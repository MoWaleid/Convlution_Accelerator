# FPGA-first hybrid classifier

The FPGA produces the exact signed-Q8 first convolution. `ps_tail_runtime.cpp`
runs the trained B32 network from the first max-pool through the ten CIFAR-10
logits on the Zynq processing system. It has no NumPy, PyTorch, or third-party
runtime dependency.

The frozen tensor bundle is exported from `golden_model/data/trained_k16.pth`.
The loader and tests establish byte-for-byte equality with the checkpoint. The
native verifier compares all ten native logits and the winning class against a
frozen NumPy reference frame.

Host verification:

```sh
g++ -std=c++14 -O3 ps_tail_runtime.cpp -o conv-classify-tail
python3 verify_tail_binary.py ./conv-classify-tail
```

The PetaLinux recipe installs the executable at `/usr/bin/conv-classify-tail`
and the B32 tensor bundle at `/opt/conv-lab-classifier/B32_CFGLUT125`.
