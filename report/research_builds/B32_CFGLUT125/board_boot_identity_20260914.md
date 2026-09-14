# B32_CFGLUT125 boot and clock evidence — 2026-09-14

Status: boot identity and live clock configuration PASS; runtime provisioning
and functional board qualification remain NOT RUN.

## Boot artifact

- `/boot/BOOT.BIN` SHA-256:
  `b91acd41a83eba8866c4385b5ff0d0ef9e38b1ad4b6c909d32c31d03783c04c4`
- Source WIC SHA-256:
  `c99781f6e30a651c1fe878e9806f9e6b78a605eb46f0d6315516c0af6265e5f4`
- FPGA Manager name/state: `Xilinx Zynq FPGA Manager` / `operating`.

## Live accelerator discovery

| Address | Value |
|---|---|
| `0x43C04100` | `0x43564831` |
| `0x43C04104` | `0x00010000` |
| `0x43C04108` | `0x000001FF` |
| `0x43C04120` | `0x00000020` |
| `0x43C04124` | `0x00000020` |
| `0x43C04128` | `0x00000003` |
| `0x43C0412C` | `0x00000010` |
| `0x43C04138` | `0x00000484` |
| `0x43C0413C` | `0x00008000` |
| `0x43C04150` | `0x32523031` |
| `0x43C04154` | `0x4E335733` |
| `0x43C04158` | `0x354B3136` |
| `0x43C0415C` | `0x45463132` |
| `0x43C04160` | `0x00000016` |

The BUILD_ID words reconstruct to `45463132354b31364e33573332523031`,
ASCII `EF125K16N3W32R01`. Geometry is W=32, H=32, N=3, K=16;
input/output lengths are 1156/32768 bytes and DMA length width is 22.

## Live FCLK0 derivation

The deployed kernel does not provide debugfs, so the board clock was checked
from the live Zynq-7000 SLCR registers:

- `IO_PLL_CTRL` (`0xF8000108`) = `0x0001E000`: FBDIV=30.
- `PLL_STATUS` (`0xF800010C`) = `0x0000003F`.
- `FPGA0_CLK_CTRL` (`0xF8000170`) = `0x00200400`: IO PLL source,
  DIVISOR0=4 and DIVISOR1=2.

Using the ZedBoard 33.333333 MHz PS reference clock:

`FCLK0 = 33.333333 MHz * 30 / (4 * 2) = 124.99999875 MHz`, nominally
125 MHz.

## Open boundary

`B32_CFGLUT125_board_runtime_3eb5074.tar.gz` was absent from `/boot` during
this check. No runtime files were installed and no DMA or convolution frame
was executed. G2.7 and G3.3 therefore remain open.
