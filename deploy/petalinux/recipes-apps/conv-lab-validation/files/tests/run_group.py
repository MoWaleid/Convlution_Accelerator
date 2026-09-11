"""User-invoked reporting harness. Importing this module does not run tests."""
import argparse
from collections import Counter
from datetime import datetime,timezone
import importlib
import json
from pathlib import Path
import platform
import sys
import traceback
import unittest
import uuid

MODULES = {
    "A": ("tests.test_a_grammar","tests.test_a_admission","tests.test_a_storage","tests.test_a_worker"),
    "B": ("tests.test_b_reference","tests.test_b_integration"),
    "C": ("tests.test_c_conversion","tests.test_c_offline"),
}


def source_observation():
    # Bind future evidence to observed bytes. Old reports remain unchanged.
    from conv_lab.release_io import code_identity
    from conv_lab.strict import sha256
    value = code_identity()
    root = Path(__file__).resolve().parent
    value["test_files"] = {p.name: sha256(p.read_bytes()) for p in sorted(root.glob("*.py"))}
    return value


def environment():
    info = dict(python=sys.version,executable=sys.executable,platform=platform.platform(),
                pillow="UNAVAILABLE",decoder_versions={},software_only=True,
                board_qualification="NOT RUN")
    try:
        from PIL import __version__,features
        info["pillow"] = __version__
        info["decoder_versions"] = {name:features.version(name) for name in ("jpg","zlib")}
    except Exception as exc:
        info["dependency_observation_error"] = type(exc).__name__+": "+str(exc)
    return info


def flatten(suite):
    for value in suite:
        if isinstance(value,unittest.TestSuite):
            yield from flatten(value)
        else:
            yield value


class EvidenceResult(unittest.TextTestResult):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self.records = {}
        self.subcases = []

    def startTest(self,test):
        super().startTest(test)
        method = getattr(test,test._testMethodName,None)
        self.records[test.id()] = dict(id=test.id(),status="NOT RUN",started=True,
            domain=getattr(test,"evidence_domain","desktop_software"),
            seed=getattr(method,"differential_seed",None),details=[])

    def _mark(self,test,status,detail=None):
        entry = self.records.setdefault(test.id(),dict(id=test.id(),status="NOT RUN",started=False,
            domain=getattr(test,"evidence_domain","desktop_software"),seed=None,details=[]))
        # A failed subcase must not be overwritten by another successful subcase.
        if entry["status"] != "FAIL":
            entry["status"] = status
        if detail:
            entry["details"].append(detail)

    def addSuccess(self,test):
        super().addSuccess(test); self._mark(test,"PASS")

    def addFailure(self,test,err):
        super().addFailure(test,err); self._mark(test,"FAIL",self._exc_info_to_string(err,test))

    def addError(self,test,err):
        super().addError(test,err); self._mark(test,"FAIL",self._exc_info_to_string(err,test))

    def addSkip(self,test,reason):
        super().addSkip(test,reason); self._mark(test,"SKIPPED",reason)

    def addSubTest(self,test,subtest,err):
        super().addSubTest(test,subtest,err)
        self.subcases.append(dict(parent=test.id(),case=str(subtest),
                                  status="FAIL" if err else "PASS"))
        if err:
            self._mark(test,"FAIL",self._exc_info_to_string(err,test))

    def stopTest(self,test):
        if hasattr(test,"worker_records"):
            self.records[test.id()]["worker_records"] = test.worker_records
        super().stopTest(test)


def status_of(records):
    statuses = [r["status"] for r in records]
    if "FAIL" in statuses:
        return "FAIL"
    if not statuses or "NOT RUN" in statuses:
        return "NOT RUN"
    if "SKIPPED" in statuses:
        return "SKIPPED"
    return "PASS"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("group",choices=tuple(MODULES))
    parser.add_argument("--report-dir",type=Path,default=Path(__file__).resolve().parent.parent/"reports")
    args = parser.parse_args()
    args.report_dir.mkdir(parents=True,exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    suite = unittest.TestSuite()
    for name in MODULES[args.group]:
        suite.addTests(unittest.defaultTestLoader.loadTestsFromName(name))
    cases = list(flatten(suite))
    runner = unittest.TextTestRunner(verbosity=2,resultclass=EvidenceResult)
    result = runner._makeResult()
    interrupted = False
    result.startTestRun()
    try:
        suite(result)
    except KeyboardInterrupt:
        interrupted = True
    finally:
        result.stopTestRun()
        for test in cases:
            if test.id() not in result.records:
                method = getattr(test,test._testMethodName,None)
                result.records[test.id()] = dict(id=test.id(),status="NOT RUN",started=False,
                    domain=getattr(test,"evidence_domain","desktop_software"),
                    seed=getattr(method,"differential_seed",None),details=[])
        records = list(result.records.values())
        if interrupted:
            for item in records:
                if item["started"] and item["status"] == "NOT RUN":
                    item["status"] = "FAIL"
                    item["details"].append("Interrupted; no passing result.")
        worker = [r for r in records if r["domain"] == "linux_worker_enforcement"]
        differential = [r for r in records if r["seed"] is not None]
        report = dict(group=args.group,started_utc=started,finished_utc=datetime.now(timezone.utc).isoformat(),
            status="FAIL" if interrupted else status_of(records),interrupted=interrupted,
            environment=environment(),source_observation=source_observation(),linux_worker_enforcement=status_of(worker),
            actual_test_methods_started=result.testsRun,status_counts=dict(Counter(r["status"] for r in records)),
            actual_subcases=len(result.subcases),subcase_counts=dict(Counter(r["status"] for r in result.subcases)),
            differential=dict(planned=len(differential),started=sum(r["started"] for r in differential),
                              seeds=[r["seed"] for r in differential if r["started"]],
                              statuses=dict(Counter(r["status"] for r in differential))),
            tests=records,subcases=result.subcases,M1_complete=False,M2_complete=False,
            limitations=["Software evidence only; no board qualification.",
                         "Fixture decoder records are not Linux enforcement evidence.",
                         "Reference computation has no decoder deadline."])
        name = f"M2-{args.group}-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}.json"
        path = args.report_dir/name
        with path.open("x",encoding="utf-8",newline="\n") as stream:
            json.dump(report,stream,indent=2,allow_nan=False)
            stream.write("\n")
        print(f"\n{report['status']}: {path}")
        print(f"Linux worker enforcement: {report['linux_worker_enforcement']}")
    return 1 if report["status"] in ("FAIL","NOT RUN") else (2 if report["status"] == "SKIPPED" else 0)


if __name__ == "__main__":
    raise SystemExit(main())
