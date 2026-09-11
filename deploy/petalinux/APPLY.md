# Guarded application and scoped rollback

Target: /home/walid/projects/zedboard_linux. Run as its existing Ubuntu owner, without sudo.
READY FOR USER APPLICATION. Helpers have static review only; no execution/build qualification.
README.md is the single ordered command handoff.

## Exact changes

Append one registration line to project-spec/meta-user/conf/user-rootfsconfig:
CONFIG_conv-lab-validation

Append one selection line to project-spec/configs/rootfs_config:
CONFIG_conv-lab-validation=y

Every pre-existing byte is preserved. Dependency selection belongs to recipe RDEPENDS.
Add only these initially absent directories:
- project-spec/meta-user/recipes-apps/conv-lab
- project-spec/meta-user/recipes-apps/conv-lab-starter
- project-spec/meta-user/recipes-apps/conv-lab-validation

APPLICATION_PLAN.json lists every copied file, destination, SHA256 and mode. Only concrete .bb
files and their files/ payloads are applied. Retained historical .bb.in templates are never copied.
No DT, XSA, hardware config, UIO, module, IRQ, accounts, permissions on devices or bitstream changes.

| Config | Original SHA256 | Immediate applied SHA256 |
| --- | --- | --- |
| rootfs_config | b08f990653d97dbef8661431908b67dc8df2771bbf6654d8c9ebe2f446196ab7 | 8a69ee2b3d8c3ba30db4a1de557e76121a45dbe0e1dc17aeeea24848aba14c53 |
| meta-user/conf/user-rootfsconfig | 7ff419f1049650e5628f14e2827592a23392a1540e8b6833b302dcbfcd0b154a | 5a582fc65701cce3660d53b2d93662a8966e3a3e56f0d753ddc594b39146ef3f |

The generated configs/rootfsconfigs/user-rootfsconfig is not edited by the helper.
Configuration regeneration is a distinct user-run PetaLinux operation after application.

## Transaction and recovery

1. Stop concurrent project editors/builds. The helper takes an advisory lock on the project
   directory; it cannot prevent unrelated tools ignoring that lock.
2. Preflight verifies the complete stage manifest/inventory, exactly scoped paths, original config
   hashes, ownership, ordinary single-link files, absence of recipe destinations and symlink-free
   containment. Stage must be outside the project. Unexpected state aborts.
3. apply creates a unique mode-0700 external backup under
   /home/walid/projects/release_checkpoints/M2P_pre_apply_<UTC>_<uuid>.
   Existing backups are never reused. The backup root must be owned by this Ubuntu user,
   not group/world writable, and on the project's filesystem for atomic config replacement.
4. Copy the full finalized stage and both originals, preserving original config owner/group/mode
   and timestamps. Compare backup bytes with both live originals and expected hashes; verify the
   copied stage manifest. Write BACKUP_SHA256SUMS.txt and a BACKUP_VERIFIED receipt.
   No project file has changed yet.
5. Recheck live originals, stage and destination absence. Exclusively create recipe directories and
   files. Verify their exact inventories. Atomically replace the two configs using verified external
   temporary copies; preserve recorded metadata and verify resulting hashes.
6. Save a unique APPLIED receipt recording configuration before/after hashes, metadata, exact added
   inventory and stage identity. Its path is printed. Save it; never infer a receipt from a wildcard.
   All progress receipts and partial work are retained.

A normal caught failure records FAILED_PARTIAL. Stop and use its exact receipt for scoped rollback.
Unexpected termination/power loss may leave a last APPLYING receipt or an unrecorded partial file;
preserve it and inspect before recovery. A partially written or unexpected file is never deleted or
silently accepted. Re-running apply intentionally refuses existing destinations.

Rollback command (user-run; set the exact printed receipt path):
~~~sh
python3 -I -B "$STAGE/apply.py" rollback --project /home/walid/projects/zedboard_linux --receipt "$RECEIPT"
~~~

Rollback verifies the backup stage and original hashes, receipt scope, current config hashes/metadata,
and every existing added file before mutation. Configs must still be either their exact originals or
this patch's exact post-images. Matching partial recipe trees can be recovered; unexpected files,
edits or symlinks abort for review. It moves only recorded patch-created recipe directories into a
new rollback_quarantine directory inside the external backup, compares quarantined hashes, restores
the two verified config originals atomically and records ROLLED_BACK. Nothing is deleted.

Later PetaLinux regeneration may reformat rootfs_config; such a changed post-image deliberately
stops automatic rollback. Preserve regenerated files and review their diff against the receipt
before a separately scoped merge/revert. This helper does not claim to undo generated build output,
subsequent edits, installed board packages or flashed media. The independent M0 recovery remains
unchanged.
