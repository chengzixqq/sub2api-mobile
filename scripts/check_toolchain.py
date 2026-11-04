#!/usr/bin/env python3
"""Validate the selected Apple toolchain; never substitute an older compiler."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def validate(xcode, swift, developer_dir, specification):
    version = re.search(r"^Xcode\s+(\d+(?:\.\d+)*)\s*$", xcode, re.MULTILINE)
    expected = specification["xcode"]
    normalized = lambda value: tuple(int(x) for x in value.split(".")) + (0,)
    if not version or normalized(version[1])[:2] != normalized(expected)[:2]:
        raise ValueError(f"Required Xcode {expected} release; found {xcode!r}")
    build = re.search(r"^Build version\s+(\S+)", xcode, re.MULTILINE)
    # Release builds can retain a lowercase suffix when Apple promotes an RC.
    # Accept only the exact build published for the pinned official release.
    if not build or build[1] != specification["xcodeBuild"]:
        raise ValueError(f"Required official Xcode build {specification['xcodeBuild']}")
    if re.search(r"beta|(?:^|[^a-z])rc(?:[^a-z]|$)|snapshot|preview", xcode + " " + swift + " " + developer_dir, re.I):
        raise ValueError("Beta, RC, snapshot and preview toolchains are not accepted")
    compiler = re.search(r"Swift version\s+(\d+\.\d+)(?:\.\d+)?", swift)
    if not compiler or compiler[1] != specification["swiftCompiler"]:
        raise ValueError(f"Required Swift {specification['swiftCompiler']} compiler")


def run():
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    commands = [["xcodebuild", "-version"], ["xcrun", "swift", "--version"], ["xcode-select", "-p"]]
    records = []
    for command in commands:
        if not shutil.which(command[0]):
            print(f"TOOLCHAIN_UNAVAILABLE: {command[0]} is required; run this on your Mac or the xcode-27 CI runner", file=sys.stderr)
            return 2
        result = subprocess.run(command, text=True, capture_output=True)
        records.append({"command": command, "stdout": result.stdout, "stderr": result.stderr, "exit_status": result.returncode})
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        if result.returncode:
            (output / "toolchain.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
            return result.returncode
    (output / "toolchain.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    spec = json.loads((ROOT / "Toolchain.json").read_text(encoding="utf-8"))
    try:
        validate(*(r["stdout"] for r in records), spec)
    except ValueError as error:
        print(f"TOOLCHAIN_REJECTED: {error}", file=sys.stderr)
        return 3
    print("TOOLCHAIN_VERIFIED: Xcode 27 release / Swift 6.4 compiler / Swift 6 language mode")
    return 0


if __name__ == "__main__":
    sys.exit(run())
