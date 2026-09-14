# CFGLUT5 3x3/5x5 geometry generalization — 2026-09-14

Status: **RTL GEOMETRY REGRESSION PASS; physical builds and board validation
not yet run.**

## Scope

The deterministic Dadda generator now emits two exact structural entities:

| Entity | Taps / signed rows | Sum width | Dadda targets | Register boundaries | Canonical LF SHA-256 |
|---|---:|---:|---|---|---|
| `cfglut5_bitheap_3x3` | 9 / 18 | 21 | 13,9,6,4,3,2 | after level 3 | `ad49b5405d3d07736534622e063b732b7463011dac55855b2eb8a5d6af627aa7` |
| `cfglut5_bitheap_5x5` | 25 / 50 | 22 | 42,28,19,13,9,6,4,3,2 | after levels 3 and 6 | `b94b8e7a9df124b6084d48383b88bf74dfd1e12f4dd32ca0850a590197bf4135` |

The generated 3x3 text is byte-identical to the canonical pre-change Git
blob. Windows working-tree CRLF conversion changes the checkout byte hash,
so the comparison was made against `git show HEAD:<path>` and the generated
UTF-8/LF bytes.

`conv_channel.vhd` selects the matching entity at elaboration for N=3 or
N=5. Its sum and accumulator widths are derived from the selected generic N,
not from a possibly different global build projection. `conv_engine.vhd`
admits exactly N=3 or N=5. The N=5 compressor adds one valid-aligned register
boundary; all stages freeze together under CE backpressure.

## User-executed Vivado 2025.2 evidence

Runner: `scripts/research_release/test_cfglut_geometries.tcl`

Isolated project:
`work/cfglut_geometry_regression_1789402423/`

The user supplied the complete Tcl transcript. Its terminal markers were:

```text
CFGLUT_GEOMETRY_TEST_PASS: tb_cfglut5_exact
PIPELINE_125_PASS shifts=32 bias_cases=16 relu_modes=2 outputs=5120
CFGLUT_GEOMETRY_TEST_PASS: tb_cfglut5_pipeline
Exact 5x5 CFGLUT5 reload/backpressure regression passed
CFGLUT_GEOMETRY_TEST_PASS: tb_cfglut5_exact_n5
PIPELINE_N5_125_PASS shifts=32 bias_cases=16 relu_modes=2 outputs=6144
CFGLUT_GEOMETRY_TEST_PASS: tb_cfglut5_pipeline_n5
CFGLUT_GEOMETRY_REGRESSION_PASS
GEOMETRY RESULT: 0
```

Coverage includes nonzero exact 3x3 and 5x5 convolution, runtime coefficient
reload, signed-24 bias, all 32 shift values, both ReLU modes, saturation
boundaries, CE stalls, valid latency, and in-flight reset flushing.

## Boundary of this evidence

This result proves behavioral RTL arithmetic/control for both generated
geometries. It does not prove synthesis, resource fit, 125 MHz timing closure,
full wrapper framing, physical edge-free behavior, FPGA Manager switching, or
board correctness for A32/C32/D32/D640. Those remain separate release gates.
