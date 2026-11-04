import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("toolchain", Path(__file__).resolve().parents[1] / "check_toolchain.py")
toolchain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toolchain)


class ToolchainTests(unittest.TestCase):
    specification = {"xcode": "27.0", "xcodeBuild": "27A266a", "swiftCompiler": "6.4"}

    def test_accepts_release_and_patch_compiler(self):
        toolchain.validate("Xcode 27.0\nBuild version 27A266a\n", "Apple Swift version 6.4.1", "/Applications/Xcode_27.0.app/Contents/Developer", self.specification)

    def test_rejects_old_compiler(self):
        with self.assertRaises(ValueError):
            toolchain.validate("Xcode 27.0\nBuild version 27A266a", "Apple Swift version 6.3.3", "/Applications/Xcode.app", self.specification)

    def test_rejects_seed_build_even_without_beta_label(self):
        with self.assertRaises(ValueError):
            toolchain.validate("Xcode 27.0\nBuild version 27A5218g", "Apple Swift version 6.4", "/Applications/Xcode.app", self.specification)

    def test_rejects_rc_path_and_mismatched_xcode(self):
        for xcode, path in [("27.0", "Xcode_27_RC.app"), ("27.1", "Xcode.app"), ("26.6", "Xcode.app")]:
            with self.subTest(xcode=xcode, path=path), self.assertRaises(ValueError):
                toolchain.validate(f"Xcode {xcode}\nBuild version 27A266a", "Apple Swift version 6.4", path, self.specification)

    def test_rejects_unpublished_builds_including_release_shaped_identity(self):
        for build in ["27A266b", "27A100", "27A266", ""]:
            with self.subTest(build=build), self.assertRaises(ValueError):
                toolchain.validate(f"Xcode 27.0\nBuild version {build}", "Apple Swift version 6.4", "/Applications/Xcode.app", self.specification)

    def test_rejects_explicit_prerelease_labels_with_published_build(self):
        for label in ["beta", "RC", "snapshot", "preview"]:
            with self.subTest(label=label), self.assertRaises(ValueError):
                toolchain.validate("Xcode 27.0\nBuild version 27A266a", f"Apple Swift version 6.4 {label}", "/Applications/Xcode.app", self.specification)


if __name__ == "__main__":
    unittest.main()
