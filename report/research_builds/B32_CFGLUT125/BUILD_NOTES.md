# B32_CFGLUT125 first isolated research build

Built with Vivado 2025.2 from tracked commit
`f6bfab260274badb7f01af3e7fe10fbfd55735fc` and the source hashes in
`build_manifest.json`.

Signoff result: WNS `+0.157 ns`, WHS `+0.019 ns`, all user timing constraints
met, zero routing errors, and zero DRC errors. Board validation is `NOT_RUN`.

The console emitted two known classes of non-gating critical warnings:

- `PSU-1` through `PSU-4` report the negative DDR DQS-to-clock delay values
  supplied by the installed Digilent ZedBoard board definition. These are the
  board preset values, not changes introduced by the accelerator RTL.
- `Common 17-55` was emitted for four `Zedboard-Master.xdc` I/O-bank commands
  whose `get_ports` queries match no PL ports in this PS-only external-I/O
  top. They applied no constraint objects. The routed DRC report has zero
  errors.

These warnings are preserved here rather than hidden. The release remains a
built candidate until the Gate 3 measured-clock, identity, exact-output,
soak, recovery, and switching checks pass on the board.

Artifact identities:

- bit: `133713c5eca1f8a41a7baa40719e1c101364f3a835111028db925a7d7a309858`
- FPGA-manager bit.bin: `4e827310eb7f1e8c9278d0c9b36905eb4b7c766d9878a3a551e1909843d5b73b`
- XSA: `e90b84413bf35d8da2aa5b5a86b5ea41e2519360fd593b60c9f3a918544f648d`
