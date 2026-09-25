"use strict";

const state = {
  profiles: [], selected: null, source: "board", boardImages: [], selectedImage: null,
  job: null, poller: null,
};
const $ = (selector) => document.querySelector(selector);

async function api(path, options = {}) {
  const response = await fetch(path, options);
  let body;
  try { body = await response.json(); } catch { body = {}; }
  if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
  return body;
}

function fmt(value, digits = 3) {
  return Number.isFinite(Number(value)) ? `${Number(value).toFixed(digits)} ms` : "—";
}

function setConnection(online, hostname = "") {
  const node = $("#connection");
  node.className = `connection ${online ? "online" : "offline"}`;
  node.querySelector("span").textContent = online ? `Board online${hostname ? ` · ${hostname}` : ""}` : "Board unavailable";
}

function renderProfiles() {
  const host = $("#profiles");
  host.textContent = "";
  state.profiles.forEach((profile) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `profile${state.selected === profile.id ? " selected" : ""}`;
    button.setAttribute("role", "radio");
    button.setAttribute("aria-checked", state.selected === profile.id ? "true" : "false");
    button.innerHTML = `<strong>${profile.label}</strong><span>${profile.W} × ${profile.H} · ${profile.N}×${profile.N} · ${profile.K} channels</span><em>${profile.clock_mhz} MHz · QUALIFIED</em>`;
    button.addEventListener("click", () => { state.selected = profile.id; renderProfiles(); validateFile(); });
    host.appendChild(button);
  });
}

function switchSource(source) {
  state.source = source;
  document.querySelectorAll(".source-tab").forEach((button) => {
    const active = button.dataset.source === source;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", active ? "true" : "false");
  });
  $("#board-source").classList.toggle("hidden", source !== "board");
  $("#library-source").classList.toggle("hidden", source !== "library");
  $("#upload-source").classList.toggle("hidden", source !== "upload");
  validateFile();
}

function formatBytes(value) {
  if (!Number.isFinite(Number(value))) return "";
  if (value < 1024) return `${value} B`;
  return `${(value / 1024).toFixed(1)} KiB`;
}

function renderBoardImages() {
  const select = $("#board-image");
  const previous = state.selectedImage;
  select.textContent = "";
  if (!state.boardImages.length) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "No PNG/JPEG images found in approved board directories";
    select.appendChild(option);
    state.selectedImage = null;
  } else {
    state.boardImages.forEach((image) => {
      const option = document.createElement("option");
      option.value = image.id;
      option.textContent = `${image.collection} / ${image.relative_path}`;
      select.appendChild(option);
    });
    state.selectedImage = state.boardImages.some((image) => image.id === previous)
      ? previous : state.boardImages[0].id;
    select.value = state.selectedImage;
  }
  updateBoardImagePreview();
}

function updateBoardImagePreview() {
  state.selectedImage = $("#board-image").value || null;
  const image = state.boardImages.find((item) => item.id === state.selectedImage);
  const preview = $("#board-image-preview");
  if (!image) {
    preview.removeAttribute("src");
    preview.classList.remove("visible");
    $("#board-image-name").textContent = "No board image selected";
    $("#board-image-meta").textContent = "Copy PNG/JPEG files into an approved image directory, then press Refresh.";
  } else {
    preview.src = image.content_url;
    preview.classList.add("visible");
    $("#board-image-name").textContent = image.name;
    $("#board-image-meta").textContent = `${image.collection} / ${image.relative_path} · ${formatBytes(image.size_bytes)}`;
  }
  validateFile();
}

function validateFile() {
  const file = $("#image-file").files[0];
  const message = $("#validation");
  message.textContent = "";
  if (state.source === "upload") {
    if (!file) message.textContent = "Select an image before running.";
    else if (file.size > 8 * 1024 * 1024) message.textContent = "The image exceeds the 8 MiB limit.";
  } else if (state.source === "board" && !state.selectedImage) {
    message.textContent = "No compatible image was found in the approved board directories.";
  }
  $("#file-choice").textContent = file ? `${file.name} · ${(file.size / 1024).toFixed(1)} KiB` : "No file selected";
  return !message.textContent;
}

function showRunning(job) {
  $("#result-title").textContent = `${job.mode === "benchmark" ? "Benchmarking" : "Running"} ${job.profile}`;
  $("#outcome").className = "outcome running";
  $("#outcome").textContent = "RUNNING";
  $("#job-progress").classList.remove("hidden");
  $("#job-message").textContent = job.mode === "benchmark"
    ? "Collecting warm, repeated frame measurements…"
    : "Switching if needed, validating identity, and processing frames…";
  $("#run").disabled = true;
  $("#benchmark").disabled = true;
}

function closeFeatureMap() {
  const dialog = $("#feature-map-dialog");
  if (dialog.open && typeof dialog.close === "function") dialog.close();
  else dialog.removeAttribute("open");
}

function openFeatureMap(preview, caption) {
  const dialog = $("#feature-map-dialog");
  const image = $("#feature-map-image");
  const download = $("#feature-map-download");
  $("#feature-map-title").textContent = caption;
  image.src = preview.url;
  image.alt = `Enlarged ${caption}`;
  download.href = preview.url;
  download.download = preview.name;
  if (typeof dialog.showModal === "function") dialog.showModal();
  else dialog.setAttribute("open", "");
}

function renderResult(result) {
  const outcome = result.outcome || "UNKNOWN";
  const outcomeClass = outcome === "PASS" ? "pass" : outcome === "UNVERIFIED" ? "unverified" : "fail";
  $("#result-title").textContent = result.run_id || "Completed operation";
  $("#outcome").className = `outcome ${outcomeClass}`;
  $("#outcome").textContent = outcome;
  const metrics = $("#metrics").querySelectorAll(".metric strong");
  metrics[0].textContent = fmt(result.hardware_ms?.median);
  metrics[1].textContent = fmt(result.hardware_ms?.p95);
  metrics[2].textContent = fmt(result.wall_ms?.median);
  metrics[3].textContent = String(result.frame_count ?? "—");
  const verificationMode = result.verification?.mode;
  const verified = verificationMode === "exact_reference" || verificationMode === "anchor_sha256";
  $("#frame-count-label").textContent = verified ? "Verified frames" : "Processed frames";
  $("#frame-verification-label").textContent = verificationMode === "exact_reference"
    ? "Bit-exact software reference"
    : verificationMode === "anchor_sha256" ? "Matched qualified golden anchor"
    : "Output SHA recorded; no PS reference";
  const meta = $("#result-meta").querySelectorAll("b, code");
  meta[0].textContent = result.profile?.name || "—";
  meta[1].textContent = result.image_tag || "—";
  meta[2].textContent = result.output_sha256 || "—";
  const classification = result.classification;
  const classificationPanel = $("#classification-panel");
  classificationPanel.classList.toggle("hidden", !classification || classification.status !== "PASS");
  if (classification && classification.status === "PASS") {
    $("#classification-name").textContent = classification.class_name;
    $("#classification-confidence").textContent = `${(100 * classification.confidence).toFixed(1)}% confidence`;
    const top = $("#classification-top");
    top.textContent = "";
    (classification.top3 || []).forEach((item, index) => {
      const row = document.createElement("div");
      row.innerHTML = `<span>${index + 1}. ${item.class_name}</span><b>${(100 * item.confidence).toFixed(1)}%</b>`;
      top.appendChild(row);
    });
    $("#classification-timing").textContent =
      `FPGA Conv1 ${classification.fpga_conv1_ms.toFixed(3)} ms + PS tail ${classification.ps_tail_ms.toFixed(3)} ms = ${classification.hybrid_compute_ms.toFixed(3)} ms`;
  }
  const gallery = $("#gallery");
  gallery.textContent = "";
  const featureMaps = (result.previews || [])
    .filter((preview) => /^preview_ch\d+\.png$/.test(preview.name));
  featureMaps.forEach((preview) => {
    const figure = document.createElement("figure");
    const channel = Number(preview.name.match(/^preview_ch(\d+)\.png$/)[1]);
    const caption = `Channel ${channel}`;
    const button = document.createElement("button");
    const image = document.createElement("img");
    const label = document.createElement("figcaption");
    button.type = "button";
    button.className = "feature-map-button";
    button.setAttribute("aria-label", `Enlarge ${caption}`);
    image.alt = `${caption} display-normalized preview`;
    image.src = preview.url;
    label.textContent = caption;
    button.append(image, label);
    button.addEventListener("click", () => openFeatureMap(preview, caption));
    figure.appendChild(button);
    gallery.appendChild(figure);
  });
  $("#gallery-note").textContent = `${featureMaps.length} channel${featureMaps.length === 1 ? "" : "s"} · click to enlarge or download`;
  $("#gallery-wrap").classList.toggle("hidden", !featureMaps.length);
}

function showFailure(message) {
  $("#result-title").textContent = "Operation failed";
  $("#outcome").className = "outcome fail";
  $("#outcome").textContent = "FAILED";
  $("#validation").textContent = message;
}

async function pollJob() {
  try {
    const status = await api("/api/status");
    if (status.current && ["queued", "running"].includes(status.current.state)) return;
    clearInterval(state.poller);
    state.poller = null;
    $("#job-progress").classList.add("hidden");
    $("#run").disabled = false;
    $("#benchmark").disabled = false;
    if (status.last?.state === "complete") {
      if (status.last.run_id) renderResult(await api(`/api/results/${status.last.run_id}`));
      else renderDemoResult(status.last);
      await loadHistory();
    } else showFailure(status.last?.error || status.last?.stderr || "The board operation did not complete.");
  } catch (error) {
    clearInterval(state.poller);
    state.poller = null;
    $("#job-progress").classList.add("hidden");
    $("#run").disabled = false;
    $("#benchmark").disabled = false;
    showFailure(error.message);
  }
}

function renderDemoResult(job) {
  const stats = job.demo_metrics || {};
  renderResult({
    run_id: "demo-preview", outcome: "PASS", profile: { name: job.profile },
    image_tag: "verified-library-image", frame_count: job.frames,
    hardware_ms: stats, wall_ms: {}, output_sha256: "demo mode — board not accessed", previews: [],
  });
}

async function submitRun(mode = "run") {
  $("#validation").textContent = "";
  if (!state.selected) { $("#validation").textContent = "Choose a hardware profile."; return; }
  if (mode === "run" && !validateFile()) return;
  try {
    let job;
    const frames = mode === "benchmark" ? 100 : Number($("#frames").value);
    if (state.source === "upload" && mode === "run") {
      const file = $("#image-file").files[0];
      job = await api("/api/upload-jobs", {
        method: "POST",
        headers: { "Content-Type": "application/octet-stream", "X-Profile": state.selected,
          "X-Filename": file.name.replace(/[^\x20-\x7e]/g, "_"), "X-Frames": String(frames),
          "X-Previews": $("#previews").checked ? "1" : "0" },
        body: file,
      });
    } else {
      const boardImage = state.source === "board" && mode === "run" ? state.selectedImage : undefined;
      job = await api("/api/jobs", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode, profile: state.selected, frames, warmup: 10,
          previews: $("#previews").checked, board_image: boardImage }),
      });
    }
    state.job = job;
    showRunning(job);
    state.poller = setInterval(pollJob, 600);
  } catch (error) { showFailure(error.message); }
}

async function loadHistory() {
  const host = $("#history");
  try {
    const { results } = await api("/api/results");
    if (!results.length) { host.innerHTML = '<p class="empty">No archived runs found.</p>'; return; }
    host.textContent = "";
    results.forEach((run) => {
      const row = document.createElement("div");
      row.className = "history-row";
      const stateClass = run.outcome === "PASS" ? "pass"
        : run.outcome === "UNVERIFIED" ? "unverified" : "fail";
      row.innerHTML = `<strong>${run.profile?.name || "unknown"}</strong><span class="${stateClass}">${run.outcome}</span><span>${run.frame_count} frames</span><span>${fmt(run.hardware_ms?.median)}</span><span>${run.started_utc || ""}</span>`;
      row.addEventListener("click", async () => renderResult(await api(`/api/results/${run.run_id}`)));
      host.appendChild(row);
    });
  } catch (error) { host.innerHTML = `<p class="empty">${error.message}</p>`; }
}

async function initialize() {
  try {
    const [status, catalog, library] = await Promise.all([
      api("/api/status"), api("/api/profiles"), api("/api/images"),
    ]);
    setConnection(true, status.hostname);
    state.profiles = catalog.profiles;
    state.selected = state.profiles[0]?.id || null;
    state.boardImages = library.images || [];
    renderProfiles();
    renderBoardImages();
    $("#board-name").textContent = `${status.hostname} · Zynq-7000 · 125 MHz`;
    if (status.current && ["queued", "running"].includes(status.current.state)) {
      showRunning(status.current);
      state.poller = setInterval(pollJob, 600);
    }
    await loadHistory();
  } catch (error) { setConnection(false); showFailure(error.message); }
}

document.querySelectorAll(".source-tab").forEach((button) => button.addEventListener("click", () => switchSource(button.dataset.source)));
$("#image-file").addEventListener("change", validateFile);
$("#board-image").addEventListener("change", updateBoardImagePreview);
$("#run").addEventListener("click", () => submitRun("run"));
$("#benchmark").addEventListener("click", () => submitRun("benchmark"));
$("#refresh").addEventListener("click", initialize);
$("#feature-map-close").addEventListener("click", closeFeatureMap);
$("#feature-map-dialog").addEventListener("click", (event) => {
  if (event.target === event.currentTarget) closeFeatureMap();
});
initialize();
