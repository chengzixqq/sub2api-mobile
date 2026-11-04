#!/usr/bin/env python3
"""Create/reopen four review roles and execute binary patch + rollback verification."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "3177500f74b005ed32512d3f79a7a24d05eac352"


def write_verification(path, records):
    """Keep the previous literal ledger before replacing the four-role record."""
    path = path.resolve()
    data = "\n".join(records).encode("utf-8")
    previous = path.read_bytes() if path.exists() else None
    if previous == data:
        return
    if previous is not None:
        digest = hashlib.sha256(previous).hexdigest()
        history = path.with_name(f"{path.stem}.history-{digest}{path.suffix}")
        try:
            with history.open("xb") as stream:
                stream.write(previous)
        except FileExistsError:
            if history.read_bytes() != previous:
                raise ValueError(f"Refusing to overwrite conflicting history: {history}")
        if history.read_bytes() != previous:
            raise ValueError(f"History verification failed: {history}")
        records.append(f"PREVIOUS_VERIFICATION: {history}\nSHA256: {digest}\nBYTES: {len(previous)}")
        data = "\n".join(records).encode("utf-8")
    path.write_bytes(data)
    if path.read_bytes() != data:
        raise ValueError(f"Verification write mismatch: {path}")


def verify_source_identity(manifest, command_runner, records):
    # Import the build command's canonical input list instead of maintaining a second list.
    from build import SOURCE_INPUTS

    source_revision = manifest.get("sourceRevision")
    if not isinstance(source_revision, str) or not source_revision:
        raise ValueError("IPA manifest is missing sourceRevision")
    if manifest.get("sourceDirty") is not False:
        raise ValueError("IPA must be built from a recorded clean source tree")
    objects = manifest.get("sourceInputObjects")
    if not isinstance(objects, dict) or set(objects) != set(SOURCE_INPUTS):
        raise ValueError("IPA sourceInputObjects must contain exactly the canonical build input paths")
    if command_runner is None:
        raise ValueError("A recorded Git command runner is required to verify IPA source identity")
    paths = list(SOURCE_INPUTS)
    identities = command_runner(["git", "rev-parse", "HEAD"] + [f"HEAD:{path}" for path in paths]).splitlines()
    if len(identities) != len(paths) + 1:
        raise ValueError("Git returned an unexpected number of build input identities")
    revision = identities[0]
    for path, identity in zip(paths, identities[1:]):
        if not isinstance(objects[path], str) or objects[path] != identity:
            raise ValueError(f"IPA build input differs from committed delivery source: {path}")
    records.append(f"IPA_SOURCE_REVISION: {source_revision}\nDELIVERY_SOURCE_REVISION: {revision}\nIPA_SOURCE_DIRTY: false\nBUILD_INPUT_OBJECTS_MATCH_DELIVERY_HEAD: true\nSOURCE_INPUT_OBJECTS:\n" + json.dumps(objects, indent=2))
    if source_revision != revision:
        records.append("REVISION_RELATION: differing source revisions; every canonical build input object is identical. Delivery metadata/helper changes are outside the verified build inputs.")
    else:
        records.append("REVISION_RELATION: IPA and delivery use the same source revision.")


def build_evidence(artifacts, build_run, records, command_runner=None):
    """Retain supplied execution evidence without inventing unobserved results."""
    statuses = {}
    if build_run:
        build_run = build_run.resolve()
        ledger = build_run / "commands.jsonl"
        for line in ledger.read_text(encoding="utf-8").splitlines():
            entry = json.loads(line)
            stdout_path = (build_run / entry["stdout"]).resolve()
            stderr_path = (build_run / entry["stderr"]).resolve()
            if stdout_path.parent != build_run or stderr_path.parent != build_run:
                raise ValueError("Build logs must be direct children of the supplied run directory")
            stdout = stdout_path.read_text(encoding="utf-8")
            stderr = stderr_path.read_text(encoding="utf-8")
            name = stdout_path.name.removesuffix(".stdout.log")
            statuses[name] = entry["exit_status"]
            records.append("BUILD_EVIDENCE: " + str(build_run) + "\n$ " + subprocess.list2cmdline(entry["command"]) + "\nSTDOUT:\n" + stdout + "\nSTDERR:\n" + stderr + "\nEXIT: " + str(entry["exit_status"]) + "\n")

    for name, stage in (("CORE_TESTS", "core-tests"), ("SIMULATOR_TESTS", "simulator-tests")):
        status = statuses.get(stage)
        records.append(f"{name}: " + ("NOT_RECORDED - no stage evidence supplied" if status is None else f"EXIT {status}"))

    if artifacts:
        artifacts = artifacts.resolve()
        manifest_path = artifacts / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        verify_source_identity(manifest, command_runner, records)
        ipa = artifacts / "Sub2Mobile-unsigned.ipa"
        data = ipa.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != manifest["sha256"] or len(data) != manifest["bytes"]:
            raise ValueError("Supplied IPA does not match manifest hash/size")
        if manifest["platform"] != "iphoneos" or manifest["architecture"] != "arm64" or manifest["signed"] is not False:
            raise ValueError("Manifest does not describe an unsigned arm64 iPhone device build")
        if build_run and Path(manifest["evidence"]).name != build_run.name:
            raise ValueError("Supplied run does not match the IPA manifest evidence identity")
        with zipfile.ZipFile(ipa) as archive:
            if archive.testzip() is not None:
                raise ValueError("Supplied IPA ZIP integrity failure")
            info = plistlib.loads(archive.read("Payload/Sub2Mobile.app/Info.plist"))
            if info.get("CFBundleIdentifier") != "com.chengzixqq.sub2mobile" or info.get("DTPlatformName") != "iphoneos":
                raise ValueError("Supplied IPA has the wrong bundle or platform")
        records.append(f"IPA: PRODUCED - archive integrity/hash/size/Info.plist verified\nREOPENED: {ipa}\nSHA256: {digest}\nBYTES: {len(data)}\nMANIFEST (platform/architecture/signing assertions from build pipeline):\n" + manifest_path.read_text(encoding="utf-8") + "\nTOOLCHAIN:\n" + (artifacts / "toolchain.json").read_text(encoding="utf-8"))
    else:
        records.append("IPA: NOT_RECORDED - no artifact evidence supplied")
    records.append("SIGNED_IPHONE_ACCEPTANCE: NOT_RECORDED\nLIVE_WRITE_ACCEPTANCE: NOT_RECORDED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--run", type=int, help="Final GitHub Actions run whose literal logs are retained")
    parser.add_argument("--build-artifacts", type=Path, help="Observed build/artifacts directory with IPA, manifest and toolchain")
    parser.add_argument("--build-run", type=Path, help="Observed build/runs/<run> directory with commands.jsonl and literal logs")
    args = parser.parse_args()
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    records = []

    def run(command, cwd=ROOT, allowed=(0,)):
        result = subprocess.run(list(map(str, command)), cwd=cwd, text=True, encoding="utf-8", errors="replace", capture_output=True)
        records.append("$ " + subprocess.list2cmdline(list(map(str, command))) + "\nCWD: " + str(cwd) + "\nSTDOUT:\n" + result.stdout + "\nSTDERR:\n" + result.stderr + "\nEXIT: " + str(result.returncode) + "\n")
        if result.returncode not in allowed:
            write_verification(destination / "VERIFICATION.txt", records)
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
    rollback.write_text('#!/bin/sh\nset -eu\nif [ "$#" -ne 1 ]; then echo "Usage: ROLLBACK.sh TARGET_COPY.zip" >&2; exit 64; fi\nrole_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\ncase "$1" in /*|[A-Za-z]:/*) target=$1 ;; *) target=./$1 ;; esac\ncp "$role_dir/BASELINE.zip" "$target"\nprintf "%s\\n" "ROLLBACK_RESTORED"\n', encoding="utf-8", newline="\n")
    rollback.chmod(0o755)
    check = [sys.executable, ROOT / "scripts/inspect_archive.py"]
    records.append("BASELINE behavior:")
    run(check + ["SOURCE.zip"], cwd=destination / "baseline")
    records.append("MODIFIED behavior:")
    run(check + ["SOURCE.zip"], cwd=destination / "modified")
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
    run(check + ["SOURCE.zip"], cwd=scratch)
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
    records.append(f"TARGET: {ROOT}\nBRANCH: {branch}\nBASELINE: {BASELINE}\nMODIFIED: {revision}\nCHANGED: Expo application replaced with NativeApp SwiftUI project; Swift 6 language mode; iOS17; com.chengzixqq.sub2mobile.\n")
    build_evidence(args.build_artifacts, args.build_run, records, run)
    for path in (modified_zip, diff, rollback, baseline_zip):
        # Open actual bytes again rather than reporting merely intended paths.
        records.append(f"REOPENED: {path}\nSHA256: {sha(path)}\nBYTES: {len(path.read_bytes())}")
    verification = destination / "VERIFICATION.txt"
    write_verification(verification, records)
    assert verification.read_text(encoding="utf-8")
    (destination / "README.txt").write_text("MODIFIED_FILE.zip is the native source snapshot, NOT an IPA.\nDIFF_FILE.patch reconstructs that exact ZIP from BASELINE.zip:\n  cp BASELINE.zip SOURCE.zip\n  git apply --check -p2 DIFF_FILE.patch\n  git apply -p2 DIFF_FILE.patch\nROLLBACK.sh accepts a target ZIP copy and restores pristine BASELINE.zip bytes:\n  ./ROLLBACK.sh /absolute/path/to/SOURCE.zip\nKeep ROLLBACK.sh beside BASELINE.zip. The original repository is not modified.\nThe supplementary native-source.patch applies the code-tree change to legacy commit 3177500.\nVERIFICATION.txt contains actual commands, outputs, statuses, hashes, and CI logs.\n", encoding="utf-8")
    for path in (modified_zip, diff, verification, rollback):
        print(f"{path}\nSHA256 {sha(path)}\nBYTES {len(path.read_bytes())}")


if __name__ == "__main__":
    main()
