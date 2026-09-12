# M7_STATE.md — Current M7 execution state for AI handoff

> **2026-09-12 evening correction:** the `m7_switch.py` described here is the
> pre-review build; the manager has since been repaired and mock-tested —
> `AI_HANDOFF.md` §16 is the live state (current md5 `e853933b…`). §3/§5 below
> wrongly blame a tar extraction path for the board's `FileNotFoundError`; the
> real cause is that `hardware_{B32,C32,D32,D640}.json` and the `D640/` parameter
> dir were never in the pushed bundle. Ready-made push payloads + exact next
> commands: `AI_HANDOFF.md` §16.4–§16.5.

**Purpose:** Immediate working state for M7 profile switching. Read together with
`M7_CONTINUATION.md` (planning/risks) and `AI_HANDOFF.md` (general context).
Written 2026-09-12 by the primary AI after completing all 5 profile builds and
preparing the board-side switch manager.

---

## 1. What M7 is trying to achieve

Switch between 5 compiled FPGA bitstream profiles (A32/B32/C32/D32/D640) on the
live ZedBoard using the Zynq FPGA Manager, validating identity after each reload,
installing that profile's parameters, and proving bit-exact inference. The gate
requires 20× A32→B32→A32 cycles plus every other ordered pair at least once.

## 2. What is DONE and verified

### All 5 bitstreams built, timing-met, archived

| Profile | BUILD_ID (ASCII) | N | K | W×H | WNS | Bitstream | Firmware .bin |
|---|---|---:|---:|---|---:|---|---|
| A32 | M4N3K8W32-260911 | 3 | 8 | 32×32 | +0.009 | `bitstreams/k8_gp0_noila_len22_2026-09-11.bit` | `m4_accelerator_dma.bin` (already on board) |
| B32 | BN3K16W32-260912 | 3 | 16 | 32×32 | +0.009 | `bitstreams/bn3k16_len22_2026-09-12.bit` | `bn3k16_len22_2026-09-12.bit.bin` |
| C32 | CN5K08W32-260912 | 5 | 8 | 32×32 | **+0.290** | `bitstreams/cn5k08_len22_2026-09-12.bit` | `cn5k08_len22_2026-09-12.bit.bin` |
| D32 | DN3K04W32-260912 | 3 | 4 | 32×32 | +0.003 | `bitstreams/dn3k04_len22_2026-09-12.bit` | `dn3k04_len22_2026-09-12.bit.bin` |
| D640 | D640N3K04-260912 | 3 | 4 | 640×480 | +0.001 | `bitstreams/dn3k04_w640480_2026-09-12.bit` | `dn3k04_w640480_2026-09-12.bit.bin` |

All `.bit.bin` firmware images generated with `bootgen -arch zynq -process_bitstream bin`.
A32's firmware is already on the board at `/lib/firmware/m4_accelerator_dma.bin` from M6.
The other 4 were copied to the SD card's FAT partition (partition 1) by the user
via Windows SD reader, then staged on the board to `/lib/firmware/` as:
`m7_B32.bin`, `m7_C32.bin`, `m7_D32.bin`, `m7_D640.bin`.

### Per-profile golden anchors computed

`profiles/anchors_m7.json` contains output SHA256 for each profile running
alley_cat_s_000013 (the canonical test image):
- A32: `cb3975593073652b…` (matches all prior board runs — self-check ✓)
- B32: `5821c8b19a88fd34…` (32,768 bytes — 16 channels)
- C32: `b6ab2d53dd9517f3…` (16,384 bytes — N=5 kernel)
- D32: `6cb736f6a80132d8…` (8,192 bytes — 4 channels)
- D640: `e323defbf8ad2616…` (2,457,600 bytes — 640×480, LANCZOS-resized input)

### Per-profile hardware manifests written

`software/hardware_A32.json`, `hardware_B32.json`, `hardware_C32.json`,
`hardware_D32.json`, `hardware_D640.json` — each contains BUILD_ID, geometry,
byte counts, device map, layout offsets, and artifact SHA256 hashes.

### Per-profile training/parameters complete

- B32: trained model `golden_model/data/trained_k16.pth` (70.08% test accuracy),
  weights exported to `golden_model/data/weights_k16/`
- C32: trained model `golden_model/data/trained_n5.pth` (67.72% test accuracy),
  weights exported to `golden_model/data/weights_n5/`
- D32: hand-authored filters (identity/SobelX/SobelY/blur, ReLU off) in
  `golden_model/data/weights_d32/` — no training required per M1_BUILD_MATRIX
- A32: existing `golden_model/data/weights/` (unchanged)

### RTL identity chain unified

All 5 RTL files (`config_pkg.vhd`, `conv_top.vhd`, `conv_axis_wrapper.vhd`,
`axi_lite_ctrl.vhd`) now share a single `CFG_BUILD_ID` constant defined in
`config_pkg.vhd`. Changing profiles means editing only `config_pkg.vhd`
(CFG_PROFILE, CFG_BUILD_ID, CFG_K, CFG_N, CFG_UNPADDED_WIDTH/HEIGHT).

### Test suites passed

`verification/m7_profiles/run.ps1 -Suite All` → all PASS:
- M7_SOFTWARE_PASS (DMA layout, identity chain, rejection logic)
- M7_PROFILE_PASS × 5 (A32/B32/C32/D32/D640 through real BD adapter)
- M7_ID_LEAK_REJECT_PASS (B32 with injected A32 ID → rejected)
- M7_RTL_SUITE_PASS

### Board-side firmware images staged

All 5 `.bin` files are at `/lib/firmware/` on the board:
- `m7_A32.bin` (copied from `m4_accelerator_dma.bin`, sha `b59378e4…`)
- `m7_B32.bin` (sha `f5a5d07f…`)
- `m7_C32.bin` (sha `c8b3e0c6…`)
- `m7_D32.bin` (sha `fc282238…`)
- `m7_D640.bin` (sha `17896ba8…`)

### `m7_switch.py` written and staged

`software/m7_switch.py` (board copy at `/home/petalinux/m7_switch.py`,
md5 `9337746ce1e5d597156458fd8666b09e`) — syntax-checked, compiles clean.
It implements the full profile-switch lifecycle:
- VALIDATING: firmware hash + live identity vs `hardware_<X>.json`
- QUIESCING: halt DMA, confirm quiescent
- DETACHED: close all handles before programming
- PROGRAMMING: write flags/firmware to `/sys/class/fpga_manager/fpga0/`, poll to `operating`
- REATTACHING: fresh handles, identity re-validated, stale-state proof (STATUS `0x101`)
- SELF_TEST: install parameters + bit-exact activation frame
- READY

If the live BUILD_ID already matches the requested profile, it skips
reprogramming (parameter re-admission only) — per the lifecycle contract.
If it differs, it does the full PL reload.

Modes: `--profile X [frames]` (switch + N activation frames) and `--matrix`
(the full switch matrix).

---

## 3. What is IMMEDIATELY BLOCKED and needs fixing

The profiles bundle (`m7_profiles.tgz`) was pushed and extracted, but the
tar was built with paths relative to `.` so files landed at `/home/petalinux/`
instead of `/home/petalinux/profiles/`. The script expects them at
`/home/petalinux/profiles/`.

**Fix (board command):**
```bash
mkdir -p /home/petalinux/profiles
for p in A32 B32 C32 D32 D640; do mv /home/petalinux/$p /home/petalinux/profiles/$p 2>/dev/null; done
mv /home/petalinux/m7_profiles.json /home/petalinux/profiles/ 2>/dev/null
mv /home/petalinux/anchors_m7.json /home/petalinux/profiles/ 2>/dev/null
for p in A32 B32 C32 D32 D640; do mv /home/petalinux/hardware_$p.json /home/petalinux/profiles/ 2>/dev/null; done
ls /home/petalinux/profiles/
```

Wait — actually check what's at `/home/petalinux/` first:
```bash
ls /home/petalinux/*.json /home/petalinux/A32 /home/petalinux/B32 2>/dev/null
```
Then move accordingly.

**Alternative fix (re-push with correct path):** just re-create the bundle
with a `profiles/` prefix in the tar paths, re-push, and re-extract with
`extractall('/home/petalinux/')`.

## 4. What is READY to run after the fix

### First single-profile switch test
```bash
sudo python3 /home/petalinux/m7_switch.py --profile B32 3
```
Expected: full-PL reload (BUILD_ID changes from A32→B32), 3 activation frames
bit-exact, output sha `5821c8b1…`. Then switch back:
```bash
sudo python3 /home/petalinux/m7_switch.py --profile A32 3
```

### Full switch matrix
```bash
sudo python3 /home/petalinux/m7_switch.py --matrix
```
58 switches total: 20× A32→B32→A32 cycles (40 switches), then the remaining
18 ordered pairs. Each switch: identity check → (reload if needed) →
parameter install → bit-exact activation frame. ~2-4 min total.

### Per-profile soak (if time permits)
```bash
sudo python3 /home/petalinux/m7_switch.py --soak B32 20
```

## 5. Board file inventory (current, verified)

| Path | What |
|---|---|
| `/home/petalinux/m4_filebackend.py` | M4 backend (used by M5/M6, now superseded) |
| `/home/petalinux/m5_qualify.py` | M5 qualification (passed) |
| `/home/petalinux/m6_reload.py` | M6 reload (passed, 21 reloads) |
| `/home/petalinux/m7_switch.py` | M7 profile manager (ready, untested on board) |
| `/home/petalinux/hardware.json` | A32 hardware manifest (same as `hardware_A32.json`) |
| `/home/petalinux/m7sw.b64` | b64 payload for m7_switch.py (decoded) |
| `/home/petalinux/m7prof.b64` | b64 payload for profiles bundle (decoded) |
| `/lib/firmware/m7_A32.bin` | A32 firmware (sha `b59378e4…`) |
| `/lib/firmware/m7_B32.bin` | B32 firmware (sha `f5a5d07f…`) |
| `/lib/firmware/m7_C32.bin` | C32 firmware (sha `c8b3e0c6…`) |
| `/lib/firmware/m7_D32.bin` | D32 firmware (sha `fc282238…`) |
| `/lib/firmware/m7_D640.bin` | D640 firmware (sha `17896ba8…`) |
| `/opt/conv-lab/library/` | A32 model + dataset (used for alley_cat input) |

**NOT YET ON BOARD:** the profiles directory tree (`A32/`, `B32/`, `C32/`,
`D32/` parameter subdirs + `m7_profiles.json` + `anchors_m7.json` +
`hardware_*.json` per-profile manifests). The tar was pushed but extracted
to the wrong path. Fix per §3.

## 6. Board quirks (all previously encountered)

- Board clock resets to 2018 every boot — `sudo date -s "<UTC>"` after each boot
- `/tmp` wiped on reboot — use `/home/petalinux/`
- No `base64` applet — use `python3 -c "import base64,..."`
- UIO/udmabuf devices are root-only — run inference scripts with `sudo`
- S2MM DMA must be armed BEFORE MM2S triggers
- Post-frame STATUS is `0x19D` (sticky events) until CVH1 RESET → `0x181`
- Illegal MMIO access from userspace → SIGBUS (fail-stop), never probe error paths
- Serial paste corruption is the #1 transfer problem — always verify per-chunk md5

## 7. M7 completion criteria (remaining)

> **2026-09-13: ALL BOARD ITEMS COMPLETE — M7 gate PASS.** Live evidence in
> `AI_HANDOFF.md` §10/§16 and `report/evidence/m7_*.txt`. Item 13's commit is
> the only user action outstanding.

1. ✅ All 5 bitstreams built, timing-met, archived
2. ✅ Per-profile golden anchors computed
3. ✅ Per-profile hardware manifests written
4. ✅ Per-profile training/parameters ready
5. ✅ RTL identity chain unified
6. ✅ Test suites passed (software + RTL + identity-leak rejection)
7. ✅ Firmware images staged on board
8. ✅ `m7_switch.py` written, staged on board (repaired build `e853933b…`)
9. ✅ Profiles directory tree on board (delta landed 2026-09-13; 11 members md5-verified)
10. ✅ First single-profile switch test (`--profile B32 3`) — PASS, anchor-exact
11. ✅ Switch back to A32 — PASS; C32/D32/D640 singles also PASS
12. ✅ Full switch matrix (`--matrix`) — 58 switches, 58 reloads, 20/20 ordered pairs, 404.4 s
13. ⬜ Record transcripts (done: `report/evidence/m7_*.txt`), update `AI_HANDOFF.md` (done), **commit — pending user**
14. ✅ Per-profile 100-frame soaks ×5 — PASS (A32/B32/C32/D32 median ~0.124 ms; D640 median 3.731 ms timed)
15. ✅ Cold-boot fallback proof — PASS (persistence md5 + reload + 3 anchor-exact frames)
