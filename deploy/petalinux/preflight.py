"""Read-only integrity and exact-project preflight; never invokes build tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat

ROOT = Path(__file__).resolve().parent
PROJECT = Path("/home/walid/projects/zedboard_linux")
BACKUPS = Path("/home/walid/projects/release_checkpoints")
NAMES = ("conv-lab", "conv-lab-starter", "conv-lab-validation")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe(path):
    """Reject symlinks in every existing component, including ancestors."""
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        require(not part.is_symlink(), "symlink refused: " + str(part))
    require(path.resolve(strict=False) == path, "noncanonical path: " + str(path))
    return path


def regular(path):
    safe(path)
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            "regular single-link file required: " + str(path))
    return info


def inventory(root):
    safe(root)
    require(root.is_dir(), "directory required: " + str(root))
    result = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(base)/name
            safe(path)
            info = path.lstat()
            require(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode),
                    "special file refused: " + str(path))
            if stat.S_ISREG(info.st_mode):
                regular(path)
                result[path.relative_to(root).as_posix()] = digest(path)
    return result


def verify(stage):
    safe(stage)
    regular(stage/"SHA256SUMS.txt")
    wanted = {}
    for line in (stage/"SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        value, name = line.split("  ", 1)
        require(re.fullmatch("[0-9a-f]{64}", value), "invalid checksum")
        rel = PurePosixPath(name)
        require(not rel.is_absolute() and all(p not in ("", ".", "..") for p in name.split("/"))
                and "\\" not in name and ":" not in name, "unsafe manifest path")
        require(name not in wanted and name != "SHA256SUMS.txt", "duplicate/self manifest entry")
        wanted[name] = value
    actual = inventory(stage)
    actual.pop("SHA256SUMS.txt")
    require(actual == wanted, "stage inventory/checksum mismatch")
    return len(wanted)


def load_stage(stage):
    count = verify(stage)
    plan = json.loads((stage/"APPLICATION_PLAN.json").read_bytes())
    require(plan["status"] == "READY FOR USER APPLICATION; BUILD AND ARM VALIDATION NOT RUN",
            "stage is not finalized")
    require(plan["ubuntu_project"] == str(PROJECT), "unexpected planned project")
    require({x["path"] for x in plan["configuration"]} == {
        "project-spec/configs/rootfs_config", "project-spec/meta-user/conf/user-rootfsconfig"}
        and len(plan["configuration"]) == 2, "configuration scope differs")
    seen = set()
    for item in plan["installed_files"]:
        rel = item["destination"]
        require(any(rel.startswith("project-spec/meta-user/recipes-apps/" + name + "/") for name in NAMES),
                "destination outside approved recipe scope")
        require(all(x not in ("", ".", "..") for x in rel.split("/")) and "\\" not in rel,
                "unsafe destination path")
        require(rel not in seen and item["mode"] == 0o644, "duplicate payload or unexpected mode")
        seen.add(rel)
        require(item["staged"] == rel.removeprefix("project-spec/meta-user/"), "payload mapping differs")
        require(not rel.endswith(".bb.in"), "inactive template cannot be applied")
    for item in plan["configuration"]:
        leaf = Path(item["path"]).name
        require(item["original"] == "configuration/original/"+leaf and
                item["replacement"] == "configuration/updated/"+leaf, "unsafe config snapshot path")
        require(digest(stage/item["original"]) == item["original_sha256"], "original snapshot mismatch")
        require(digest(stage/item["replacement"]) == item["result_sha256"], "replacement snapshot mismatch")
    return plan, count


def check_project(stage, project):
    plan, count = load_stage(stage)
    require(safe(project) == PROJECT and project.is_dir(), "wrong Ubuntu project")
    require(os.getuid() != 0 and os.getuid() == os.geteuid(), "use existing Ubuntu project owner without sudo")
    require(stage != project and project not in stage.parents and stage not in project.parents,
            "transfer stage must be outside project")
    for item in plan["configuration"]:
        path = safe(project/item["path"])
        info = regular(path)
        require(info.st_uid == os.getuid(), "configuration must belong to current project owner")
        require(digest(path) == item["original_sha256"], "unexpected configuration edit: " + str(path))
        require(os.access(path.parent, os.W_OK), "configuration parent not writable")
    parent = safe(project/"project-spec/meta-user/recipes-apps")
    require(parent.is_dir() and os.access(parent, os.W_OK), "recipe parent must exist and be writable")
    for name in NAMES:
        require(not os.path.lexists(parent/name), "destination already exists: " + str(parent/name))
    for item in plan["installed_files"]:
        require(digest(stage/item["staged"]) == item["sha256"], "payload mismatch")
    return plan, count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    plan, count = check_project(ROOT, args.project)
    print(json.dumps({"status": plan["status"], "verified_stage_entries": count,
                      "project": str(PROJECT), "next": "apply.py apply creates and verifies a fresh backup",
                      "qualification": "build settings/build/installed ARM execution remain user-run"}, indent=2))


if __name__ == "__main__":
    main()
