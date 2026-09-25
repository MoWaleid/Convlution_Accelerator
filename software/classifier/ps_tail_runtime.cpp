// Dependency-free ARM/host runtime for the trained CNN layers after FPGA Conv1.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

const char* kClasses[] = {"airplane", "automobile", "bird", "cat", "deer",
                          "dog", "frog", "horse", "ship", "truck"};

std::string join(const std::string& root, const std::string& file) {
    if (!root.empty() && (root.back() == '/' || root.back() == '\\')) return root + file;
    return root + "/" + file;
}

template <class T>
std::vector<T> read_exact(const std::string& path, std::size_t count) {
    std::ifstream input(path.c_str(), std::ios::binary | std::ios::ate);
    if (!input) throw std::runtime_error("cannot open " + path);
    const std::streamoff expected = static_cast<std::streamoff>(count * sizeof(T));
    if (input.tellg() != expected) throw std::runtime_error("wrong byte count: " + path);
    input.seekg(0);
    std::vector<T> values(count);
    input.read(reinterpret_cast<char*>(values.data()), expected);
    if (!input) throw std::runtime_error("short read: " + path);
    return values;
}

struct Model {
    int channels;
    std::vector<float> conv2_w, conv2_b;
    std::vector<float> conv3_w, conv3_b;
    std::vector<float> fc1_w, fc1_b;
    std::vector<float> fc2_w, fc2_b;

    Model(const std::string& root, int k) : channels(k) {
        if (k != 8 && k != 16) throw std::runtime_error("channels must be 8 or 16");
        conv2_w = read_exact<float>(join(root, "conv2_weight.f32le"), 32u*k*3u*3u);
        conv2_b = read_exact<float>(join(root, "conv2_bias.f32le"), 32);
        conv3_w = read_exact<float>(join(root, "conv3_weight.f32le"), 32u*32u*3u*3u);
        conv3_b = read_exact<float>(join(root, "conv3_bias.f32le"), 32);
        fc1_w = read_exact<float>(join(root, "fc1_weight.f32le"), 256u*2048u);
        fc1_b = read_exact<float>(join(root, "fc1_bias.f32le"), 256);
        fc2_w = read_exact<float>(join(root, "fc2_weight.f32le"), 10u*256u);
        fc2_b = read_exact<float>(join(root, "fc2_bias.f32le"), 10);
    }
};

inline std::size_t idx3(int c, int y, int x, int h, int w) {
    return (static_cast<std::size_t>(c) * h + y) * w + x;
}

std::vector<float> pool_fpga_frame(const std::vector<std::int16_t>& frame, int k) {
    // Input is HWC/pixel-major interleaved. Pool in the exact integer domain,
    // then convert signed Q8 to the floating network scale.
    std::vector<float> output(static_cast<std::size_t>(k) * 16u * 16u);
    for (int c = 0; c < k; ++c) {
        for (int y = 0; y < 16; ++y) {
            for (int x = 0; x < 16; ++x) {
                std::int16_t best = std::numeric_limits<std::int16_t>::min();
                for (int dy = 0; dy < 2; ++dy)
                    for (int dx = 0; dx < 2; ++dx)
                        best = std::max(best, frame[((2*y+dy)*32 + (2*x+dx))*k + c]);
                output[idx3(c, y, x, 16, 16)] = static_cast<float>(best) / 256.0f;
            }
        }
    }
    return output;
}

std::vector<float> conv_same_relu(const std::vector<float>& input, int in_c,
                                  int h, int w, const std::vector<float>& weight,
                                  const std::vector<float>& bias, int out_c) {
    std::vector<float> output(static_cast<std::size_t>(out_c) * h * w);
    for (int oc = 0; oc < out_c; ++oc) {
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                float total = bias[oc];
                for (int ic = 0; ic < in_c; ++ic) {
                    for (int ky = 0; ky < 3; ++ky) {
                        const int iy = y + ky - 1;
                        if (iy < 0 || iy >= h) continue;
                        for (int kx = 0; kx < 3; ++kx) {
                            const int ix = x + kx - 1;
                            if (ix < 0 || ix >= w) continue;
                            const std::size_t wi = (((static_cast<std::size_t>(oc)*in_c + ic)*3 + ky)*3 + kx);
                            total += input[idx3(ic, iy, ix, h, w)] * weight[wi];
                        }
                    }
                }
                output[idx3(oc, y, x, h, w)] = std::max(total, 0.0f);
            }
        }
    }
    return output;
}

std::vector<float> maxpool2(const std::vector<float>& input, int channels, int h, int w) {
    std::vector<float> output(static_cast<std::size_t>(channels) * (h/2) * (w/2));
    for (int c = 0; c < channels; ++c)
        for (int y = 0; y < h/2; ++y)
            for (int x = 0; x < w/2; ++x) {
                float best = -std::numeric_limits<float>::infinity();
                for (int dy = 0; dy < 2; ++dy)
                    for (int dx = 0; dx < 2; ++dx)
                        best = std::max(best, input[idx3(c, 2*y+dy, 2*x+dx, h, w)]);
                output[idx3(c, y, x, h/2, w/2)] = best;
            }
    return output;
}

std::vector<float> linear_relu(const std::vector<float>& input,
                               const std::vector<float>& weight,
                               const std::vector<float>& bias, int outputs) {
    const int inputs = static_cast<int>(input.size());
    std::vector<float> result(outputs);
    for (int o = 0; o < outputs; ++o) {
        float total = bias[o];
        const float* row = &weight[static_cast<std::size_t>(o) * inputs];
        for (int i = 0; i < inputs; ++i) total += row[i] * input[i];
        result[o] = std::max(total, 0.0f);
    }
    return result;
}

std::vector<float> classify(const Model& model, const std::vector<std::int16_t>& frame) {
    std::vector<float> x = pool_fpga_frame(frame, model.channels);
    x = conv_same_relu(x, model.channels, 16, 16, model.conv2_w, model.conv2_b, 32);
    x = maxpool2(x, 32, 16, 16);
    x = conv_same_relu(x, 32, 8, 8, model.conv3_w, model.conv3_b, 32);
    x = linear_relu(x, model.fc1_w, model.fc1_b, 256);
    std::vector<float> logits(10);
    for (int o = 0; o < 10; ++o) {
        float total = model.fc2_b[o];
        const float* row = &model.fc2_w[static_cast<std::size_t>(o) * 256u];
        for (int i = 0; i < 256; ++i) total += row[i] * x[i];
        logits[o] = total;
    }
    return logits;
}

void emit_json(const std::vector<float>& logits, double elapsed_ms) {
    const float maximum = *std::max_element(logits.begin(), logits.end());
    std::vector<double> probability(logits.size());
    double sum = 0.0;
    for (std::size_t i = 0; i < logits.size(); ++i) {
        probability[i] = std::exp(static_cast<double>(logits[i] - maximum));
        sum += probability[i];
    }
    for (double& value : probability) value /= sum;
    std::vector<int> order(10);
    for (int i = 0; i < 10; ++i) order[i] = i;
    std::sort(order.begin(), order.end(), [&](int a, int b) { return probability[a] > probability[b]; });

    std::cout << std::setprecision(9)
              << "{\"status\":\"PASS\",\"class_index\":" << order[0]
              << ",\"class_name\":\"" << kClasses[order[0]]
              << "\",\"confidence\":" << probability[order[0]]
              << ",\"tail_ms\":" << elapsed_ms << ",\"logits\":[";
    for (int i = 0; i < 10; ++i) {
        if (i) std::cout << ',';
        std::cout << logits[i];
    }
    std::cout << "],\"top3\":[";
    for (int rank = 0; rank < 3; ++rank) {
        if (rank) std::cout << ',';
        const int i = order[rank];
        std::cout << "{\"class_index\":" << i << ",\"class_name\":\""
                  << kClasses[i] << "\",\"confidence\":" << probability[i] << '}';
    }
    std::cout << "]}\n";
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 4) {
            std::cerr << "usage: conv-classify-tail BUNDLE_DIR CHANNELS FRAME.s16le\n";
            return 2;
        }
        const int channels = std::stoi(argv[2]);
        const Model model(argv[1], channels);
        const std::vector<std::int16_t> frame =
            read_exact<std::int16_t>(argv[3], 32u * 32u * static_cast<unsigned>(channels));
        const auto start = std::chrono::steady_clock::now();
        const std::vector<float> logits = classify(model, frame);
        const auto stop = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double, std::milli>(stop - start).count();
        emit_json(logits, elapsed);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "conv-classify-tail: " << error.what() << '\n';
        return 1;
    }
}
