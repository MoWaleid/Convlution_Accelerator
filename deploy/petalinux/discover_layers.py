"""Read-only Ubuntu filesystem discovery. Never invokes BitBake or sources shell files."""
import argparse
import hashlib
import json
import os
from pathlib import Path

NAMES = {"bblayers.conf", "local.conf", "petalinuxbsp.conf", "layer.conf",
         "python3-manifest.json", "user-rootfsconfig", "metadata"}
PRUNE = {".git", ".venv", "downloads", "sstate-cache", "tmp", "tmp-glibc", "cache", "sysroots"}
LIMIT = 150000


def wanted(path):
    name = path.name
    return (name in NAMES or
            ((name.startswith("python3") or
              name.startswith("python-pillow") or name.startswith("python3-pillow")) and
             path.suffix in (".bb", ".inc", ".bbappend")) or
            name in ("base.bbclass", "unpack.bbclass", "allarch.bbclass"))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project", type=Path, required=True)
    p.add_argument("--tool-root", type=Path, required=True)
    p.add_argument("--layer-root", type=Path, action="append", default=[])
    args = p.parse_args()
    roots = [args.project.resolve(strict=True), args.tool_root.resolve(strict=True)]
    roots += [r.resolve(strict=True) for r in args.layer_root]
    count, total, records, seen, links = 0, 0, [], set(), []
    for root in roots:
        if not root.is_dir():
            raise RuntimeError("not a directory: "+str(root))
        for directory, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = sorted(d for d in dirs if d not in PRUNE)
            for name in list(dirs):
                path = Path(directory)/name
                if path.is_symlink():
                    links.append({"path": str(path), "target": str(path.resolve())})
                    dirs.remove(name)
            for name in sorted(files):
                count += 1
                if count > LIMIT:
                    raise RuntimeError("bounded discovery exceeded; narrow supplied roots")
                path = Path(directory)/name
                if not wanted(path) or str(path) in seen:
                    continue
                seen.add(str(path))
                with path.open("rb") as stream:
                    data = stream.read(2097153)
                total += len(data)
                if len(data) > 2097152 or total > 33554432:
                    raise RuntimeError("metadata byte budget exceeded; narrow layer roots")
                records.append({"path": str(path), "resolved": str(path.resolve()),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "text": data.decode("utf-8", errors="replace")})
    project = args.project.resolve()
    proposals = [project/"project-spec/configs/rootfs_config",
                 project/"project-spec/meta-user/conf/user-rootfsconfig"]
    originals = []
    for path in proposals:
        originals.append({"path": str(path), "exists": path.exists(), "is_symlink": path.is_symlink(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None,
            "text": path.read_text() if path.is_file() else None})
    conflicts = {name: (project/"project-spec/meta-user/recipes-apps"/name).exists()
                 for name in ("conv-lab", "conv-lab-starter", "conv-lab-validation")}
    print(json.dumps({"scope": "Read-only file observations; not BitBake evaluation or build proof",
        "project": str(project), "roots": list(map(str, roots)), "files_visited": count,
        "records": records, "unfollowed_directory_links": links,
        "proposed_originals": originals, "recipe_destination_conflicts": conflicts,
        "needs_review": ["Resolve active BBLAYERS includes/variables and priorities.",
                        "Confirm selected python3/Pillow recipes, appends, package splits and codec flags.",
                        "Resolve Python packagegroup existence and S/UNPACKDIR convention.",
                        "External symlinked layers may need another explicit --layer-root."]}, indent=2))


if __name__ == "__main__":
    main()
