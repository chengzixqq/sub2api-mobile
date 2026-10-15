#!/usr/bin/env python3
"""Create/reopen four review roles and execute binary patch + rollback verification."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "3177500f74b005ed32512d3f79a7a24d05eac352"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--run", type=int, help="Final GitHub Actions run whose literal logs are retained")
    args = parser.parse_args()
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    records = []

    def run(command, cwd=ROOT, allowed=(0,)):
        result = subprocess.run(list(map(str, command)), cwd=cwd, text=True, encoding="utf-8", errors="replace", capture_output=True)
        records.append("$ " + subprocess.list2cmdline(list(map(str, command))) + "\nCWD: " + str(cwd) + "\nSTDOUT:\n" + result.stdout + "\nSTDERR:\n" + result.stderr + "\nEXIT: " + str(result.returncode) + "\n")
        if result.returncode not in allowed:
            (destination / "VERIFICATION.txt").write_text("\n".join(records), encoding="utf-8")
            raise RuntimeError(f"Exit {result.returncode}: {command}")
        return result.stdout

    revision = run(["git", "rev-parse", "HEAD"]).strip()
    branch = run(["git", "branch", "--show-current"]).strip()
    if branch != "codex/native-ios-rebuild" or run(["git", "status", "--porcelain"]).strip():
        raise SystemExit("Commit the native branch and make it clean before snapshotting")
    baseline_zip = destination / "BASELINE.zip"
    modified_zip = destination / "MODIFIED_FILE.zip"
    diff = destination / "DIFF_FILE.patch"
    rollback = destination / "ROLLBACK.sh"
    run(["git", "archive", "--format=zip", f"--output={baseline_zip}", BASELINE])
    run(["git", "archive", "--format=zip", f"--output={modified_zip}", revision])
    for directory, source in (("baseline", baseline_zip), ("modified", modified_zip)):
        folder = destination / directory
        folder.mkdir(exist_ok=True)
        shutil.copy2(source, folder / "SOURCE.zip")
    run(["git", "diff", "--no-index", "--binary", f"--output={diff}", "baseline/SOURCE.zip", "modified/SOURCE.zip"], cwd=destination, allowed=(1,))
    # The sibling baseline makes the rollback self-contained and usable on macOS/Linux/Git Bash.
    rollback.write_text('#!/bin/sh\nset -eu\nif [ "$#" -ne 1 ]; then echo "Usage: ROLLBACK.sh TARGET_COPY.zip" >&2; exit 64; fi\nrole_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\ncase "$1" in /*|[A-Za-z]:/*) target=$1 ;; *) target=./$1 ;; esac\ncp "$role_dir/BASELINE.zip" "$target"\nprintf "%s\\n" "ROLLBACK_RESTORED"\n', encoding="utf-8")
    rollback.chmod(0o755)
    check = [sys.executable, ROOT / "scripts/inspect_archive.py"]
    records.append("BASELINE behavior:")
    run(check + [baseline_zip])
    records.append("MODIFIED behavior:")
    run(check + [modified_zip])
    scratch = destination / "rollback-check"
    scratch.mkdir(exist_ok=True)
    restored = scratch / "SOURCE.zip"
    shutil.copy2(modified_zip, restored)
    bash = shutil.which("bash")
    if sys.platform == "win32":
        bash = "C:/Program Files/Git/bin/bash.exe"
    if not bash:
        raise SystemExit("A POSIX shell is required to execute rollback")
    run([bash, rollback.as_posix(), restored.as_posix()])
    records.append("ROLLBACK behavior (same inspector/input shape):")
    run(check + [restored])
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    assert sha(restored) == sha(baseline_zip), "Rollback hash mismatch"
    records.append("RESTORED_SHA256_EQUALS_BASELINE: true")
    run(["git", "apply", "--check", "-p2", str(diff)], cwd=scratch)
    run(["git", "apply", "-p2", str(diff)], cwd=scratch)
    assert sha(restored) == sha(modified_zip), "Patch reconstruction mismatch"
    records.append("DIFF_RECONSTRUCTS_MODIFIED: true")
    # Reapply the verified candidate bytes after the independent rollback trial.
    shutil.copy2(restored, modified_zip)
    with zipfile.ZipFile(modified_zip) as archive:
        assert archive.testzip() is None
    run(check + [modified_zip])
    run(["git", "diff", "--binary", BASELINE, revision, "--output=" + str(destination / "native-source.patch")])
    if args.run:
        run(["gh", "run", "view", str(args.run), "--repo", "chengzixqq/sub2api-mobile", "--json", "status,conclusion,jobs,url"])
        logs = run(["gh", "run", "view", str(args.run), "--repo", "chengzixqq/sub2api-mobile", "--log"])
        (destination / f"ci-run-{args.run}.log").write_text(logs, encoding="utf-8")
    records.append(f"TARGET: {ROOT}\nBRANCH: {branch}\nBASELINE: {BASELINE}\nMODIFIED: {revision}\nCHANGED: Expo application replaced with NativeApp SwiftUI project; Swift 6 language mode; iOS17; com.chengzixqq.sub2mobile.\nIPA: NOT_PRODUCED - release Xcode unavailable on observed runner. Simulator/device/live-write acceptance NOT_RUN.\n")
    for path in (modified_zip, diff, rollback, baseline_zip):
        # Open actual bytes again rather than reporting merely intended paths.
        records.append(f"REOPENED: {path}\nSHA256: {sha(path)}\nBYTES: {len(path.read_bytes())}")
    verification = destination / "VERIFICATION.txt"
    verification.write_text("\n".join(records), encoding="utf-8")
    assert verification.read_text(encoding="utf-8")
    for path in (modified_zip, diff, verification, rollback):
        print(f"{path}\nSHA256 {sha(path)}\nBYTES {len(path.read_bytes())}")


if __name__ == "__main__":
    main()
