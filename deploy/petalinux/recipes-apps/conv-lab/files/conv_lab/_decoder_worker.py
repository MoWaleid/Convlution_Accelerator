"""Private executable child. Limit/privilege checks precede Pillow import."""
import os
import sys


def _isolate():
    if sys.platform != "linux" or os.getuid() == 0 or os.getuid() != os.geteuid():
        raise RuntimeError("unprivileged Linux worker required")
    import resource
    import ctypes
    ceiling = 134217728
    _,hard = resource.getrlimit(resource.RLIMIT_AS)
    effective = ceiling if hard == resource.RLIM_INFINITY else min(hard,ceiling)
    resource.setrlimit(resource.RLIMIT_AS,(effective,effective))
    if resource.getrlimit(resource.RLIMIT_AS) != (effective,effective):
        raise RuntimeError("address-space enforcement unavailable")
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    libc = ctypes.CDLL(None,use_errno=True)
    if libc.prctl(38,1,0,0,0) != 0:  # PR_SET_NO_NEW_PRIVS
        raise RuntimeError("no_new_privs unavailable")
    with open("/proc/self/status") as status:
        fields = dict(line.split(":",1) for line in status if ":" in line)
    if int(fields["CapEff"].strip(),16) != 0:
        raise RuntimeError("effective capabilities forbidden")
    for name in os.listdir("/proc/self/fd"):
        if int(name) > 2:
            try:
                os.fstat(int(name))
            except OSError:
                continue  # closed /proc directory iterator
            raise RuntimeError("unexpected inherited descriptor")
    return effective


def _header(data):
    """Inspect encoded precision/mode, not a silently downconverted Pillow mode."""
    import struct
    import zlib
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        pos,first,ended,shape = 8,True,False,None
        while pos < len(data):
            if pos+12 > len(data):
                raise ValueError("truncated PNG chunk")
            count = int.from_bytes(data[pos:pos+4],"big")
            tag = data[pos+4:pos+8]
            end = pos+12+count
            if end > len(data):
                raise ValueError("PNG chunk bounds")
            chunk = data[pos+8:pos+8+count]
            if zlib.crc32(tag+chunk) & 0xffffffff != int.from_bytes(data[pos+8+count:end],"big"):
                raise ValueError("PNG CRC")
            if first:
                if tag != b"IHDR" or count != 13:
                    raise ValueError("PNG IHDR")
                w,h,depth,color,compression,filtering,interlace = struct.unpack(">IIBBBBB",chunk)
                if depth != 8 or color not in (0,2) or compression != 0 or filtering != 0 or interlace not in (0,1):
                    raise ValueError("unsupported PNG encoding")
                shape = w,h,"L" if color == 0 else "RGB"
                first = False
            elif tag == b"IHDR":
                raise ValueError("duplicate IHDR")
            if tag in (b"tRNS",b"acTL",b"fcTL",b"fdAT"):
                raise ValueError("transparency/animation forbidden")
            pos = end
            if tag == b"IEND":
                if count != 0 or pos != len(data):
                    raise ValueError("trailing PNG data")
                ended = True
                break
        if not ended or shape is None:
            raise ValueError("incomplete PNG")
        return "PNG",shape
    if data.startswith(b"\xff\xd8"):
        pos,shape,ended = 2,None,False
        while pos < len(data):
            if data[pos] != 255:  # entropy-coded data
                pos += 1
                continue
            while pos < len(data) and data[pos] == 255:
                pos += 1
            if pos == len(data):
                break
            marker = data[pos]; pos += 1
            if marker == 0 or 0xd0 <= marker <= 0xd7:
                continue
            if marker == 0xd9:
                if pos != len(data):
                    raise ValueError("trailing JPEG/second image")
                ended = True
                break
            if marker == 0xd8 or pos+2 > len(data):
                raise ValueError("malformed JPEG")
            count = int.from_bytes(data[pos:pos+2],"big")
            if count < 2 or pos+count > len(data):
                raise ValueError("JPEG segment bounds")
            body = data[pos+2:pos+count]
            if marker in (0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf):
                if shape is not None or len(body) < 6 or body[0] != 8 or body[5] not in (1,3):
                    raise ValueError("unsupported JPEG precision/components")
                shape = int.from_bytes(body[3:5],"big"),int.from_bytes(body[1:3],"big"),"L" if body[5] == 1 else "RGB"
            pos += count
        if not ended or shape is None:
            raise ValueError("incomplete JPEG")
        return "JPEG",shape
    raise ValueError("only static PNG/JPEG admitted")


def _read_exact(stream, count):
    data = stream.read(count)
    if len(data) != count:
        raise ValueError("short request")
    return data


def main():
    effective = _isolate()
    import io
    import json
    import struct
    import warnings
    from pathlib import Path
    # -I prevents user-controlled current/PYTHONPATH imports. Only trusted code root is added.
    sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
    from conv_lab.preprocessing import (MAX_RECORD_BYTES,RESOURCE_STRATEGY,source_bounds)
    from conv_lab.strict import integer,obj,parse_json,require,sha256
    size = struct.unpack(">I",_read_exact(sys.stdin.buffer,4))[0]
    require(0 < size <= 4096,"request metadata bound")
    req = obj(parse_json(_read_exact(sys.stdin.buffer,size)),"W H policy source_length")
    length = integer(req["source_length"],1,8388608)
    w,h,policy = integer(req["W"],1,0xffffffff),integer(req["H"],1,0xffffffff),req["policy"]
    require(w*h <= 4194303//2,"canonical output bound from signed16 DMA length")
    require(policy in ("exact","resize_exact"),"policy")
    source = _read_exact(sys.stdin.buffer,length)
    require(not sys.stdin.buffer.read(1),"extra request data")
    fmt,(sw,sh,mode) = _header(source)
    source_bounds(length,sw,sh)
    from PIL import Image,ImageOps,features,__version__ as pillow_version
    warnings.simplefilter("error")  # Reject malformed metadata warnings as well as bomb warnings.
    with Image.open(io.BytesIO(source),formats=("PNG","JPEG")) as image:
        require(image.format == fmt and image.mode == mode and image.size == (sw,sh),"decoded source mismatch")
        require(getattr(image,"n_frames",1) == 1 and "transparency" not in image.info,"multiframe/transparency")
        exif = image.getexif()
        orientation = exif.get(274)
        if 274 in exif:
            integer(orientation,1,8)
        image.load()  # exactly one full source decode
        oriented = ImageOps.exif_transpose(image)
        ow,oh = oriented.size
        source_bounds(length,ow,oh)
        gray = oriented if mode == "L" else oriented.convert("L")
        if policy == "exact":
            require(gray.size == (w,h),"exact geometry mismatch")
        else:
            gray = gray.resize((w,h),Image.Resampling.LANCZOS)
        pixels = gray.tobytes()
    decoder_name = "zlib" if fmt == "PNG" else "jpg"
    version = features.version(decoder_name)
    require(type(version) is str and bool(version),"codec version unavailable")
    record = dict(source_sha256=sha256(source),source_format=fmt,source_mode=mode,
                  source_width=sw,source_height=sh,exif_orientation=orientation,
                  oriented_width=ow,oriented_height=oh,target_width=w,target_height=h,
                  geometry_policy=policy,resize_filter="NONE" if policy == "exact" else "LANCZOS",
                  aspect_ratio_changed=ow*h != oh*w,canonical_sha256=sha256(pixels),
                  pillow_version=pillow_version,decoder_versions=[dict(name=decoder_name,version=version)],
                  preprocessing_version="1",decode_policy=dict(max_source_bytes=8388608,max_width=4096,
                  max_height=4096,max_pixels=2097152,resource_strategy=RESOURCE_STRATEGY),
                  extensions=dict(worker_uid=os.getuid(),address_space_limit=effective,
                                  no_new_privs=True,python_version=sys.version,hardware_descriptors_inherited=False))
    metadata = json.dumps(record,separators=(",",":"),allow_nan=False).encode()
    require(len(metadata) <= MAX_RECORD_BYTES and len(pixels) == w*h,"output bounds")
    sys.stdout.buffer.write(struct.pack(">I",len(metadata))+metadata+pixels)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        sys.stderr.write((type(exc).__name__+": "+str(exc))[:2048]+"\n")
        sys.exit(1)
