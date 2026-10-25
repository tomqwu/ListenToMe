"""Behavior contracts for the repository's BDD gate (offline, no Apple access)."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("bdd", Path(__file__).with_name("bdd.py"))
bdd = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bdd)


class BDDTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.binding = {"suite": "core", "file": "Tests/ListenToMeCoreTests/ExampleTests.swift",
                        "test": "ExampleTests/testKeepsData"}
        self.scenario = {
            "id": "DATA-001", "name": "Keep data", "given": "a saved conversation",
            "when": "the archive reopens", "then": "its data remains readable",
            "covers": ["App/*"], "bindings": [self.binding],
        }
        self.write("App/Example.swift", "struct Example {}\n")
        self.write(self.binding["file"], "final class ExampleTests: XCTestCase {\n"
                   "    func testKeepsData() {\n        XCTAssertTrue(true)\n    }\n}\n")
        self.save()
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=BDD fixture", "-c", "user.email=bdd@example.invalid",
                 "commit", "-qm", "baseline behavior")
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return bdd.git(self.root, *args)

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def save(self):
        self.write("Behaviors/data.json", json.dumps({"feature": "Data", "scenarios": [self.scenario]}))

    def change_test(self):
        path = self.root / self.binding["file"]
        path.write_text(path.read_text().replace("XCTAssertTrue(true)", "XCTAssertEqual(reopened.title, original.title)"))

    def test_behavior_change_requires_scenario_and_changed_bound_method(self):
        # Given a committed behavior and executable scenario, when its behavior changes,
        # then neither code alone nor prose alone satisfies the development contract.
        self.write("App/Example.swift", "struct Example { let title: String }\n")
        with self.assertRaisesRegex(bdd.ContractError, "add/update"):
            bdd.check(self.root, self.base)
        self.scenario["then"] = "the new title and data remain readable"
        self.save()
        with self.assertRaisesRegex(bdd.ContractError, "bound regression test"):
            bdd.check(self.root, self.base)
        self.change_test()
        self.assertEqual(len(bdd.check(self.root, self.base)), 1)

    def test_binding_must_exist_in_the_declared_class(self):
        self.write(self.binding["file"], "final class OtherTests: XCTestCase {\n"
                   "    func testKeepsData() {}\n}\n")
        with self.assertRaisesRegex(bdd.ContractError, "Missing test method"):
            bdd.check(self.root)

    def test_zero_tests_skips_and_partial_runs_are_not_passes(self):
        selectors = ["ExampleTests/testKeepsData"]
        for output in ("Executed 0 tests", "Test Case 'ExampleTests.testKeepsData' skipped (0.1 seconds).",
                       "Test Case 'OtherTests.testKeepsData' passed (0.1 seconds)."):
            with self.subTest(output=output), self.assertRaises(bdd.ContractError):
                bdd.require_executed(output, "core", selectors)
        bdd.require_executed("Test Case '-[Module.ExampleTests testKeepsData]' passed (0.1 seconds).", "core", selectors)
        bdd.require_executed("Test Case 'ExampleTests.testKeepsData' passed (0.1 seconds).", "core", selectors)
        for output in ("Ran 0 tests in 0s\nOK", "Ran 1 test in 0s\nOK (skipped=1)", "OK"):
            with self.subTest(output=output), self.assertRaises(bdd.ContractError):
                bdd.require_executed(output, "tooling", selectors)
        bdd.require_executed("testKeepsData (__main__.ExampleTests.testKeepsData) ... ok\nRan 1 test in 0.1s\nOK", "tooling", selectors)
        with self.assertRaises(bdd.ContractError):
            bdd.require_executed("testOther (__main__.OtherTests.testOther) ... ok\nRan 1 test in 0.1s\nOK", "tooling", selectors)

    def test_python_versions_report_both_supported_verbose_selector_formats(self):
        selector = ["ExampleTests/testKeepsData"]
        for output in ("testKeepsData (__main__.ExampleTests) ... ok",
                       "testKeepsData (__main__.ExampleTests.testKeepsData) ... ok"):
            with self.subTest(output=output):
                bdd.require_executed(output, "tooling", selector)

    def test_changes_outside_bound_method_do_not_satisfy_the_gate(self):
        self.write("App/Example.swift", "struct Example { let title: String }\n")
        self.scenario["then"] += " after relaunch"
        self.save()
        path = self.root / self.binding["file"]
        path.write_text("// Changed file, unchanged test\n" + path.read_text())
        with self.assertRaisesRegex(bdd.ContractError, "bound regression test"):
            bdd.check(self.root, self.base)

    def test_comment_formatting_and_trailing_helpers_are_not_test_changes(self):
        self.write("App/Example.swift", "struct Example { let title: String }\n")
        self.scenario["then"] += " after relaunch"
        self.save()
        path = self.root / self.binding["file"]
        original = path.read_text()
        variants = [original.replace("XCTAssertTrue", "// new comment\n        XCTAssertTrue"),
                    original.replace("XCTAssertTrue", "  XCTAssertTrue"),
                    original + "\nprivate func unrelatedHelper() { print(42) }\n"]
        for value in variants:
            with self.subTest(value=value):
                path.write_text(value)
                with self.assertRaisesRegex(bdd.ContractError, "bound regression test"):
                    bdd.check(self.root, self.base)

    def test_swift_literal_changes_are_preserved_but_nested_comments_are_ignored(self):
        self.assertEqual(bdd.swift_tokens('foo(/* outer /* nested */ end */ "https://a")'),
                         bdd.swift_tokens('foo("https://a")'))
        self.assertNotEqual(bdd.swift_tokens('foo("a b")'), bdd.swift_tokens('foo("ab")'))
        self.assertNotEqual(bdd.swift_tokens('foo(#"// a"#)'), bdd.swift_tokens('foo(#"// b"#)'))
        self.assertNotEqual(bdd.swift_tokens('foo("""\na\n""")'), bdd.swift_tokens('foo("""\nb\n""")'))

    def test_new_and_deleted_behavior_paths_are_checked(self):
        self.write("App/New.swift", "struct New {}")
        with self.assertRaisesRegex(bdd.ContractError, "add/update"):
            bdd.check(self.root, self.base)
        (self.root / "App/New.swift").unlink()
        (self.root / "App/Example.swift").unlink()
        with self.assertRaisesRegex(bdd.ContractError, "add/update"):
            bdd.check(self.root, self.base)

    def test_unmapped_behavior_files_fail(self):
        self.write("Watch/Recorder.swift", "struct Recorder {}")
        self.git("add", "Watch/Recorder.swift")
        with self.assertRaisesRegex(bdd.ContractError, "no scenario"):
            bdd.check(self.root)

    def test_new_unknown_code_root_fails_without_a_scenario(self):
        self.write("FuturePlatform/Recorder.swift", "struct Recorder {}")
        with self.assertRaisesRegex(bdd.ContractError, "no scenario"):
            bdd.check(self.root)

    def test_documentation_only_change_needs_no_binary_test(self):
        self.write("docs/example.md", "Describe the existing behavior.")
        self.assertEqual(len(bdd.check(self.root, self.base)), 1)

    def test_blank_steps_duplicate_ids_and_unscoped_patterns_fail(self):
        for field, value in (("given", " "), ("when", ""), ("then", ""), ("covers", ["*"]),
                             ("covers", ["../App/*"]), ("covers", ["/App/*"]), ("bindings", [])):
            with self.subTest(field=field, value=value):
                saved = copy.deepcopy(self.scenario)
                self.scenario[field] = value
                self.save()
                with self.assertRaises(bdd.ContractError):
                    bdd.check(self.root)
                self.scenario = saved
        self.save()
        self.write("Behaviors/duplicate.json", (self.root / "Behaviors/data.json").read_text())
        with self.assertRaisesRegex(bdd.ContractError, "duplicate"):
            bdd.check(self.root)

    def test_manual_acceptance_needs_reason_steps_and_automated_binding(self):
        self.scenario["manual"] = {"reason": "Real paired devices are required", "steps": ["Record, reconnect and play"]}
        self.save()
        self.assertEqual(len(bdd.check(self.root)), 1)
        self.scenario["manual"]["steps"] = []
        self.save()
        with self.assertRaisesRegex(bdd.ContractError, "concrete steps"):
            bdd.check(self.root)

    def test_suite_must_match_test_path(self):
        self.scenario["bindings"][0]["suite"] = "ios-unit"
        self.save()
        with self.assertRaisesRegex(bdd.ContractError, "invalid suite or test path"):
            bdd.check(self.root)

    def test_python_binding_uses_class_and_method(self):
        self.write("scripts/test-example.py", "import unittest\nclass ToolTests(unittest.TestCase):\n"
                   "    def test_rejects_export(self):\n        self.assertTrue(True)\n")
        binding = {"suite": "tooling", "file": "scripts/test-example.py", "test": "ToolTests/test_rejects_export"}
        self.assertIn("test_rejects_export", bdd.binding_body(self.root, binding))
        binding["test"] = "OtherTests/test_rejects_export"
        with self.assertRaises(bdd.ContractError):
            bdd.binding_body(self.root, binding)

    def test_native_commands_select_exact_methods_and_dedicated_simulator(self):
        commands = bdd.commands([self.scenario], "core", "")
        self.assertEqual(commands[0][:3], ["swift", "test", "--filter"])
        self.assertIn("testKeepsData", commands[0][3])
        with self.assertRaisesRegex(bdd.ContractError, "zero-test"):
            bdd.commands([self.scenario], "ios-ui", "")
        self.binding.update(suite="ios-ui", file="iOSTests/ExampleTests.swift")
        with self.assertRaisesRegex(bdd.ContractError, "dedicated simulator"):
            bdd.commands([self.scenario], "ios-ui", "")
        cmd = bdd.commands([self.scenario], "ios-ui", "platform=iOS Simulator,id=dedicated")[-1]
        self.assertIn("-only-testing:ListenToMeIOSUITests/ExampleTests/testKeepsData", cmd)
        self.assertIn("platform=iOS Simulator,id=dedicated", cmd)
        self.binding.update(suite="ios-unit", file="iOSUnitTests/ExampleTests.swift")
        cmd = bdd.commands([self.scenario], "ios-unit", "platform=iOS Simulator,id=dedicated")[-1]
        self.assertIn("-only-testing:ListenToMeIOSUnitTests/ExampleTests/testKeepsData", cmd)


if __name__ == "__main__":
    unittest.main()
