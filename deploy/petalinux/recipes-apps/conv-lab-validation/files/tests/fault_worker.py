"""Deliberate, bounded supervisor faults; invoked only by user-run Linux tests."""
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parent.parent))

mode = sys.argv[1]
if mode == "limit":
    from conv_lab._decoder_worker import _isolate
    limit = _isolate()
    sys.stdin.buffer.read()
    try:
        huge = bytearray(limit*2)
    except (MemoryError,OverflowError):
        print(json.dumps(dict(enforced=True,limit=limit,uid=os.getuid())))
    else:
        print(json.dumps(dict(enforced=False,allocated=len(huge))))
elif mode == "timeout":
    sys.stdin.buffer.read()
    time.sleep(10)
elif mode == "oversize":
    sys.stdin.buffer.read()
    sys.stdout.buffer.write(b"x"*131072)
elif mode == "stderr":
    sys.stdin.buffer.read()
    sys.stderr.buffer.write(b"x"*131072)
elif mode == "partial":
    sys.stdin.buffer.read()
    sys.stdout.buffer.write(b"\0\0")
elif mode == "fail":
    sys.stdin.buffer.read()
    sys.exit(7)
else:
    raise RuntimeError("unknown synthetic test fault")
