#!/usr/bin/env python3
"""Test and package with the pinned release toolchain, on a Mac or GitHub runner."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
RUN = BUILD / "runs" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid4().hex[:8])
EVIDENCE = RUN / "commands.jsonl"


def run(command, name):
    RUN.mkdir(parents=True, exist_ok=True)
    print("+ " + " ".join(map(str, command)), flush=True)
    stdout_path = RUN / f"{name}.stdout.log"
    stderr_path = RUN / f"{name}.stderr.log"
    try:
        # Keep stage logs readable while Xcode runs or collects diagnostics.
        with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open("w", encoding="utf-8") as stderr:
            result = subprocess.run(list(map(str, command)), cwd=ROOT, text=True, stdout=stdout, stderr=stderr)
    except OSError as error:
        stderr_path.write_text(str(error), encoding="utf-8")
        result = subprocess.CompletedProcess(command, 127)
    output = stdout_path.read_text(encoding="utf-8")
    errors = stderr_path.read_text(encoding="utf-8")
    with EVIDENCE.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({"command": list(map(str, command)), "exit_status": result.returncode, "stdout": f"{name}.stdout.log", "stderr": f"{name}.stderr.log"}) + "\n")
    print(output, end="", flush=True)
    print(errors, end="", file=sys.stderr, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
    return output


def simulator():
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], "simulators"))["devices"]
    for runtime in sorted(devices, key=lambda r: tuple(map(int, re.findall(r"\d+", r))), reverse=True):
        if ".iOS-" not in runtime:
            continue
        for device in devices[runtime]:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                return device["udid"]
    raise SystemExit("No available iPhone simulator. Install an iOS runtime in Xcode Settings > Components.")


def package():
    app = BUILD / "DerivedData/Build/Products/Release-iphoneos/Sub2Mobile.app"
    if not app.is_dir():
        raise SystemExit(f"Missing device build: {app}")
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "com.chengzixqq.sub2mobile" or info.get("DTPlatformName") != "iphoneos":
        raise SystemExit("Refusing to package a wrong bundle or a simulator build")
    executable = app / info["CFBundleExecutable"]
    architecture = run(["xcrun", "lipo", "-archs", executable], "device-architecture").strip()
    if architecture != "arm64":
        raise SystemExit(f"Expected arm64 only; found {architecture}")
    load_commands = run(["xcrun", "otool", "-l", executable], "device-load-commands")
    if not re.search(r"\bplatform\s+(?:2|IOS)\s", load_commands):
        raise SystemExit("Mach-O is not an iOS device binary")
    if (app / "embedded.mobileprovision").exists() or (app / "_CodeSignature").exists():
        raise SystemExit("Expected an unsigned bundle without embedded provisioning")
    artifact_dir = BUILD / "artifacts"
    artifact_dir.mkdir(exist_ok=True)
    ipa = artifact_dir / "Sub2Mobile-unsigned.ipa"
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(app.rglob("*")):
            archive.write(file, "Payload/Sub2Mobile.app/" + file.relative_to(app).as_posix())
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise SystemExit("IPA ZIP integrity failure")
        archived_info = plistlib.loads(archive.read("Payload/Sub2Mobile.app/Info.plist"))
        if archived_info["CFBundleIdentifier"] != info["CFBundleIdentifier"]:
            raise SystemExit("IPA metadata mismatch")
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (artifact_dir / "SHA256SUMS").write_text(f"{digest}  {ipa.name}\n", encoding="utf-8")
    shutil.copy2(BUILD / "toolchain.json", artifact_dir / "toolchain.json")
    report = {"ipa": str(ipa), "sha256": digest, "bytes": ipa.stat().st_size, "architecture": architecture, "platform": "iphoneos", "signed": False, "evidence": str(RUN), "deviceAcceptance": "NOT_RUN - sign locally, then verify on iPhone"}
    (artifact_dir / "manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["all", "unit", "simulator", "package"], nargs="?", default="all")
    stage = parser.parse_args().stage
    print("Evidence directory: " + str(RUN), flush=True)
    run([sys.executable, "scripts/check_toolchain.py"], "toolchain-check")
    shutil.copy2(BUILD / "toolchain.json", RUN / "toolchain.json")
    if stage in ("all", "unit"):
        run(["xcrun", "swift", "test", "--parallel"], "core-tests")
    base = ["xcodebuild", "-project", "Sub2Mobile.xcodeproj", "-scheme", "Sub2Mobile", "-derivedDataPath", str(BUILD / "DerivedData")]
    if stage in ("all", "simulator"):
        run(base + ["-configuration", "Debug", "-destination", "id=" + simulator(), "-resultBundlePath", str(RUN / "UITests.xcresult"), "-collect-test-diagnostics", "never", "test", "CODE_SIGNING_ALLOWED=NO"], "simulator-tests")
    if stage in ("all", "package"):
        run(base + ["-configuration", "Release", "-sdk", "iphoneos", "-destination", "generic/platform=iOS", "build", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="], "device-build")
        package()


if __name__ == "__main__":
    main()
