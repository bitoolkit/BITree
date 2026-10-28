import json
import sys
import tarfile
import unittest
from contextlib import chdir
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

import build_release


class ReleasePackagingTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(TemporaryDirectory()))
        self.enterContext(chdir(self.root))
        self.run = self.enterContext(patch.object(build_release, "run"))
        Path("dist").mkdir()

    def write(self, name, content):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_android_only_publishes_arm64_for_both_signing_variants(self):
        for signed in [False, True]:
            with self.subTest(signed=signed):
                if signed:
                    self.write("android/key.properties", "test signing")
                for abi in ["armeabi-v7a", "arm64-v8a", "x86_64"]:
                    self.write(
                        f"build/app/outputs/flutter-apk/app-{abi}-release.apk", abi
                    )
                self.write("build/app/outputs/bundle/release/app-release.aab", "bundle")
                self.run.reset_mock()

                prefix = f"BITree-test-{signed}"
                build_release.build_android(["--release"], prefix)

                suffix = "" if signed else "-debug-signed"
                self.assertEqual(
                    {path.name for path in Path("dist").glob(f"{prefix}*")},
                    {
                        f"{prefix}-android-arm64-v8a{suffix}.apk",
                        f"{prefix}-android{suffix}.aab",
                    },
                )
                self.assertEqual(
                    Path(f"dist/{prefix}-android-arm64-v8a{suffix}.apk").read_text(),
                    "arm64-v8a",
                )
                self.assertEqual(self.run.call_count, 2)
                for call in self.run.call_args_list:
                    self.assertIn("--target-platform=android-arm64", call.args)

    def test_linux_packages_and_metadata_do_not_collide(self):
        self.enterContext(patch.object(
            build_release, "__file__", str(self.root / "tool/build_release.py")
        ))
        for architecture in ["x64", "arm64"]:
            self.write(f"build/linux/{architecture}/release/bundle/bitree", architecture)

        for machine, architecture, metadata_platform in [
            ("x86_64", "x64", "linux"),
            ("aarch64", "arm64", "linux-arm64"),
        ]:
            with self.subTest(architecture=architecture), patch.object(
                build_release.platform, "machine", return_value=machine
            ), patch.object(sys, "argv", [
                "build_release.py", "linux", "--version", "v0.3.0",
                "--native-version", "0.3.0", "--build-number", "1",
            ]):
                self.run.reset_mock()
                build_release.main()
                self.run.assert_called_once()
                self.assertIn(
                    f"--target-platform=linux-{architecture}", self.run.call_args.args
                )
                with tarfile.open(
                    f"dist/BITree-v0.3.0-linux-{architecture}.tar.xz"
                ) as archive:
                    self.assertEqual(
                        archive.extractfile("BITree/bitree").read().decode(), architecture
                    )
                metadata = json.loads(
                    Path(f"dist/BITree-v0.3.0-{metadata_platform}-update.json").read_text()
                )
                self.assertEqual(metadata["version"], "v0.3.0")
                self.assertTrue(metadata["builtAt"])

        self.assertEqual({path.name for path in Path("dist").iterdir()}, {
            "BITree-v0.3.0-linux-x64.tar.xz",
            "BITree-v0.3.0-linux-arm64.tar.xz",
            "BITree-v0.3.0-linux-update.json",
            "BITree-v0.3.0-linux-arm64-update.json",
        })


if __name__ == "__main__":
    unittest.main()
