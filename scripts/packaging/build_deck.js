const pptxgen = require("pptxgenjs");

const W = 13.33, H = 7.5, M = 0.55;
// Palette: silicon-die graphite, PCB teal, signal amber
const BG_DARK = "141B26", BG_LIGHT = "F7F8FA", PRIMARY = "0E7C7B",
      ACCENT = "E8A33D", TEXT = "1E293B", MUTED = "64748B",
      LIGHT_ON_DARK = "E8EDF2", CARD = "FFFFFF", TINT = "E6F2F1";
const F = "Arial";
const shadow = () => ({ type: "outer", color: "0A0F14", blur: 7, offset: 2, angle: 55, opacity: 0.18 });

let p = new pptxgen();
p.layout = "LAYOUT_WIDE";
p.author = "SSCS Egypt 2026 Submission";
p.title = "Exact CFGLUT5 CNN Convolution Accelerator";

function titleSlide() {
  const s = p.addSlide();
  s.background = { color: BG_DARK };
  s.addText("IEEE SSCS Egypt Chapter — 2026 Student Design Competition", {
    x: M, y: 0.75, w: W - 2*M, h: 0.4, fontFace: F, fontSize: 15,
    color: ACCENT, charSpacing: 2, margin: 0 });
  s.addText("Exact CFGLUT5 CNN\nConvolution Accelerator", {
    x: M, y: 1.55, w: W - 2*M, h: 2.5, fontFace: F, fontSize: 54, bold: true,
    color: "FFFFFF", margin: 0, lineSpacing: 62 });
  s.addText("Five board-qualified releases · 125 MHz · zero DSP · bit-exact against the golden model", {
    x: M, y: 4.15, w: W - 2*M, h: 0.5, fontFace: F, fontSize: 19, color: LIGHT_ON_DARK, margin: 0 });
  const stats = [
    ["5", "qualified releases"], ["2,543", "bit-exact frames on silicon"],
    ["0", "DSP blocks"], ["125 MHz", "FCLK0 on ZedBoard"],
  ];
  stats.forEach((st, i) => {
    const x = M + i * ((W - 2*M) / 4);
    s.addText(st[0], { x, y: 5.0, w: (W-2*M)/4 - 0.3, h: 0.95, fontFace: F,
      fontSize: 44, bold: true, color: ACCENT, margin: 0 });
    s.addText(st[1], { x, y: 5.95, w: (W-2*M)/4 - 0.3, h: 0.6, fontFace: F,
      fontSize: 13.5, color: LIGHT_ON_DARK, margin: 0 });
  });
  s.addText("Team submission · ZedBoard (Zynq-7020 XC7Z020) · VHDL-2008 · Vivado 2025.2", {
    x: M, y: 6.85, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 12, color: MUTED, margin: 0 });
}

function specSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("The competition problem", { x: M, y: 0.45, w: 8.5, h: 0.7,
    fontFace: F, fontSize: 32, bold: true, color: TEXT, margin: 0 });
  s.addText("An FPGA NxN CNN convolution accelerator for edge-AI vision — every mandatory spec met, then taken further.", {
    x: M, y: 1.15, w: W - 2*M, h: 0.6, fontFace: F, fontSize: 16, color: MUTED, margin: 0 });
  const specs = [
    ["32×32+", "grayscale input", "shipped up to 640×480"],
    ["Q0.8", "unsigned 8-bit pixels", "justified: digit-LUT addressing"],
    ["int8", "signed programmable kernels", "reconfigured in the LUT itself"],
    ["stride 1", "same-mode zero padding", "edge-free windowing"],
    ["≥16-bit", "signed outputs", "int16, exact 25-bit accumulator"],
    ["golden", "Python bit-exact reference", "arbitrary-precision, 3rd independent impl"],
  ];
  const cw = (W - 2*M - 0.5) / 3, ch = 1.55;
  specs.forEach((sp, i) => {
    const x = M + (i % 3) * (cw + 0.25), y = 2.0 + Math.floor(i / 3) * (ch + 0.3);
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y, w: cw, h: ch, rectRadius: 0.06,
      fill: { color: CARD }, line: { color: "D8DEE6", width: 1 }, shadow: shadow() });
    s.addText(sp[0], { x: x + 0.22, y: y + 0.15, w: cw - 0.44, h: 0.6, fontFace: F,
      fontSize: 26, bold: true, color: PRIMARY, margin: 0 });
    s.addText(sp[1], { x: x + 0.22, y: y + 0.78, w: cw - 0.44, h: 0.35, fontFace: F,
      fontSize: 13, bold: true, color: TEXT, margin: 0 });
    s.addText(sp[2], { x: x + 0.22, y: y + 1.12, w: cw - 0.44, h: 0.35, fontFace: F,
      fontSize: 12, color: MUTED, margin: 0 });
  });
  s.addText("Bonuses delivered: on-board demonstration · multiple kernels (5 releases) · ReLU · edge-detection demo · one-position-per-cycle core", {
    x: M, y: 5.95, w: W - 2*M, h: 0.5, fontFace: F, fontSize: 13.5, color: TEXT, margin: 0 });
  s.addText("Source: 2026 SSCS Egypt Competition Announcement, Required Specifications 1–10", {
    x: M, y: 6.9, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function archSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("System architecture", { x: M, y: 0.45, w: 8, h: 0.65,
    fontFace: F, fontSize: 32, bold: true, color: TEXT, margin: 0 });
  s.addImage({ path: "report/figures/fig1_blockdesign.png",
    x: M, y: 1.35, w: 8.1, h: 4.55, sizing: { type: "contain", w: 8.1, h: 4.55 } });
  const notes = [
    ["PS7 + DMA", "Cortex-A9 drives parameters over AXI4-Lite; frames stream via S_AXI_HP0 DMA"],
    ["Accelerator", "AXI-Stream in/out; edge-free window generator; K exact CFGLUT5 channels"],
    ["Runtime swap", "Zynq FPGA Manager reloads the full fabric in ~183 ms between releases"],
  ];
  notes.forEach((n, i) => {
    const y = 1.35 + i * 1.6;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: 9.0, y, w: 3.8, h: 1.4, rectRadius: 0.06,
      fill: { color: TINT }, line: { color: PRIMARY, width: 1 } });
    s.addText(n[0], { x: 9.2, y: y + 0.12, w: 3.4, h: 0.4, fontFace: F, fontSize: 15,
      bold: true, color: PRIMARY, margin: 0 });
    s.addText(n[1], { x: 9.2, y: y + 0.52, w: 3.4, h: 0.8, fontFace: F, fontSize: 11.5,
      color: TEXT, margin: 0 });
  });
  s.addText("Figure 1 — accelerator_dma block design, Vivado 2025.2", {
    x: M, y: 6.35, w: 8, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function datapathSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("Exact datapath: multiply in the LUT, compress with Dadda", {
    x: M, y: 0.45, w: W - 2*M, h: 0.65, fontFace: F, fontSize: 30, bold: true, color: TEXT, margin: 0 });
  s.addImage({ path: "report/figures/fig2_pipeline.png",
    x: M, y: 1.3, w: 12.2, h: 2.85, sizing: { type: "contain", w: 12.2, h: 2.85 } });
  const facts = [
    ["Weight = LUT configuration", "Each 8×8 tap product is a radix-16 lookup in six CFGLUT5 primitives — coefficients are reprogrammed through the LUT configuration chain (32 clocks/bank), no DSP48s."],
    ["Exact Dadda compression", "A generated, column-aware bit heap (183 full + 13 half LUT6_2 compressors at N=3) reduces 18 signed rows to an exact 21-bit sum pair — no truncation before the bias."],
    ["Exact at every shift", "S4 registers the discarded half-bit; S5's round-half-up consumes it. Shifts 24–31 verified exact on silicon — a restriction the predecessor MAC datapath could not lift."],
  ];
  facts.forEach((f, i) => {
    const x = M + i * ((W - 2*M - 0.5) / 3), w = (W - 2*M - 0.5) / 3;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y: 4.45, w, h: 2.0, rectRadius: 0.06,
      fill: { color: CARD }, line: { color: "D8DEE6", width: 1 }, shadow: shadow() });
    s.addText(f[0], { x: x + 0.2, y: 4.6, w: w - 0.4, h: 0.5, fontFace: F, fontSize: 14.5,
      bold: true, color: PRIMARY, margin: 0 });
    s.addText(f[1], { x: x + 0.2, y: 5.1, w: w - 0.4, h: 1.25, fontFace: F, fontSize: 11,
      color: TEXT, margin: 0 });
  });
  s.addText("Figure 2 — per-channel pipeline [S10: conv_channel.vhd, generated cfglut5_bitheap_* entities]", {
    x: M, y: 6.65, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function edgeSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("Edge-free windowing — measured, disclosed", {
    x: M, y: 0.45, w: W - 2*M, h: 0.65, fontFace: F, fontSize: 30, bold: true, color: TEXT, margin: 0 });
  s.addText("Prefetch keeps the core supplied across row transitions. The wrapper regression measures exactly how clean each release is (frame D = continuous-supply stress):", {
    x: M, y: 1.15, w: W - 2*M, h: 0.65, fontFace: F, fontSize: 14.5, color: MUTED, margin: 0 });
  const rows = [
    [{ text: "Release", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
     { text: "Invalid core advances", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
     { text: "External output gaps", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
     { text: "Disclosed consequence", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } }],
    ["B32 (3×16)", "0", "0", "edge-free proven end-to-end"],
    ["A32 (3×8)", "31", "0", "bubbles hidden by output prefetch — externally gapless"],
    ["C32 (5×8)", "62", "31", "exact, ~1.5% transition bubbles disclosed"],
    ["D32 (3×4)", "62", "62", "exact, ~6% transition bubbles disclosed"],
    ["D640 (3×4 VGA)", "958", "958", "exact, ~0.3% of beats — disclosed"],
  ];
  s.addTable(rows, { x: M, y: 2.0, w: W - 2*M, colW: [2.4, 2.6, 2.6, 4.5],
    fontFace: F, fontSize: 13.5, color: TEXT, border: { pt: 0.5, color: "C9D2DC" },
    fill: { color: CARD }, rowH: 0.52, margin: 0.08, valign: "middle" });
  s.addText([
    { text: "Claim discipline: ", options: { bold: true, color: TEXT } },
    { text: "every delivered value is bit-exact in all five releases. The zero-gap claim is made only where measured; the rest is disclosed, not claimed away.", options: { color: TEXT } },
  ], { x: M, y: 5.9, w: W - 2*M, h: 0.7, fontFace: F, fontSize: 14, margin: 0 });
  s.addText("Source: five-release wrapper regression, official run wrapper_official_user_20260914T210835Z (16/16 checksums verified)", {
    x: M, y: 6.85, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function releasesSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("Five compiled releases — one RTL, one constraint, five bitstreams", {
    x: M, y: 0.45, w: W - 2*M, h: 0.65, fontFace: F, fontSize: 28, bold: true, color: TEXT, margin: 0 });
  const rows = [[
    { text: "Release", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
    { text: "Shape", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
    { text: "WNS / WHS (ns)", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
    { text: "LUTs (sys / core)", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
    { text: "DSP", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
    { text: "Power (W)", options: { bold: true, color: "FFFFFF", fill: { color: PRIMARY } } },
  ],
  ["D640 (3×4, 640×480)", "N3K4W640H480", "+0.001 / +0.022", "7,679 / 3,281", "0", "1.769"],
  ["D32 (3×4, 32×32)", "N3K4W32H32", "+0.093 / +0.014", "7,273 / 2,883", "0", "1.768"],
  ["A32 (3×8, 32×32)", "N3K8W32H32", "+0.197 / +0.037", "9,145 / 4,746", "0", "1.785"],
  ["B32 (3×16, 32×32)", "N3K16W32H32", "+0.090 / +0.053", "12,670 / 8,274", "0", "1.806"],
  ["C32 (5×8, 32×32)", "N5K8W32H32", "+0.003 / +0.037", "14,162 / 9,764", "0", "1.823"]];
  s.addTable(rows, { x: M, y: 1.4, w: W - 2*M, colW: [2.9, 2.2, 2.1, 2.4, 0.9, 1.6],
    fontFace: F, fontSize: 13, color: TEXT, border: { pt: 0.5, color: "C9D2DC" },
    fill: { color: CARD }, rowH: 0.55, margin: 0.08, valign: "middle" });
  s.addText([
    { text: "One source of truth: ", options: { bold: true, color: TEXT } },
    { text: "all five bitstreams build from the same generalized RTL and the same 125 MHz constraint; every artifact is hash-bound in a source-bound build manifest, and every bitstream the board executed is the Bootgen product of exactly that bitstream.", options: { color: TEXT } },
  ], { x: M, y: 5.15, w: W - 2*M, h: 0.85, fontFace: F, fontSize: 14, margin: 0 });
  s.addText("Trained parameters per release: K8 68.15% · K16 70.08% · N5 67.72% (CIFAR-10 grayscale) · D-set hand-authored identity/Sobel/blur", {
    x: M, y: 6.2, w: W - 2*M, h: 0.5, fontFace: F, fontSize: 13, color: MUTED, margin: 0 });
  s.addText("Source: per-release routed build reports (timing/power/utilization/DRC), hash-verified", {
    x: M, y: 6.9, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function qualSlide() {
  const s = p.addSlide();
  s.background = { color: BG_DARK };
  s.addText("Qualified on silicon — the G5 campaign", { x: M, y: 0.5, w: W - 2*M, h: 0.7,
    fontFace: F, fontSize: 32, bold: true, color: "FFFFFF", margin: 0 });
  const gates = [
    ["577", "bit-exact frames, zero mismatches — anchors, 60 exact-reference extremes, five 100-frame soaks"],
    ["58", "full-PL reloads in one matrix — all 20 ordered release pairs, 20 provably consecutive A32↔B32 cycles"],
    ["125 MHz", "re-verified from SLCR registers after a true power-cycle cold boot"],
    ["2+2", "hardware fault paths injected (ABORT-from-IDLE, ABORT race) — clean RESET recovery, anchor-exact proof frames"],
  ];
  gates.forEach((g, i) => {
    const y = 1.55 + i * 1.32;
    s.addText(g[0], { x: M, y, w: 2.6, h: 1.1, fontFace: F, fontSize: 40, bold: true,
      color: ACCENT, margin: 0 });
    s.addText(g[1], { x: 3.4, y: y + 0.12, w: W - 3.4 - M, h: 1.0, fontFace: F,
      fontSize: 15.5, color: LIGHT_ON_DARK, margin: 0 });
    if (i < 3) s.addShape(p.shapes.LINE, { x: M, y: y + 1.22, w: W - 2*M, h: 0,
      line: { color: "2A3648", width: 0.75 } });
  });
  s.addText("Verbatim transcript + 17 hashed run records preserved in the submission package (docs/board_evidence/)", {
    x: M, y: 6.95, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function fomSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("Figure of Merit — two honest scopes", { x: M, y: 0.45, w: W - 2*M, h: 0.65,
    fontFace: F, fontSize: 30, bold: true, color: TEXT, margin: 0 });
  s.addText("FOM = Throughput / (Power × (LUTs + 50·DSP + 100·BRAM)) · throughput in valid output values per clock cycle", {
    x: M, y: 1.1, w: W - 2*M, h: 0.45, fontFace: F, fontSize: 13.5, color: MUTED, margin: 0 });
  s.addChart(p.charts.BAR, [{
    name: "Accelerator core FOM",
    labels: ["D32", "D640", "A32", "B32", "C32"],
    values: [9.25e-2, 7.17e-2, 6.02e-2, 3.95e-2, 1.26e-2],
  }], {
    x: M, y: 1.75, w: 6.0, h: 3.9, barDir: "col", varyColors: true,
    chartColors: ["0E7C7B", "0E7C7B", "0E7C7B", "0E7C7B", "0E7C7B"],
    showValue: true, dataLabelPosition: "outEnd", dataLabelColor: "1E293B",
    dataLabelFormatCode: "0.00e+00",
    catAxisLabelColor: MUTED, valAxisLabelColor: MUTED,
    valGridLine: { color: "E2E8F0", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: true, title: "Accelerator core scope",
    titleFontSize: 13, titleColor: TEXT, chartArea: { fill: { color: BG_LIGHT } },
  });
  s.addChart(p.charts.BAR, [{
    name: "Full-system FOM",
    labels: ["D640", "D32", "A32", "B32", "C32"],
    values: [2.825e-4, 2.807e-4, 2.373e-4, 1.708e-4, 1.494e-4],
  }], {
    x: 6.9, y: 1.75, w: 6.0, h: 3.9, barDir: "col", varyColors: true,
    chartColors: ["E8A33D", "E8A33D", "E8A33D", "E8A33D", "E8A33D"],
    showValue: true, dataLabelPosition: "outEnd", dataLabelColor: "1E293B",
    dataLabelFormatCode: "0.00e+00",
    catAxisLabelColor: MUTED, valAxisLabelColor: MUTED,
    valGridLine: { color: "E2E8F0", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: true, title: "Full system (64-bit bus-limited)",
    titleFontSize: 13, titleColor: TEXT, chartArea: { fill: { color: BG_LIGHT } },
  });
  s.addText("Accelerator core: design rate K outputs/cycle, core power and LUTs. Full system: the 64-bit DMA output bus carries 4 int16/beat (4 outputs/cycle), derated by disclosed gaps; system power and LUTs. Vectorless Vivado power; BRAM = 3 RAMB36-eq. All inputs machine-extracted from hash-bound routed reports.", {
    x: M, y: 5.85, w: W - 2*M, h: 0.85, fontFace: F, fontSize: 11.5, color: TEXT, margin: 0 });
  s.addText("Source: fom_table.py over the five hash-bound routed reports", {
    x: M, y: 6.85, w: W - 2*M, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function tradeoffSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("Design trade-offs", { x: M, y: 0.45, w: 8, h: 0.65,
    fontFace: F, fontSize: 32, bold: true, color: TEXT, margin: 0 });
  const rows = [
    ["Exact LUT multiplication vs DSP48", "All multiplication is CFGLUT5 configuration lookup — 0 DSP in every release, FOM DSP term zero. Cost: up to 14,162 LUT (26.6%) at the 25-tap shape."],
    ["The compressor is smaller than the MAC it replaced", "Same K=8 shape: 9,145 vs 12,362 system LUTs (−26%) at 125 vs 100 MHz — and shifts 24–31 became exact by construction."],
    ["Zero-BRAM datapath", "SRL line buffers + LUT windowing: the only BRAM is the DMA's 3 blocks. Windowing cost is pure LUT."],
    ["Fail-stop + self-checking frames", "Illegal accesses are SLVERR in RTL and process-fatal in the platform; the core faults itself if frame counters miss the compiled quotas."],
    ["Disclosed beats claimed", "Edge bubbles at K=4 are measured and printed (§3.4 of the report) instead of claimed away — the zero-gap claim is limited to where it was proven."],
  ];
  rows.forEach((r, i) => {
    const y = 1.35 + i * 1.12;
    s.addText(r[0], { x: M, y, w: 4.6, h: 1.0, fontFace: F, fontSize: 15, bold: true,
      color: PRIMARY, margin: 0 });
    s.addText(r[1], { x: 5.35, y: y + 0.02, w: W - 5.35 - M, h: 1.0, fontFace: F,
      fontSize: 12.5, color: TEXT, margin: 0 });
    if (i < rows.length - 1) s.addShape(p.shapes.LINE, { x: M, y: y + 1.0,
      w: W - 2*M, h: 0, line: { color: "D8DEE6", width: 0.75 } });
  });
}

function demoSlide() {
  const s = p.addSlide();
  s.background = { color: BG_LIGHT };
  s.addText("On-board demonstration", { x: M, y: 0.45, w: 8, h: 0.65,
    fontFace: F, fontSize: 32, bold: true, color: TEXT, margin: 0 });
  s.addImage({ path: "debug_captures/m3_demo_sobel_mag_aeroplane_view.png",
    x: M, y: 1.4, w: 6.2, h: 4.65, sizing: { type: "contain", w: 6.2, h: 4.65 } });
  const pts = [
    ["Sobel maps rendered from silicon", "The board computed the magnitude map and returned it over DMA; Linux rendered the PNG from the raw hardware output."],
    ["D-profiles = edge-detection demo", "The qualified D32/D640 releases carry identity / Sobel-X / Sobel-Y / blur kernels — an industrial-inspection style demo in hardware."],
    ["575-frame final campaign", "Anchors, extremes, soaks, switching matrix, cold boot and fault recovery — all bit-exact against the Python golden model."],
  ];
  pts.forEach((pt, i) => {
    const y = 1.5 + i * 1.6;
    s.addText(pt[0], { x: 7.1, y, w: 5.6, h: 0.5, fontFace: F, fontSize: 16,
      bold: true, color: PRIMARY, margin: 0 });
    s.addText(pt[1], { x: 7.1, y: y + 0.5, w: 5.6, h: 0.9, fontFace: F, fontSize: 12.5,
      color: TEXT, margin: 0 });
  });
  s.addText("Figure 4 — board-computed Sobel magnitude map (aeroplane test image)", {
    x: M, y: 6.3, w: 6.2, h: 0.35, fontFace: F, fontSize: 11, color: MUTED, margin: 0 });
}

function closeSlide() {
  const s = p.addSlide();
  s.background = { color: BG_DARK };
  s.addText("Everything the rules ask for,\nverified past the requirements.", {
    x: M, y: 1.1, w: W - 2*M, h: 2.0, fontFace: F, fontSize: 40, bold: true,
    color: "FFFFFF", margin: 0, lineSpacing: 50 });
  const items = [
    "Correctness — bit-exact against an arbitrary-precision golden model, 2,543 frames on silicon, zero mismatches",
    "Quality — exact CFGLUT5 compressor datapath, edge-free windowing, fail-stop CVH1 control, deterministic generated RTL",
    "Efficiency — 0 DSP, 3 BRAM (DMA only), 125 MHz with positive slack on all five releases, FOM reported at two transparent scopes",
    "Demonstration — five live releases with runtime full-FPGA switching, Sobel edge demo, fault-injection recovery",
  ];
  items.forEach((it, i) => {
    const y = 3.35 + i * 0.82;
    s.addShape(p.shapes.OVAL, { x: M + 0.05, y: y + 0.09, w: 0.16, h: 0.16, fill: { color: ACCENT } });
    s.addText(it, { x: M + 0.45, y, w: W - 2*M - 0.45, h: 0.75, fontFace: F,
      fontSize: 14.5, color: LIGHT_ON_DARK, margin: 0 });
  });
  s.addText("Full evidence chain in the submission package: source-bound build manifests, hashed run records, verbatim transcripts", {
    x: M, y: 6.85, w: W - 2*M, h: 0.4, fontFace: F, fontSize: 12, color: MUTED, margin: 0 });
}

titleSlide(); specSlide(); archSlide(); datapathSlide(); edgeSlide();
releasesSlide(); qualSlide(); fomSlide(); tradeoffSlide(); demoSlide(); closeSlide();

p.writeFile({ fileName: "submission/docs/presentation.pptx" })
  .then(() => console.log("deck written"));
