Attention is all you need - ZedBoard recovery payloads

Keep these two payloads together with SHA256SUMS.txt:

1. zedboard_B32_CFGLUT125_G3_3eb5074.wic.gz
   Final compatible PetaLinux SD-card image. Decompress before flashing.
   The decompressed WIC SHA-256 must be:
   c99781f6e30a651c1fe878e9806f9e6b78a605eb46f0d6315516c0af6265e5f4

2. g5_runtime_20260915T024500Z.tar.gz
   Five-profile board runtime overlay.

After recovery, verify the live hardware identity and run the profile anchors
before demonstrations. See recovery/BOARD_RECOVERY.md in the project for the
full procedure.
