"""Linux-only bounded supervisor. No in-process image-decoding fallback."""
import json
import os
import selectors
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

from .errors import AdmissionError, EnforcementUnavailable
from .strict import integer, obj, parse_json, require, sha256
from .types import Decoded

MAX_SOURCE_BYTES = 8388608
MAX_WIDTH = MAX_HEIGHT = 4096
MAX_PIXELS = 2097152
ADDRESS_SPACE_BYTES = 134217728
TIMEOUT_SECONDS = 30
MAX_RECORD_BYTES = 16384
MAX_CANONICAL_BYTES = 4194303//2  # Derived RX limit at the smallest K=1, not a source dimension policy.
RESOURCE_STRATEGY = "linux-process-rlimit-as-supervised-v1"


def source_bounds(byte_count, width, height):
    integer(byte_count,1,MAX_SOURCE_BYTES)
    integer(width,1,MAX_WIDTH); integer(height,1,MAX_HEIGHT)
    require(width*height <= MAX_PIXELS, "source pixel limit")


def _host_supported():
    if sys.platform != "linux" or not hasattr(os,"geteuid"):
        raise EnforcementUnavailable("Linux worker enforcement required; no desktop fallback")
    if os.geteuid() == 0 or os.getuid() != os.geteuid():
        raise EnforcementUnavailable("run as an explicit ordinary unprivileged user, not root/setuid")
    try:
        fields = dict(line.split(":",1) for line in Path("/proc/self/status").read_text().splitlines() if ":" in line)
        if int(fields["CapEff"].strip(),16) != 0:
            raise EnforcementUnavailable("decoder supervisor must have no effective capabilities")
    except (OSError,KeyError,ValueError) as exc:
        raise EnforcementUnavailable("cannot establish Linux privilege state") from exc


@contextmanager
def _worker_slot():
    """Per-UID flock also serializes independent supervisor processes."""
    import fcntl
    directory = Path(tempfile.gettempdir()) / f"conv-lab-decoder-{os.getuid()}"
    directory.mkdir(mode=0o700,exist_ok=True)
    st = directory.lstat()
    require(stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() and
            stat.S_IMODE(st.st_mode) == 0o700, "insecure worker lock directory")
    fd = os.open(directory/"worker.lock", os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    try:
        st = os.fstat(fd)
        require(stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid() and st.st_nlink == 1 and
                stat.S_IMODE(st.st_mode) == 0o600, "insecure worker lock")
        try:
            fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise AdmissionError("another decoder worker is active") from exc
        yield
    finally:
        os.close(fd)


def _exchange(command, packet, maximum_output, deadline_seconds):
    """Private transport, also exercised by deliberate user-run fault workers."""
    deadline = time.monotonic()+deadline_seconds
    child = subprocess.Popen(command, stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE,close_fds=True,pass_fds=(),
                             start_new_session=True,env={"LANG":"C.UTF-8"})
    selector = selectors.DefaultSelector()
    output, errors, sent = bytearray(), bytearray(), 0
    try:
        for stream,event in ((child.stdin,selectors.EVENT_WRITE),
                             (child.stdout,selectors.EVENT_READ),(child.stderr,selectors.EVENT_READ)):
            os.set_blocking(stream.fileno(),False)
            selector.register(stream,event)
        while selector.get_map():
            remaining = deadline-time.monotonic()
            require(remaining > 0, "preprocessing deadline exceeded")
            for key,_ in selector.select(min(remaining,0.1)):
                stream = key.fileobj
                if stream is child.stdin:
                    try:
                        sent += os.write(stream.fileno(),memoryview(packet)[sent:sent+65536])
                    except BlockingIOError:
                        continue
                    except BrokenPipeError:
                        selector.unregister(stream); stream.close(); continue
                    if sent == len(packet):
                        selector.unregister(stream); stream.close()
                else:
                    try:
                        chunk = os.read(stream.fileno(),65536)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        selector.unregister(stream); stream.close(); continue
                    target,limit = (output,maximum_output) if stream is child.stdout else (errors,4096)
                    require(len(target)+len(chunk) <= limit,"worker IPC/output limit")
                    target.extend(chunk)
        remaining = deadline-time.monotonic()
        require(remaining > 0,"late worker result")
        try:
            child.wait(timeout=remaining)
        except subprocess.TimeoutExpired as exc:
            raise AdmissionError("preprocessing deadline exceeded") from exc
        require(time.monotonic() <= deadline and child.returncode == 0 and sent == len(packet),
                "failed/late worker: "+errors.decode("utf-8",errors="replace"))
        return bytes(output)
    finally:
        selector.close()
        if child.poll() is None:
            os.killpg(child.pid,signal.SIGKILL)
        child.wait()  # Always reap; only this worker/session can be terminated.
        for stream in (child.stdin,child.stdout,child.stderr):
            if not stream.closed:
                stream.close()


def validate_decoded(result, source, w, h, policy):
    require(type(result) is Decoded and type(result.canonical) is bytes and
            len(result.canonical) == w*h, "canonical result size/type")
    record = obj(parse_json(result.record_json,MAX_RECORD_BYTES),
                 "source_sha256 source_format source_mode source_width source_height exif_orientation oriented_width oriented_height target_width target_height geometry_policy resize_filter aspect_ratio_changed canonical_sha256 pillow_version decoder_versions preprocessing_version decode_policy")
    require(record["source_sha256"] == sha256(source) and
            record["canonical_sha256"] == sha256(result.canonical),"decoder identity mismatch")
    require(record["target_width"] == w and type(record["target_width"]) is int and
            record["target_height"] == h and type(record["target_height"]) is int and
            record["geometry_policy"] == policy and
            record["resize_filter"] == ("NONE" if policy == "exact" else "LANCZOS"), "decoder geometry")
    source_bounds(len(source),record["source_width"],record["source_height"])
    source_bounds(len(source),record["oriented_width"],record["oriented_height"])
    require(record["source_format"] in ("PNG","JPEG") and record["source_mode"] in ("L","RGB"),"decoder format")
    orientation = record["exif_orientation"]
    if orientation is not None:
        integer(orientation,1,8)
    expected_shape = (record["source_height"],record["source_width"]) if orientation in (5,6,7,8) else (record["source_width"],record["source_height"])
    require((record["oriented_width"],record["oriented_height"]) == expected_shape,"orientation record")
    if policy == "exact":
        require(expected_shape == (w,h),"exact geometry mismatch")
    aspect = record["oriented_width"]*h != record["oriented_height"]*w
    require(type(record["aspect_ratio_changed"]) is bool and record["aspect_ratio_changed"] == aspect,"aspect record")
    require(type(record["pillow_version"]) is str and bool(record["pillow_version"]),"Pillow version")
    require(type(record["decoder_versions"]) is list and bool(record["decoder_versions"]),"decoder versions")
    for version in record["decoder_versions"]:
        obj(version,"name version")
        require(all(type(version[x]) is str and bool(version[x]) for x in ("name","version")),"decoder version")
    require(record["preprocessing_version"] == "1", "preprocessing version")
    limits = obj(record["decode_policy"],"max_source_bytes max_width max_height max_pixels resource_strategy")
    for key,value in (("max_source_bytes",MAX_SOURCE_BYTES),("max_width",MAX_WIDTH),
                      ("max_height",MAX_HEIGHT),("max_pixels",MAX_PIXELS)):
        require(type(limits[key]) is int and limits[key] == value,"decoder policy mismatch")
    require(limits["resource_strategy"] == RESOURCE_STRATEGY,"decoder enforcement strategy")
    return result


class LinuxDecoder:
    def decode(self, source, w, h, policy):
        _host_supported()
        require(type(source) is bytes and 0 < len(source) <= MAX_SOURCE_BYTES,"source byte limit")
        integer(w,1,0xffffffff); integer(h,1,0xffffffff)
        require(w*h <= MAX_CANONICAL_BYTES,"target exceeds signed16 DMA frame bound")
        require(policy in ("exact","resize_exact"),"policy")
        request = json.dumps({"W":w,"H":h,"policy":policy,"source_length":len(source)},separators=(",",":")).encode()
        packet = struct.pack(">I",len(request))+request+source
        command = [sys.executable,"-I","-B",str(Path(__file__).with_name("_decoder_worker.py"))]
        with _worker_slot():
            output = _exchange(command,packet,4+MAX_RECORD_BYTES+w*h,TIMEOUT_SECONDS)
        require(len(output) >= 4,"truncated worker output")
        length = struct.unpack(">I",output[:4])[0]
        require(0 < length <= MAX_RECORD_BYTES and len(output) == 4+length+w*h,"worker framing")
        result = Decoded(output[4+length:],output[4:4+length])
        return validate_decoded(result,source,w,h,policy)
