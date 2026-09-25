# Hardware and parameter profiles

`m7_profiles.json` is the qualified five-release runtime catalog. Despite its
historical filename, it contains only the final 125 MHz A32, B32, C32, D32,
and D640 releases. `anchors_m7.json` records their bit-exact reference anchors.

`development_profiles.json` is deliberately separate. The profile generator
adds new, unqualified hardware geometries there so a development bitstream
cannot be mistaken for an admitted runtime release.

Use:

```powershell
python -B scripts/research_release/create_profile.py E128_CFGLUT125 `
  --n 3 --k 8 --width 128 --height 128
```

The current exact compressor supports N=3 and N=5. The generator validates K,
geometry, build identity, and the 22-bit DMA transfer limit before writing a
spec. A new profile needs its own parameter bundle, runtime manifest, exact
reference vectors, implementation reports, and board qualification before it
can move into `m7_profiles.json`.
