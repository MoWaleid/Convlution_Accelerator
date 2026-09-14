# B32_CFGLUT100 build attempts — 2026-09-14

## Attempt 1: fail-closed before synthesis

The isolated build applied 100 MHz to the PS correctly, then block-design
validation rejected the module-reference adapter because its clock interface
metadata still declared a fixed 125 MHz. Vivado reported `BD 41-237` frequency
mismatches on the clock, AXI-Lite, MM2S, and S2MM interfaces. No synthesis,
implementation, bitstream generation, or hardware operation occurred.

Resolution: remove only the stale `FREQ_HZ 125000000` annotation from
`conv_axis_wrapper_bd.v`. The PS FCLK connected by the block design is now the
single frequency authority. Accelerator logic, port widths, addressing, and
the numerical datapath are unchanged. A focused regression asserts that the
wrapper metadata remains profile-agnostic.

## Attempt 2: routed build PASS

The clean retry completed the full fail-closed flow at 100 MHz:

- WNS: `+0.764 ns`
- WHS: `+0.011 ns`
- DRC errors: 0
- Routing errors: 0
- BIT SHA-256:
  `a4c1a1836eb42553e6eec3c4d588bdc912480cb0ee1d933f50f52053c9fff900`
- FPGA-Manager BIT.BIN SHA-256:
  `fe603bd161a37297d256518a10c742439eef3eececd583acf757e94ffdde0dad`
- XSA SHA-256:
  `fc33afa0696de2abb3ee682ff10a464ef4bf8bca17292d984da89bff3b964840`

Vivado emitted the same non-gating unused-board-port critical warnings
documented for B32_CFGLUT125. The explicit routed DRC gate reported zero
errors. Board validation remains `NOT_RUN`.
