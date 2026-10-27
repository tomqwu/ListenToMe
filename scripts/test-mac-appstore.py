#!/usr/bin/env python3
"""Verify generated distribution settings, separately from signed-app acceptance."""
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MacAppStoreConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = tempfile.TemporaryDirectory(prefix="ListenToMe store settings ")
        subprocess.run(["xcodegen", "generate", "--spec", str(ROOT / "project.yml"),
                        "--project", cls.output.name, "--quiet"], check=True)
        path = Path(cls.output.name) / "ListenToMe.xcodeproj/project.pbxproj"
        result = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(path)],
                                capture_output=True, check=True)
        cls.project = plistlib.loads(result.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.output.cleanup()

    def configurations(self, target_name):
        objects = self.project["objects"]
        target = next(value for value in objects.values()
                      if value.get("isa") == "PBXNativeTarget" and value.get("name") == target_name)
        configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
        return {objects[key]["name"]: objects[key]["buildSettings"] for key in configurations}

    def test_store_configuration_matches_listing_and_declares_sandbox_access(self):
        settings = self.configurations("ListenToMe")
        self.assertIn("AppStore", settings, "Mac listing needs its own sandboxed distribution configuration")
        store = settings["AppStore"]
        self.assertEqual(store["PRODUCT_BUNDLE_IDENTIFIER"], "com.tomwu.ListenToMe.ios")
        self.assertEqual(store["DEVELOPMENT_TEAM"], "T32FW7PZ3S")
        self.assertEqual(store["DEVELOPMENT_LANGUAGE"], "en-US")
        self.assertEqual(store["ENABLE_APP_SANDBOX"], "YES")
        with (ROOT / store["CODE_SIGN_ENTITLEMENTS"]).open("rb") as stream:
            entitlements = plistlib.load(stream)
        for capability in ("app-sandbox", "device.audio-input", "network.client",
                           "personal-information.calendars", "files.user-selected.read-write", "files.bookmarks.app-scope"):
            self.assertIs(entitlements.get("com.apple.security." + capability), True, capability)
        self.assertNotIn("com.apple.security.network.server", entitlements)
        self.assertNotIn("com.apple.security.temporary-exception.files.home-relative-path.read-write", entitlements)
        with (ROOT / "App/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["LSApplicationCategoryType"], "public.app-category.productivity")
        self.assertTrue(info["NSLocalNetworkUsageDescription"])
        self.assertIs(info["ITSAppUsesNonExemptEncryption"], False)

    def test_store_configuration_preserves_dmg_and_development_identities(self):
        settings = self.configurations("ListenToMe")
        self.assertEqual(settings["Debug"]["PRODUCT_BUNDLE_IDENTIFIER"], "com.tomwu.ListenToMe.dev")
        self.assertEqual(settings["Release"]["PRODUCT_BUNDLE_IDENTIFIER"], "com.tomwu.ListenToMe")
        self.assertEqual(settings["Release"]["CODE_SIGN_ENTITLEMENTS"], "App/ListenToMe.entitlements")
        with (ROOT / settings["Release"]["CODE_SIGN_ENTITLEMENTS"]).open("rb") as stream:
            self.assertIs(plistlib.load(stream)["com.apple.security.app-sandbox"], False)

    def test_export_preserves_version_and_exports_without_implicit_upload(self):
        path = ROOT / "Config/macOS/AppStoreExportOptions.plist"
        self.assertTrue(path.is_file(), "Mac App Store export settings are missing")
        with path.open("rb") as stream:
            settings = plistlib.load(stream)
        self.assertEqual(settings["method"], "app-store-connect")
        self.assertEqual(settings["destination"], "export")
        self.assertEqual(settings["teamID"], "T32FW7PZ3S")
        self.assertIs(settings["manageAppVersionAndBuildNumber"], False)

    def test_export_uses_local_signing_without_cloud_certificate_access(self):
        with (ROOT / "Config/macOS/AppStoreExportOptions.plist").open("rb") as stream:
            settings = plistlib.load(stream)
        self.assertEqual(settings["signingStyle"], "manual")
        self.assertEqual(settings["signingCertificate"], "Apple Distribution")
        self.assertEqual(settings["installerSigningCertificate"],
                         "3rd Party Mac Developer Installer: Qiang Wu (T32FW7PZ3S)")
        self.assertEqual(settings["provisioningProfiles"],
                         {"com.tomwu.ListenToMe.ios": "ListenToMe Mac App Store"})

    def test_sandbox_acceptance_uses_dev_identity_without_store_profile(self):
        settings = self.configurations("ListenToMe")
        self.assertIn("SandboxAcceptance", settings, "Local sandbox acceptance needs a development build, not a Store profile")
        local = settings["SandboxAcceptance"]
        self.assertEqual(local["PRODUCT_BUNDLE_IDENTIFIER"], "com.tomwu.ListenToMe.dev")
        self.assertEqual(local["BUNDLE_DISPLAY_NAME"], "ListenToMe (Dev)")
        for key in ("CODE_SIGN_ENTITLEMENTS", "ENABLE_APP_SANDBOX", "ENABLE_HARDENED_RUNTIME",
                    "ENABLE_OUTGOING_NETWORK_CONNECTIONS", "ENABLE_RESOURCE_ACCESS_AUDIO_INPUT",
                    "ENABLE_RESOURCE_ACCESS_CALENDARS", "ENABLE_USER_SELECTED_FILES"):
            self.assertEqual(local[key], settings["AppStore"][key], key)
        self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER", local)
        self.assertNotIn("DEVELOPMENT_TEAM", local, "Use the maintainer's existing Dev signing override")
        self.assertEqual(settings["AppStore"]["PRODUCT_BUNDLE_IDENTIFIER"], "com.tomwu.ListenToMe.ios")
        objects = self.project["objects"]
        project = objects[self.project["rootObject"]]
        builds = objects[project["buildConfigurationList"]]["buildConfigurations"]
        configs = {objects[key]["name"]: objects[key]["buildSettings"] for key in builds}
        for key in ("SWIFT_OPTIMIZATION_LEVEL", "SWIFT_COMPILATION_MODE", "DEBUG_INFORMATION_FORMAT"):
            self.assertEqual(configs["SandboxAcceptance"][key], configs["AppStore"][key], key)
        self.assertEqual(configs["SandboxAcceptance"]["SWIFT_OPTIMIZATION_LEVEL"], "-O")
        self.assertNotIn("DEBUG", configs["SandboxAcceptance"].get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split())

    def test_sandbox_acceptance_missing_signing_stops_before_build_or_upload(self):
        result = subprocess.run(["make", "--no-print-directory", "mac-sandbox-build", "SIGN_FLAGS="],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stable Dev signing", result.stdout + result.stderr)
        self.assertNotIn("xcodebuild", result.stdout)
        self.assertNotIn("xcodegen", result.stdout)


if __name__ == "__main__":
    unittest.main()
