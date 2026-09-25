# Cold-boot GUI qualification

**Team:** Attention is all you need
**Qualification date:** 2026-09-25
**Status:** PASS

The ZedBoard was halted, physically power-cycled, and allowed to boot without
manual network setup, service startup, FPGA programming, or driver recovery.
The board then completed an anchored B32 inference initiated from the browser
GUI.

## Evidence artifacts

| Artifact | SHA-256 |
|---|---|
| `cold_boot_B32_20260925_qualified_v2.tar.gz` | `11c888f3dcc2480f20c08cf77140dd1aadf8b1b49522ac16df846f4ae776ce07` |
| `cold_boot_gui_B32_PASS.png` | `c58c416ea030f14208bfd1d816b895bea36d3433f101859ba48cf3df2a461c57` |

The archive contains its own `SHA256SUMS.txt`. All 24 listed entries passed
verification again after transfer to the workstation. It contains the run
record, three raw output frames, all 16 rendered channel previews, the service
and network configurations, and textual platform/result validations. The GUI
authentication token is intentionally excluded.

## Automatically recovered state

- Ethernet interface `enx000a35001e53`: link up with carrier.
- Static board address: `192.168.0.3/24`.
- Direct host link to `192.168.0.2`: 3/3 replies, zero packet loss.
- GUI service: started automatically and listening on TCP port 8080.
- FPGA Manager: `operating`.
- `/dev/uio0`, `/dev/uio1`, and `/dev/udmabuf0`: present.

## Verified inference

| Field | Value |
|---|---|
| Result ID | `20180310T032854Z-B32_CFGLUT125-library_alley_cat` |
| Release | `B32_CFGLUT125` |
| Shape/build | `N3K16W32H32-CVH1` / `EF125K16N3W32R01` |
| Result | PASS |
| Verified frames | 3 |
| Output bytes per frame | 32,768 |
| Output SHA-256 | `5821c8b19a88fd34e3002dd7b0c7d60c7fcd79b8a61a326697d95b6e3ec3be94` |
| Accelerator-path median / p95 | 0.126 ms / 0.145 ms |
| Whole-call median | 2.912 ms |
| Feature-map previews | 16/16 |

The three output frames were bit-identical and matched the anchor SHA-256
recorded in `record.json`. Every expected `preview_ch0.png` through
`preview_ch15.png` was present and passed PNG signature validation. The GUI
displayed all 16 thumbnails and supported enlarged viewing and per-channel
download.

## Scope and timestamp note

This evidence qualifies unattended boot recovery and one anchored B32 GUI
inference. It complements, rather than replaces, the separate five-release
switching, anchor, extremes, soak, and fault-recovery campaign.

The ZedBoard has no valid real-time clock source in this setup, so the result
identifier contains a 2018 board timestamp. The host-side acquisition and
qualification date above is authoritative.
