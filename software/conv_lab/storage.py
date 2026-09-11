"""Bounded import/publication and retention planning, without deployment/backup code."""
import io
import json
import os
import stat
import struct
import tempfile
import threading
import zipfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from .admission import IdentityCatalog
from .bundles import ReadBudget,fingerprint,read_bundle,references,relative_path
from .errors import AdmissionError
from .schemas import bundle_identity
from .strict import integer,parse_json,require,sha256
from .types import Blob,Bundle

FREE_HEADROOM = 536870912
DISPOSABLE_BUDGET = 268435456


def _preflight_zip(data,maximum_entries):
    """Bound central-directory parsing BEFORE ZipFile allocates ZipInfo objects."""
    end = data.rfind(b"PK\x05\x06",max(0,len(data)-65557))
    require(end >= 0 and end+22 <= len(data),"ZIP end record")
    disk,cd_disk,disk_count,count,size,offset,comment = struct.unpack_from("<HHHHIIH",data,end+4)
    require(end+22+comment == len(data),"ZIP trailing data")
    require(disk == cd_disk == 0 and disk_count == count,"multidisk ZIP unsupported")
    require(count != 65535 and size != 0xffffffff and offset != 0xffffffff,"ZIP64 unsupported")
    require(count <= maximum_entries and offset+size == end,"ZIP directory budget/bounds")
    pos,actual = offset,0
    while pos < end:
        require(pos+46 <= end and data[pos:pos+4] == b"PK\x01\x02","ZIP central header")
        name,extra,note = struct.unpack_from("<HHH",data,pos+28)
        require(pos+46+name+extra+note <= end,"ZIP central entry bounds")
        require(b"\0" not in data[pos+46:pos+46+name],"NUL archive filename")
        actual += 1
        require(actual <= maximum_entries,"actual ZIP entry budget")
        pos += 46+name+extra+note
    require(pos == end and actual == count,"ZIP central entry count")


def read_zip_bundle(archive,kind,budget=ReadBudget()):
    """Bound actual decompression into a frozen snapshot; never extract paths."""
    require(type(archive) is bytes and len(archive) <= budget.max_bundle_bytes,"compressed import budget")
    _preflight_zip(archive,budget.max_files)
    files, total, names = [],0,set()
    try:
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            require(len(z.infolist()) <= budget.max_files,"archive entry budget")
            for info in z.infolist():
                name = info.filename[:-1] if info.is_dir() else info.filename
                relative_path(name)
                require(name.casefold() not in names,"duplicate/aliased archive entry")
                names.add(name.casefold())
                mode = info.external_attr >> 16
                require(not stat.S_ISLNK(mode) and not (info.flag_bits & 1),"archive link/encryption")
                if info.is_dir():
                    continue
                require(stat.S_IFMT(mode) in (0,stat.S_IFREG),"archive special entry")
                maximum = budget.max_bundle_bytes-total
                if name == f"{kind}.json":
                    maximum = min(maximum,budget.max_manifest_bytes)
                if kind == "dataset" and name != "dataset.json":
                    maximum = min(maximum,8388608)
                require(info.file_size <= maximum,"declared decompressed budget")
                chunks,size = [],0
                with z.open(info) as source:
                    while True:
                        chunk = source.read(min(65536,maximum-size+1))
                        if not chunk:
                            break
                        size += len(chunk)
                        require(size <= maximum,"actual decompressed growth")
                        chunks.append(chunk)
                require(size == info.file_size,"archive size mismatch")
                data = b"".join(chunks); total += size
                files.append(Blob(name,data,sha256(data)))
        require(len({b.path.casefold() for b in files}) == len(files),"archive aliases")
        bundle = Bundle(kind,"zip-snapshot",tuple(files))
        m = parse_json(bundle.blob(f"{kind}.json").data,budget.max_manifest_bytes)
        refs = references(kind,m)
        require({b.path for b in files} == {f"{kind}.json"} | {p for p,_ in refs},"archive inventory")
        require(all(bundle.blob(p).sha256 == h for p,h in refs),"archive integrity")
        return bundle
    except (OSError,KeyError,StopIteration,zipfile.BadZipFile,RuntimeError,NotImplementedError) as exc:
        raise AdmissionError(f"archive rejected: {exc}") from exc


class SpaceLedger:
    """One exclusive application owner; free_bytes observes the target filesystem.

    Reserve peak simultaneous temporary+final bytes. Materialized bytes reduce the
    outstanding reservation because they already reduce observed free space.
    External filesystem writers still require repeated checks/platform qualification.
    """
    def __init__(self,free_bytes):
        self._free_bytes = free_bytes
        self._remaining = {}
        self._lock = threading.RLock()

    @contextmanager
    def reserve(self,temporary,final):
        integer(temporary); integer(final)
        token = object()
        with self._lock:
            amount = temporary+final
            free = integer(self._free_bytes())
            require(free-sum(self._remaining.values())-amount >= FREE_HEADROOM,"insufficient peak storage/headroom")
            self._remaining[token] = amount
        try:
            yield Reservation(self,token)
        finally:
            with self._lock:
                self._remaining.pop(token,None)


class Reservation:
    def __init__(self,ledger,token):
        self._ledger,self._token = ledger,token

    def materialize(self,count,writer=None):
        """Serialize accounting with the actual write/flush when supplied."""
        integer(count)
        with self._ledger._lock:
            remaining = self._ledger._remaining
            require(self._token in remaining and count <= remaining[self._token],"operation grew beyond reservation")
            require(integer(self._ledger._free_bytes())-sum(remaining.values()) >= FREE_HEADROOM,"filesystem headroom lost")
            if writer is not None:
                writer()
            remaining[self._token] -= count


def write_bounded(stream,chunks,maximum,reservation):
    integer(maximum)
    total = 0
    for chunk in chunks:
        require(type(chunk) is bytes,"output must be immutable bytes")
        require(total+len(chunk) <= maximum,"output growth limit")
        def write_chunk():
            require(stream.write(chunk) == len(chunk),"short storage write")
            stream.flush()
        reservation.materialize(len(chunk),writer=write_chunk)
        total += len(chunk)
    return total


class Publisher:
    """Atomic no-overwrite publication. Validator is a required trusted adapter.

    register_existing must inventory all embedded/imported origins before use.
    Failed staging is retained with a bounded failure record; it is not disposable
    evidence. No automatic recovery of stale publication locks is attempted.
    """
    def __init__(self,library,staging,ledger,catalog):
        self.library,self.staging = Path(library).resolve(),Path(staging).resolve()
        require(self.library != self.staging and self.library not in self.staging.parents and
                self.staging not in self.library.parents,"separate staging/library roots")
        require(type(catalog) is IdentityCatalog,"identity catalog required")
        self.ledger,self.catalog = ledger,catalog
        self._inventory_ready = False

    def register_existing(self,bundles):
        self.catalog.register(tuple(bundles))
        self._inventory_ready = True

    def publish(self,bundle,validator):
        require(self._inventory_ready,"register the existing embedded/imported inventory first")
        require(type(bundle) is Bundle,"frozen snapshot required")
        require(all(type(b.data) is bytes and sha256(b.data) == b.sha256 for b in bundle.files),"snapshot integrity")
        validator(bundle)  # full selected-kind semantics, before staging/publication
        key = bundle_identity(bundle)
        label = sha256(json.dumps(key,separators=(",",":")).encode())
        self.library.mkdir(parents=True,exist_ok=True)
        self.staging.mkdir(parents=True,exist_ok=True)
        require(self.library.stat().st_dev == self.staging.stat().st_dev,"atomic publication needs one filesystem")
        lock = self.library/".publication-lock"
        try:
            lock.mkdir(mode=0o700)
        except FileExistsError as exc:
            raise AdmissionError("publication busy/stale lock; explicit recovery required") from exc
        stage = None
        try:
            with self.catalog._lock:
                self.catalog.check((bundle,))
                existing = self.catalog._entries.get(key)
                if existing is not None:
                    # Recheck stored bytes; a stale catalog is not integrity evidence.
                    current = read_bundle(existing[1],bundle.kind)
                    validator(current)
                    require(fingerprint(current) == fingerprint(bundle),"existing origin changed")
                    return Path(existing[1])
                target = self.library/label
                require(not target.exists() and not target.is_symlink(),"publication target already exists")
                size = sum(len(b.data) for b in bundle.files)
                # Rename has no second payload copy; reserve bounded metadata/failure space too.
                overhead = 65536+4096*len(bundle.files)
                with self.ledger.reserve(temporary=overhead,final=size) as reservation:
                    stage = Path(tempfile.mkdtemp(prefix="import-",dir=self.staging))
                    for blob in bundle.files:
                        dest = stage/relative_path(blob.path)
                        dest.parent.mkdir(parents=True,exist_ok=True)
                        with dest.open("xb") as stream:
                            chunks = (blob.data[p:p+65536] for p in range(0,len(blob.data),65536))
                            write_bounded(stream,chunks,len(blob.data),reservation)
                            stream.flush(); os.fsync(stream.fileno())
                    check = read_bundle(stage,bundle.kind)
                    require(fingerprint(check) == fingerprint(bundle),"staged copy mismatch")
                    validator(check)
                    require(not target.exists(),"publication collision")
                    os.rename(stage,target)
                    published = Bundle(bundle.kind,str(target),bundle.files)
                    self.catalog.register((published,))
                    return target
        except Exception as exc:
            if stage is not None and stage.exists():
                # Keep failed bytes/evidence. Never recursively delete protected failure data.
                try:
                    message = (type(exc).__name__+": "+str(exc)).encode("utf-8")[:2048]+b"\n"
                    with self.ledger.reserve(temporary=8192,final=0) as evidence_space:
                        with (stage/"IMPORT_FAILURE.txt").open("xb") as report:
                            write_bounded(report,(message,),2049,evidence_space)
                except (OSError,AdmissionError):
                    # The exception still identifies protected staging if even evidence
                    # cannot fit without spending the required filesystem headroom.
                    pass
                raise AdmissionError(f"publication failed; protected staging retained at {stage}: {exc}") from exc
            raise
        finally:
            lock.rmdir()  # Exact lock created by this call; never a recursive removal.


@dataclass(frozen=True,slots=True)
class Payload:
    identity: str
    bytes: int
    created_order: int
    kind: str
    outcome: str
    pinned: bool
    disposable: bool


def retention_candidates(payloads,space_needed=0):
    """Plan only. Return payload IDs, never summaries; no filesystem deletion API."""
    integer(space_needed)
    require(len({p.identity for p in payloads}) == len(payloads),"duplicate retention identity")
    for p in payloads:
        integer(p.bytes); integer(p.created_order)
        require(type(p.pinned) is bool and type(p.disposable) is bool,"retention flags")
    classified = [p for p in payloads if p.disposable]
    need = max(space_needed,sum(p.bytes for p in classified)-DISPOSABLE_BUDGET,0)
    eligible = sorted((p for p in classified if p.kind == "run_payload" and p.outcome == "PASS" and not p.pinned),
                      key=lambda p:(p.created_order,p.identity))
    picked,released = [],0
    for p in eligible:
        if released >= need:
            break
        picked.append(p.identity); released += p.bytes
    require(released >= need,"protected content prevents retention/headroom target")
    return tuple(picked)
