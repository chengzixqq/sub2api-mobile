#!/usr/bin/env python3
"""Read a source snapshot without extracting it or executing its contents."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile


def inspect(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "Corrupt ZIP"
        names = set(archive.namelist())
        if "Toolchain.json" in names and "Sub2Mobile.xcodeproj/project.pbxproj" in names:
            spec = json.loads(archive.read("Toolchain.json"))
            result = {"stack": "native-swiftui", "xcode": spec["xcode"], "swiftCompiler": spec["swiftCompiler"], "swiftLanguageMode": spec["swiftLanguageMode"], "minimumIOS": spec["minimumIOS"], "bundleIdentifier": spec["bundleIdentifier"], "expoUpdates": False}
        else:
            manifest = json.loads(archive.read("package.json"))
            result = {"stack": "legacy-expo", "expo": manifest["dependencies"]["expo"], "nativeProject": False}
        assert "LICENSE" in names, "Missing preserved license"
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    print("sha256=" + hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == "__main__":
    inspect(sys.argv[1])
