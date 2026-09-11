"""Scoped user-run application/rollback. No build tools, hardware operations or deletion."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import uuid

# -I excludes cwd/PYTHONPATH; import only the adjacent verified distribution.
STAGE = Path(__file__).resolve().parent
sys.path.insert(0, str(STAGE))
from preflight import (BACKUPS, NAMES, PROJECT, check_project, digest, inventory,
                       load_stage, regular, require, safe, verify)


def unique(prefix):
    return prefix + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex


def create_file(path, data, mode=0o600):
    safe(path)
    with path.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(path, mode)


def syncdir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def record(backup, receipt, status):
    receipt["status"] = status
    receipt["updated_utc"] = datetime.now(timezone.utc).isoformat()
    data = (json.dumps(receipt, indent=2) + "\n").encode()
    entry = backup/(unique("receipt_") + ".json")
    create_file(entry, data)
    syncdir(backup)
    print(json.dumps({"status": status, "backup": str(backup), "receipt": str(entry)}), flush=True)
    return entry


def metadata(path):
    info = regular(path)
    return {"mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid, "gid": info.st_gid,
            "atime_ns": info.st_atime_ns, "mtime_ns": info.st_mtime_ns}


def copy_owned(source, dest, info):
    create_file(dest, source.read_bytes(), info["mode"])
    os.chown(dest, info["uid"], info["gid"])
    os.utime(dest, ns=(info["atime_ns"], info["mtime_ns"]))
    require(digest(source) == digest(dest), "copy verification failed")


def backup_root():
    safe(BACKUPS)
    if not BACKUPS.exists():
        BACKUPS.mkdir(mode=0o700)
    require(BACKUPS.is_dir() and BACKUPS.stat().st_uid == os.getuid(),
            "backup root must belong to current Ubuntu owner")
    require(BACKUPS.stat().st_mode & 0o022 == 0, "backup root is group/world writable")
    require(BACKUPS.stat().st_dev == PROJECT.stat().st_dev,
            "atomic replacement requires backup and project on same filesystem")


def intended_dirs(files, root):
    dirs = {root}
    for item in files:
        path = Path(item["destination"]).parent
        while str(path) != root:
            dirs.add(path.as_posix())
            path = path.parent
        dirs.add(root)
    return dirs


def check_new_tree(project, plan, name, partial=False):
    root = "project-spec/meta-user/recipes-apps/" + name
    wanted = {x["destination"][len(root)+1:]: x["sha256"] for x in plan["installed_files"]
              if x["destination"].startswith(root + "/")}
    path = project/root
    if not path.exists():
        require(partial, "missing installed recipe")
        return
    observed = inventory(path)
    require(all(k in wanted and wanted[k] == v for k, v in observed.items()), "changed/unexpected recipe payload")
    require(partial or observed == wanted, "incomplete installed recipe")
    allowed_dirs = intended_dirs([x for x in plan["installed_files"]
                                 if x["destination"].startswith(root + "/")], root)
    for base, dirs, files in os.walk(path):
        for child in dirs:
            p = Path(base)/child
            require(p.relative_to(project).as_posix() in allowed_dirs, "unexpected recipe directory")
    for item in plan["installed_files"]:
        if item["destination"].startswith(root + "/"):
            p = project/item["destination"]
            if p.exists():
                st = regular(p)
                require(st.st_uid == os.getuid() and stat.S_IMODE(st.st_mode) == item["mode"],
                        "changed recipe ownership/mode")


def apply(project):
    plan, count = check_project(STAGE, project)
    backup_root()
    backup = BACKUPS/unique("M2P_pre_apply_")
    backup.mkdir(mode=0o700)
    receipt = {"schema": 1, "project": str(project), "backup": str(backup),
               "stage_manifest_sha256": digest(STAGE/"SHA256SUMS.txt"),
               "configuration": [], "installed_files": plan["installed_files"],
               "planned_recipe_directories": list(NAMES), "started_recipe_directories": [],
               "no_build_or_hardware_action": True}
    # Everything below is outside the project until BACKUP_VERIFIED is recorded.
    shutil.copytree(STAGE, backup/"stage")
    verify(backup/"stage")
    require(digest(backup/"stage/SHA256SUMS.txt") == receipt["stage_manifest_sha256"], "backup stage changed")
    for item in plan["configuration"]:
        current = project/item["path"]
        info = metadata(current)
        original = backup/"originals"/item["path"]
        original.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        copy_owned(current, original, info)
        require(digest(original) == item["original_sha256"], "backup original mismatch")
        receipt["configuration"].append(dict(item, metadata=info))
    immutable = inventory(backup/"originals")
    create_file(backup/"BACKUP_SHA256SUMS.txt",
                "".join(v + "  originals/" + k + "\n" for k, v in sorted(immutable.items())).encode())
    record(backup, receipt, "BACKUP_VERIFIED")
    # Recheck both originals, stage and all destinations after completing backup.
    check_project(STAGE, project)
    record(backup, receipt, "APPLYING")
    try:
        for name in NAMES:
            root = project/"project-spec/meta-user/recipes-apps"/name
            root.mkdir(mode=0o755)  # exclusive creation; never overwrite a destination
            os.chmod(root, 0o755)
            receipt["started_recipe_directories"].append(name)
            record(backup, receipt, "APPLYING")
            selected = [x for x in plan["installed_files"]
                        if x["destination"].startswith(root.relative_to(project).as_posix()+"/")]
            dirs = intended_dirs(selected, root.relative_to(project).as_posix())
            for rel in sorted(dirs, key=lambda p: (p.count("/"), p)):
                if project/rel != root:
                    safe(project/rel).mkdir(mode=0o755)
                    os.chmod(project/rel, 0o755)
            for item in selected:
                dest = safe(project/item["destination"])
                create_file(dest, (backup/"stage"/item["staged"]).read_bytes(), item["mode"])
                require(digest(dest) == item["sha256"], "installed payload mismatch")
            check_new_tree(project, plan, name)
        for item in receipt["configuration"]:
            target = safe(project/item["path"])
            require(digest(target) == item["original_sha256"] and
                    all(metadata(target)[k] == item["metadata"][k] for k in ("mode", "uid", "gid")), "config changed during apply")
            replacement = backup/unique("config_post_")
            copy_owned(backup/"stage"/item["replacement"], replacement, item["metadata"])
            os.replace(replacement, target)
            syncdir(target.parent)
            require(digest(target) == item["result_sha256"], "post configuration hash mismatch")
        for name in NAMES:
            check_new_tree(project, plan, name)
        record(backup, receipt, "APPLIED")
    except BaseException:
        record(backup, receipt, "FAILED_PARTIAL")
        print("Stop; preserve backup and use rollback with the latest receipt. Do not rerun apply.", file=sys.stderr)
        raise


def rollback(project, receipt_path):
    safe(receipt_path); regular(receipt_path)
    backup = receipt_path.parent
    require(backup.parent == BACKUPS and backup.name.startswith("M2P_pre_apply_"), "wrong receipt location")
    require(backup.stat().st_uid == os.getuid() and backup.stat().st_mode & 0o077 == 0, "unsafe backup owner/mode")
    receipt = json.loads(receipt_path.read_bytes())
    require(receipt["project"] == str(project) and receipt["backup"] == str(backup), "receipt identity mismatch")
    require(receipt["status"] in ("APPLIED", "FAILED_PARTIAL", "APPLYING"), "receipt not applicable for rollback")
    plan, _ = load_stage(backup/"stage")
    require(digest(backup/"stage/SHA256SUMS.txt") == receipt["stage_manifest_sha256"], "wrong backup stage")
    require(receipt["installed_files"] == plan["installed_files"], "receipt payload mismatch")
    require([ {k: x[k] for k in plan["configuration"][i]} for i,x in enumerate(receipt["configuration"])]
            == plan["configuration"], "receipt configuration scope mismatch")
    backup_root()
    # Validate ALL affected paths and backups before any rollback mutation.
    for item in receipt["configuration"]:
        original = backup/"originals"/item["path"]
        regular(original)
        require(digest(original) == item["original_sha256"], "corrupt original backup")
        current = safe(project/item["path"])
        info = metadata(current)
        require(digest(current) in (item["original_sha256"], item["result_sha256"]), "later config edit; manual review required")
        require(all(info[k] == item["metadata"][k] for k in ("mode", "uid", "gid")), "later config metadata edit")
    require(set(receipt["started_recipe_directories"]).issubset(NAMES), "invalid rollback scope")
    for name in receipt["started_recipe_directories"]:
        check_new_tree(project, plan, name, partial=True)
    quarantine = backup/unique("rollback_quarantine_")
    quarantine.mkdir(mode=0o700)
    record(backup, receipt, "ROLLBACK_STARTED")
    for name in receipt["started_recipe_directories"]:
        source = safe(project/"project-spec/meta-user/recipes-apps"/name)
        if source.exists():
            observed = inventory(source)
            os.rename(source, quarantine/name)
            require(inventory(quarantine/name) == observed, "quarantine verification failed")
    for item in receipt["configuration"]:
        target = safe(project/item["path"])
        require(digest(target) in (item["original_sha256"], item["result_sha256"]), "concurrent config edit")
        temp = backup/unique("config_restore_")
        copy_owned(backup/"originals"/item["path"], temp, item["metadata"])
        os.replace(temp, target)
        syncdir(target.parent)
        require(digest(target) == item["original_sha256"], "restoration mismatch")
    receipt["quarantine"] = str(quarantine)
    record(backup, receipt, "ROLLED_BACK")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("apply", "rollback"))
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    project = safe(args.project)
    require(project == PROJECT and project.is_dir(), "wrong project")
    require(os.getuid() != 0 and os.getuid() == os.geteuid(), "run as Ubuntu project owner, without sudo")
    verify(STAGE)
    os.umask(0o077)
    # Advisory directory lock leaves no project lockfile; stop other edits/builds first.
    fd = os.open(project, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == "apply":
            require(args.receipt is None, "apply does not take a receipt")
            apply(project)
        else:
            require(args.receipt is not None, "rollback requires exact receipt path")
            rollback(project, args.receipt)
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
