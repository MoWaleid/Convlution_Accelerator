import io
import tempfile
import unittest
import zipfile
from pathlib import Path

from conv_lab.admission import IdentityCatalog
from conv_lab.bundles import ReadBudget,fingerprint,read_bundle
from conv_lab.errors import AdmissionError
from conv_lab.schemas import hardware
from conv_lab.storage import (DISPOSABLE_BUDGET,FREE_HEADROOM,Payload,Publisher,SpaceLedger,
                              read_zip_bundle,retention_candidates,write_bounded)
from .fixtures import change_json,write_selection


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="m2-storage-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.roots,_ = write_selection(self.base/"source")

    def test_peak_reservation_actual_growth_and_concurrency(self):
        free = [FREE_HEADROOM+100]
        ledger = SpaceLedger(lambda:free[0])
        with ledger.reserve(40,60) as reservation:
            with self.assertRaises(AdmissionError):
                with ledger.reserve(1,0):
                    pass
            reservation.materialize(20); free[0] -= 20
            with self.assertRaises(AdmissionError):
                reservation.materialize(81)
            sink = io.BytesIO()
            self.assertEqual(write_bounded(sink,[b"abc"],3,reservation),3)
            with self.assertRaises(AdmissionError):
                write_bounded(sink,[b"toolong"],1,reservation)
            free[0] = FREE_HEADROOM-1
            with self.assertRaises(AdmissionError):
                reservation.materialize(1)
        with self.assertRaises(AdmissionError):
            with ledger.reserve(100,100):
                pass

    def test_archive_budget_hash_paths_and_inventory(self):
        def archive(extra=None):
            result = io.BytesIO()
            with zipfile.ZipFile(result,"w",compression=zipfile.ZIP_DEFLATED) as z:
                for p in self.roots[0].iterdir():
                    z.writestr(p.name,p.read_bytes())
                if extra:
                    z.writestr(*extra)
            return result.getvalue()
        good = archive()
        hardware(read_zip_bundle(good,"hardware"))
        for raw in (archive(("../escape",b"bad")),archive(("unlisted",b"bad")),b"notzip"):
            with self.assertRaises(AdmissionError):
                read_zip_bundle(raw,"hardware")
        with self.assertRaises(AdmissionError):
            read_zip_bundle(good,"hardware",ReadBudget(max_bundle_bytes=100,max_files=3))
        # Highly compressible extra data must not bypass decompressed-byte budgeting.
        with self.assertRaises(AdmissionError):
            read_zip_bundle(archive(("bomb",b"x"*200000)),"hardware",
                            ReadBudget(max_bundle_bytes=100000))
        broken = self.roots[0]/"SYNTHETIC-NOT-PROGRAMMABLE.bit"
        broken.write_bytes(b"hash changed")
        with self.assertRaises(AdmissionError):
            read_zip_bundle(archive(),"hardware")

    def publisher(self):
        result = Publisher(self.base/"library",self.base/"staging",
                           SpaceLedger(lambda:FREE_HEADROOM+10000000),IdentityCatalog())
        return result

    def test_atomic_publication_and_identity(self):
        bundle = read_bundle(self.roots[0],"hardware")
        publisher = self.publisher()
        with self.assertRaises(AdmissionError):
            publisher.publish(bundle,hardware)
        publisher.register_existing(())
        dest = publisher.publish(bundle,hardware)
        self.assertTrue(dest.is_dir())
        self.assertEqual(fingerprint(read_bundle(dest,"hardware")),fingerprint(bundle))
        self.assertEqual(publisher.publish(bundle,hardware),dest)
        change_json(self.roots[0]/"hardware.json",lambda m:m["extensions"].update(note="changed"))
        with self.assertRaises(AdmissionError):
            publisher.publish(read_bundle(self.roots[0],"hardware"),hardware)
        self.assertEqual(fingerprint(read_bundle(dest,"hardware")),fingerprint(bundle))

    def test_failure_staging_retained(self):
        publisher = self.publisher(); publisher.register_existing(())
        count = [0]
        def validator(bundle):
            hardware(bundle); count[0] += 1
            if count[0] == 2:
                raise AdmissionError("synthetic post-copy failure")
        with self.assertRaises(AdmissionError):
            publisher.publish(read_bundle(self.roots[0],"hardware"),validator)
        self.assertEqual(len(list((self.base/"staging").glob("*/IMPORT_FAILURE.txt"))),1)
        self.assertFalse(any((self.base/"library").iterdir()))

    def test_retention_protection_and_oldest_first(self):
        records = [Payload("older",10,1,"run_payload","PASS",False,True),
                   Payload("newer",20,2,"run_payload","PASS",False,True),
                   Payload("summary",10,0,"summary","PASS",False,False)]
        self.assertEqual(retention_candidates(records,15),("older","newer"))
        for kind,outcome,pinned in (("qualification","PASS",False),("failure","FAIL",False),
                                    ("bundle","PASS",False),("recovery","PASS",False),
                                    ("run_payload","PASS",True),("run_payload","FAIL",False)):
            with self.subTest(kind=kind,pinned=pinned),self.assertRaises(AdmissionError):
                retention_candidates([Payload("protected",DISPOSABLE_BUDGET+1,0,kind,outcome,pinned,True)])
