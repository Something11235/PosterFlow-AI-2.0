"""Verify the saved source checkpoint and validated candidate without cloud writes.

This checks local files only; it is not a production database/Storage backup or
authorization to deploy. Run from this repository with Python 3.10 or later.
"""
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify():
    root = Path(__file__).resolve().parents[1]
    report_path = root / "artifacts/release-prep-20261023/validated-candidate.json"
    if not report_path.is_file():
        raise SystemExit("Missing local validation record; run release preparation first.")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    backup = Path(report["backup_directory"])
    checkpoint = json.loads((backup / "checkpoint.json").read_text(encoding="utf-8"))
    failures = []
    for item in checkpoint["files"]:
        path = backup / item["file"]
        if not path.is_file() or digest(path) != item["sha256"]:
            failures.append("backup:" + item["file"])
    for item in report["candidate_source"]:
        path = root / item["file"]
        if not path.is_file() or digest(path) != item["sha256"]:
            failures.append("candidate:" + item["file"])
    for item in report["validated_assets"]:
        path = root / "frontend/dist/assets" / item["file"]
        if not path.is_file() or digest(path) != item["sha256"]:
            failures.append("build:" + item["file"])
    for item in report["evidence"]:
        path = root / item["file"]
        if not path.is_file() or digest(path) != item["sha256"]:
            failures.append("evidence:" + item["file"])
    if failures:
        print(json.dumps({"verified": False, "changed_or_missing": failures}, ensure_ascii=False))
        raise SystemExit(1)
    print(json.dumps({"verified": True, "stable_commit": checkpoint["stable_commit"],
                      "candidate_files": len(report["candidate_source"]),
                      "source_backup_only": True,
                      "production_release_authorized_by_this_check": False}, ensure_ascii=False))


if __name__ == "__main__":
    verify()
