"""Installed-only entry point. No device access, privilege fallback or startup service."""
import argparse
import fcntl
import os
from pathlib import Path
import pwd
import stat
import sys
import tempfile

APP = Path("/opt/conv-lab/app")
DATA = Path("/var/lib/conv-lab")
MODEL = "/opt/conv-lab/library/models/N3_K8/m0-trained-cifar-k8/converted-1"
DATASET = "/opt/conv-lab/library/datasets/m0-cifar-cat/converted-1"
AUDIT = "/opt/conv-lab/validation/evidence/trained_cifar_vector_audit.json"


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def owned(path, uid, directory=True):
    info = path.lstat()
    require(not path.is_symlink() and info.st_uid == uid, "unexpected ownership/link: "+str(path))
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
            "unexpected file type: "+str(path))
    require(info.st_mode & 0o022 == 0, "group/world writable: "+str(path))
    return info


def account():
    entry = pwd.getpwnam("petalinux")
    require(entry.pw_uid > 0 and entry.pw_gid > 0, "existing non-root petalinux account required")
    return entry


def setup_output():
    """Explicit administrator action, after boot; no recursive chmod/chown."""
    require(os.geteuid() == 0, "administrator required for output-directory setup")
    entry = account()
    owned(Path("/var"), 0); owned(Path("/var/lib"), 0); owned(DATA, 0)
    for name in ("staging", "results", "qualification"):
        p = DATA/name
        if p.exists() or p.is_symlink():
            info = owned(p, entry.pw_uid)
            require(info.st_gid == entry.pw_gid and stat.S_IMODE(info.st_mode) == 0o750,
                    "existing directory differs; manual review required: "+str(p))
        else:
            p.mkdir(mode=0o750)
            os.chown(p, entry.pw_uid, entry.pw_gid)
            os.chmod(p, 0o750)
    print("Output directories prepared for existing petalinux account; no devices changed.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("offline", "tests", "prepare-output"))
    parser.add_argument("--group", choices=("A", "B", "C"))
    args = parser.parse_args(argv)
    os.umask(0o077)
    if args.mode == "prepare-output":
        require(args.group is None, "group is only for tests")
        setup_output()
        return 0
    entry = account()
    require(os.getuid() == os.geteuid() == entry.pw_uid, "run as existing petalinux, without sudo")
    for p in (Path("/opt"), Path("/opt/conv-lab"), APP, APP/"conv_lab"):
        owned(p, 0)
    for p in (APP/"conv_lab").glob("*.py"):
        owned(p, 0, False)
    owned(DATA, 0)
    for name in ("staging", "results", "qualification"):
        info = owned(DATA/name, entry.pw_uid)
        require(info.st_gid == entry.pw_gid and stat.S_IMODE(info.st_mode) == 0o750,
                "output permissions not prepared")
    if args.mode == "tests":
        require(args.group is not None, "tests requires explicit --group")
        owned(APP/"tests", 0)
        for p in (APP/"tests").glob("*.py"):
            owned(p, 0, False)
    else:
        require(args.group is None, "offline does not accept --group")
    # -I ignores user PYTHONPATH/site. Only this fixed root-owned tree is added.
    sys.path.insert(0, str(APP))
    from conv_lab.preprocessing import _host_supported
    _host_supported()  # effective capability and Linux checks, before any decoding
    tempfile.tempdir = str(DATA/"staging")
    lock = DATA/"staging"/"installed-session.lock"
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        st = os.fstat(fd)
        require(stat.S_ISREG(st.st_mode) and st.st_uid == entry.pw_uid and
                st.st_nlink == 1 and stat.S_IMODE(st.st_mode) == 0o600, "invalid session lock")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        import shutil
        from conv_lab.release_io import MAX_OUTPUT_BYTES
        require(shutil.disk_usage(DATA).free >= 536870912 + MAX_OUTPUT_BYTES + 1048576,
                "insufficient pre-operation filesystem headroom")
        # Serialize reference, worker and output accounting across installed launchers.
        # New subdirectories and reports are retained as protected evidence.
        if args.mode == "offline":
            from datetime import datetime, timezone
            import uuid
            from conv_lab.offline import main as offline_main
            name = "offline-"+datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")+"-"+uuid.uuid4().hex[:8]
            return offline_main(["--model", MODEL, "--dataset", DATASET,
                "--image-id", "alley_cat_s_000013", "--W", "32", "--H", "32", "--N", "3", "--K", "8",
                "--bias-width", "24", "--historical-audit", AUDIT,
                "--report-output", str(DATA/"qualification"/name)])
        from tests.run_group import main as tests_main
        sys.argv = ["conv-lab-tests", args.group, "--report-dir", str(DATA/"qualification")]
        return tests_main()
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, KeyError) as exc:
        print("conv-lab: "+str(exc), file=sys.stderr)
        raise SystemExit(1)
