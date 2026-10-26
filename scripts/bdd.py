#!/usr/bin/env python3
"""Validate behavior contracts and run their native XCTest/unittest bindings.

Specs are data, not a second implementation of the app. A binding identifies an
existing test method; its assertions remain in the platform's normal test suite.
"""
import argparse
import ast
import fnmatch
import json
import hashlib
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
SUITES = {
    "core": "Tests/ListenToMeCoreTests/",
    "ios-unit": "iOSUnitTests/",
    "ios-ui": "iOSTests/",
    "mac-unit": "macOSTests/",
    "watch-unit": "WatchUnitTests/",
    "watch-ui": "WatchUITests/",
    "tooling": "scripts/",
}
# Include resources, build/distribution settings and automation, not just Swift.
BEHAVIOR_ROOTS = ("App/", "Sources/", "SharedPlatform/", "iOS/", "iOSShared/",
                  "Watch/", "ShareExtension/", "Config/", "scripts/", ".github/workflows/")
BEHAVIOR_FILES = {"Makefile", "Package.swift", "project.yml", "watch-embed.yml",
                  "signing.local.mk.example", ".swiftlint.yml", ".gitignore"}
TEST_ROOTS = ("Tests/", "iOSUnitTests/", "iOSTests/", "macOSTests/", "WatchUnitTests/", "WatchUITests/")


class ContractError(ValueError):
    pass


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.PIPE).decode()


def safe_path(value):
    return (isinstance(value, str) and bool(value) and not value.startswith("/")
            and ".." not in value.split("/") and "\\" not in value)


def is_behavior(path):
    if path.startswith((*TEST_ROOTS, "docs/", "Behaviors/", "metadata/", ".agents/")):
        return False
    return (path in BEHAVIOR_FILES or path.startswith(BEHAVIOR_ROOTS)
            or path.endswith((".swift", ".py", ".sh", ".yml", ".yaml", ".mk", ".plist", ".entitlements")))


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def swift_tokens(source):
    """Ignore formatting/comments while retaining literal contents and token boundaries."""
    tokens = []
    pos = 0
    while pos < len(source):
        if source[pos].isspace():
            pos += 1
        elif source.startswith("//", pos):
            end = source.find("\n", pos)
            pos = len(source) if end < 0 else end
        elif source.startswith("/*", pos):
            depth = 1
            pos += 2
            while pos < len(source) and depth:
                if source.startswith("/*", pos):
                    depth += 1
                    pos += 2
                elif source.startswith("*/", pos):
                    depth -= 1
                    pos += 2
                else:
                    pos += 1
        else:
            literal = re.match(r'(\#*)("""|")', source[pos:])
            if literal:
                start = pos
                hashes, quote = literal.groups()
                pos += len(literal[0])
                closing = quote + hashes
                while pos < len(source):
                    if source.startswith("\\" + hashes, pos):
                        pos += 2 + len(hashes)
                    elif source.startswith(closing, pos):
                        pos += len(closing)
                        break
                    else:
                        pos += 1
                tokens.append(source[start:pos])
            else:
                token = re.match(r"\w+|[^\w\s]", source[pos:])[0]
                tokens.append(token)
                pos += len(token)
    return tokens


def binding_body(root, binding, revision=None):
    """Locate the declared class AND method; a same-named helper is insufficient."""
    path, selector = binding["file"], binding["test"]
    try:
        source = git(root, "show", f"{revision}:{path}") if revision else (root / path).read_text()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ContractError(f"Missing bound test file: {path}") from exc
    cls, method = selector.split("/")
    if binding["suite"] == "tooling":
        try:
            tree = ast.parse(source)
        except SyntaxError as exc:
            raise ContractError(f"Invalid Python test: {path}") from exc
        for node in tree.body:
            if isinstance(node, ast.ClassDef) and node.name == cls:
                for member in node.body:
                    if isinstance(member, (ast.FunctionDef, ast.AsyncFunctionDef)) and member.name == method:
                        return ast.dump(member, include_attributes=False)
    else:
        # XCTest files use top-level test classes and four-space method declarations.
        # Stop at the next class and method: a match elsewhere in the file is not a binding.
        classes = list(re.finditer(r"^(?:final )?class (\w+)\b", source, re.M))
        for index, found in enumerate(classes):
            if found[1] != cls:
                continue
            end = classes[index + 1].start() if index + 1 < len(classes) else len(source)
            body = source[found.end():end]
            methods = list(re.finditer(r"^    (?:private )?func (\w+)\(", body, re.M))
            for pos, declaration in enumerate(methods):
                if declaration[1] == method:
                    stop = methods[pos + 1].start() if pos + 1 < len(methods) else len(body)
                    candidate = body[declaration.start():stop]
                    # Native test methods follow the enforced four-space SwiftLint style.
                    # The method's own closing brace excludes trailing helpers/other classes.
                    closing = re.search(r"^    }[ \t]*(?://[^\n]*)?$", candidate, re.M)
                    if not closing:
                        raise ContractError(f"Bound Swift test needs a four-space method closing brace: {path}:{selector}")
                    return swift_tokens(candidate[:closing.end()])
    raise ContractError(f"Missing test method: {path}:{selector}")


def load(root):
    scenarios = []
    seen = set()
    files = sorted((root / "Behaviors").glob("*.json"))
    if not files:
        raise ContractError("No behavior specifications found")
    for path in files:
        try:
            feature = json.loads(path.read_text())
        except (ValueError, OSError) as exc:
            raise ContractError(f"Invalid spec: {path.name}") from exc
        if set(feature) != {"feature", "scenarios"} or not feature["feature"] or not feature["scenarios"]:
            raise ContractError(f"Expected feature and nonempty scenarios: {path.name}")
        for scenario in feature["scenarios"]:
            required = {"id", "name", "given", "when", "then", "covers", "bindings"}
            if set(scenario) - required - {"manual"} or not required <= set(scenario):
                raise ContractError(f"Invalid scenario fields: {path.name}")
            identifier = scenario["id"]
            if not isinstance(identifier, str) or not re.fullmatch(r"[A-Z]+-\d{3}", identifier) or identifier in seen:
                raise ContractError(f"Invalid or duplicate scenario ID: {identifier}")
            seen.add(identifier)
            for key in ("name", "given", "when", "then"):
                if not isinstance(scenario[key], str) or not scenario[key].strip():
                    raise ContractError(f"{identifier}: empty {key}")
            patterns = scenario["covers"]
            if not isinstance(patterns, list) or not patterns or any(
                    not safe_path(p) or p in ("*", "**", "**/*") for p in patterns):
                raise ContractError(f"{identifier}: use repository-relative, scoped covers patterns")
            if not isinstance(scenario["bindings"], list) or not scenario["bindings"]:
                raise ContractError(f"{identifier}: an automated binding is required, including for manual acceptance")
            for binding in scenario["bindings"]:
                if set(binding) != {"suite", "file", "test"}:
                    raise ContractError(f"{identifier}: invalid binding fields")
                suite = binding["suite"]
                if suite not in SUITES or not safe_path(binding["file"]) or not binding["file"].startswith(SUITES[suite]):
                    raise ContractError(f"{identifier}: invalid suite or test path")
                if not isinstance(binding["test"], str) or not re.fullmatch(r"\w+/test\w+", binding["test"]):
                    raise ContractError(f"{identifier}: bind one class/testMethod, not a suite wildcard")
                binding_body(root, binding)
            if "manual" in scenario:
                manual = scenario["manual"]
                if (not isinstance(manual, dict) or set(manual) != {"reason", "steps"}
                        or not isinstance(manual["reason"], str) or not manual["reason"].strip()
                        or not isinstance(manual["steps"], list) or not manual["steps"]
                        or any(not isinstance(step, str) or not step.strip() for step in manual["steps"])):
                    raise ContractError(f"{identifier}: manual acceptance needs a reason and concrete steps")
            scenarios.append(scenario)
    return scenarios


def check(root, base=None):
    scenarios = load(root)
    tracked = git(root, "ls-files", "-z").split("\0")
    tracked += git(root, "ls-files", "--others", "--exclude-standard", "-z").split("\0")
    for path in tracked:
        if is_behavior(path) and not any(matches(path, s["covers"]) for s in scenarios):
            raise ContractError(f"Behavior file has no scenario: {path}")
    if base:
        ancestor = git(root, "merge-base", base, "HEAD").strip()
        changed = set(git(root, "diff", "--name-only", "--no-renames", ancestor, "--").splitlines())
        changed.update(git(root, "ls-files", "--others", "--exclude-standard").splitlines())
        old = {}
        for path in git(root, "ls-tree", "-r", "--name-only", ancestor, "--", "Behaviors/").splitlines():
            if path.endswith(".json"):
                for scenario in json.loads(git(root, "show", f"{ancestor}:{path}"))["scenarios"]:
                    old[scenario["id"]] = scenario
        updated = [s for s in scenarios if s != old.get(s["id"])]
        for path in sorted(changed):
            if not is_behavior(path):
                continue
            candidates = [s for s in updated if matches(path, s["covers"])]
            if not candidates:
                raise ContractError(f"{path}: add/update its Given/When/Then scenario before changing behavior")
            # A changed test FILE is insufficient: the bound test method must change.
            tested = False
            for scenario in candidates:
                for binding in scenario["bindings"]:
                    if binding["file"] not in changed:
                        continue
                    try:
                        prior = binding_body(root, binding, ancestor)
                    except ContractError:
                        prior = None
                    if binding_body(root, binding) != prior:
                        tested = True
            if not tested:
                raise ContractError(f"{path}: change/add a bound regression test method, not just a spec or test comment")
    return scenarios


def commands(scenarios, suite, destination):
    bindings = {(b["file"], b["test"]) for s in scenarios for b in s["bindings"] if b["suite"] == suite}
    if not bindings:
        raise ContractError(f"No bindings for {suite}; refusing a zero-test pass")
    if suite == "core":
        pattern = "|".join(re.escape(test) for _, test in sorted(bindings))
        return [["swift", "test", "--filter", pattern]]
    if suite == "tooling":
        by_file = {}
        for file, test in sorted(bindings):
            by_file.setdefault(file, []).append(test.replace("/", "."))
        return [[sys.executable, file, "-v", *tests] for file, tests in by_file.items()]
    profiles = {
        "ios-unit": ("ListenToMeIOS", "ListenToMeIOSUnitTests", ".build/ios"),
        "ios-ui": ("ListenToMeIOS", "ListenToMeIOSUITests", ".build/ios"),
        "mac-unit": ("ListenToMeMacTests", "ListenToMeMacUnitTests", ".build/mac-native-tests"),
        "watch-unit": ("ListenToMeWatchTests", "ListenToMeWatchUnitTests", ".build/watch-native-tests"),
        "watch-ui": ("ListenToMeWatchTests", "ListenToMeWatchUITests", ".build/watch-native-tests"),
    }
    if suite == "mac-unit":
        destination = destination or "platform=macOS"
    elif not destination:
        variable = "WATCH_DESTINATION" if suite.startswith("watch-") else "IOS_DESTINATION"
        raise ContractError(f"Native BDD execution requires {variable} for a dedicated simulator")
    if suite.startswith("watch-") and not re.fullmatch(r"platform=watchOS Simulator,id=[^,\s]+", destination):
        raise ContractError("Watch BDD execution requires a dedicated watchOS Simulator")
    if suite == "mac-unit" and "platform=macOS" not in destination:
        raise ContractError("Mac BDD execution requires a macOS destination")
    scheme, target, derived_data = profiles[suite]
    return [["make", "gen"], ["xcodebuild", "-project", "ListenToMe.xcodeproj", "-scheme", scheme,
             "-destination", destination, "-derivedDataPath", derived_data, "-configuration", "Debug",
             "-onlyUsePackageVersionsFromResolvedFile", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-",
             "-parallel-testing-enabled", "NO", *[f"-only-testing:{target}/{test}" for _, test in sorted(bindings)], "test"]]


def require_executed(output, suite, selectors):
    """A green process with zero tests, filtered-out methods or skips is not a BDD pass."""
    if suite == "tooling":
        for selector in selectors:
            cls, method = selector.split("/")
            pattern = rf"^{re.escape(method)} \((?:[\w.]+\.)?{re.escape(cls)}(?:\.{re.escape(method)})?\) \.\.\. ok$"
            if not re.search(pattern, output, re.M):
                raise ContractError(f"No observed passing execution for {selector}")
        return
    passed = [line for line in output.splitlines() if line.startswith("Test Case ") and " passed " in line]
    for selector in selectors:
        cls, method = selector.split("/")
        if not any(re.search(r"\b" + re.escape(cls) + r"\b", line)
                   and re.search(r"\b" + re.escape(method) + r"\b", line) for line in passed):
            raise ContractError(f"No observed passing execution for {selector}")


def run(root, scenarios, suite, destination):
    selectors = sorted({b["test"] for s in scenarios for b in s["bindings"] if b["suite"] == suite})
    output = []
    evidence = root / "dist" / "bdd"
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"suite": suite, "source": git(root, "rev-parse", "HEAD").strip(),
              "workingTree": git(root, "status", "--porcelain"),
              "startedAt": datetime.now(timezone.utc).isoformat(), "status": "running",
              "selectors": selectors, "commands": commands(scenarios, suite, destination)}
    inputs = {b["file"] for s in scenarios for b in s["bindings"] if b["suite"] == suite}
    inputs.update(str(p.relative_to(root)) for p in (root / "Behaviors").glob("*.json"))
    inputs.add("scripts/bdd.py")
    report["inputSHA256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sorted(inputs)}
    report_path = evidence / f"{suite}.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    try:
        with (evidence / f"{suite}.log").open("w") as log:
            for command in report["commands"]:
                with subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True) as process:
                    for line in process.stdout:
                        print(line, end="", flush=True)
                        output.append(line)
                        log.write(line)
                    if process.wait():
                        raise ContractError(f"Native test command failed: {command[0]}")
        require_executed("".join(output), suite, selectors)
        report["status"] = "passed"
    except Exception:
        report["status"] = "failed"
        raise
    finally:
        report["finishedAt"] = datetime.now(timezone.utc).isoformat()
        report_path.write_text(json.dumps(report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="check changed behavior and bound test methods against the merge base")
    parser.add_argument("--run", choices=SUITES)
    parser.add_argument("--destination", default="")
    parser.add_argument("--manual", action="store_true", help="list outstanding manual acceptance; does not mark it passed")
    parser.add_argument("--verify-log", nargs=2, metavar=("SUITE", "LOG"), help="verify bound passing selectors in a full native test log")
    args = parser.parse_args()
    try:
        scenarios = check(ROOT, args.base)
        print(f"BDD contracts: {len(scenarios)} scenarios, all bindings and behavior paths valid", flush=True)
        if args.manual:
            for s in scenarios:
                if "manual" in s:
                    print(f"{s['id']} {s['name']} — MANUAL ACCEPTANCE REQUIRED: {s['manual']['reason']}")
                    for step in s["manual"]["steps"]:
                        print(f"  - {step}")
        if args.run:
            run(ROOT, scenarios, args.run, args.destination)
        if args.verify_log:
            suite, path = args.verify_log
            if suite not in SUITES:
                raise ContractError(f"Unknown suite: {suite}")
            selectors = sorted({b["test"] for s in scenarios for b in s["bindings"] if b["suite"] == suite})
            if not selectors:
                raise ContractError("No bindings; refusing a zero-test pass")
            require_executed(Path(path).read_text(), suite, selectors)
            print(f"Observed passing execution of all {len(selectors)} {suite} bindings")
    except (ContractError, subprocess.CalledProcessError) as exc:
        print(f"BDD failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
