# Recovery

Archives and notes for material that was removed from the working tree. None of
it is needed to build, run or verify the accelerator.

| Item | What it holds |
|---|---|
| `legacy_history_20260920.tar.gz` | Superseded milestone-era checkpoints and records |
| `release_checkpoints_20260920.tar.gz` | Routed design checkpoints of the qualified releases |
| `vmshare_legacy_20260920.tar.gz` | Files from the old Linux VM share |
| `superseded_branches_20261114.bundle` | Git bundle of the four unmerged 2026-09 research branches (`feature/k16-*`), kept before they were deleted from GitHub |
| `BOARD_RECOVERY.md` | Recovering the ZedBoard from a bad SD card or network state |
| `EXTERNAL_SOURCES.md` | The removed teammate clone and how to restore it |
| `VMShare_RECOVERY_README.txt` | How the VM share archive was produced |

Verify an archive with `sha256sum -c <name>.sha256`. The large tarballs are not
tracked in git, only their checksums; the small branch bundle is tracked.

## Restoring the deleted branches

```bash
git fetch recovery/superseded_branches_20261114.bundle \
  'refs/remotes/origin/feature/*:refs/heads/archive/*'
```

This creates local `archive/k16-cfglut5-exact`, `archive/k16-drop2`,
`archive/k16-cfglut5-edgefree-100mhz` and `archive/k16-cfglut5-edgefree-125mhz`.
