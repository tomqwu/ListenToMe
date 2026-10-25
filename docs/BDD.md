# Behavior-driven development

ListenToMe develops behavior from examples across the whole repository: Mac, iPhone/iPad, Duo,
Watch, shared services, imports, data ownership, privacy and build/release tooling. The rules live
in [AGENTS.md](../AGENTS.md); the executable examples live in [Behaviors](../Behaviors/).

Each JSON feature groups observable scenarios with stable IDs, a name, `given`, `when`, `then`,
scoped repository-relative `covers` patterns and `bindings`. This is a native-test adapter: Swift
XCTest and Python unittest execute the assertions. JSON carries the behavior contract and exact
test selector, so there is no duplicate Cucumber implementation or dependency to keep in sync.

## Working an issue

1. Understand the issue and choose concrete examples before writing production code. State the
   starting condition, user action/event and observable outcome. Add edge cases, failures, data
   erasure, cancellation and off-device consent as the behavior requires.
2. Add/update a scenario in the appropriate feature. Narrow `covers` to the affected files or
   domain; baseline platform globs route ownership and do not prove exhaustive behavior coverage.
   Bind it to a specific `Class/testMethod` and source file in `core`, `ios-unit`, `ios-ui` or
   `tooling`. A scenario may need multiple bindings across platforms.
3. Write the reproducing native test and run it **before** implementation. Record the expected
   failure, implement the behavior and record the passing run. Refactor under the same tests.
   A failing compile caused by a typo is not evidence that a regression was reproduced.
4. Run `make bdd-check`, affected suites and the existing `make validate-local` gates. Exercise
   rendered UI and actual audio/device paths when required. Preserve source, commands and results.
5. Update all affected docs and platform release notes, request independent correctness review,
   include scenario IDs and actual red/green evidence in the PR template, then merge with the three
   required CI checks green. Publication remains a separate authorized release train.

Example from the retained-Watch-audio contract (`WATCH-001`):

```json
{
  "id": "WATCH-001",
  "name": "Retain Watch audio only with consent",
  "given": "a Watch recording arrives on iPhone",
  "when": "transcription finishes with Save audio recordings on or off",
  "then": "opt-in retains playable audio and opt-out removes the inbox copy",
  "covers": ["iOS/MobileSession+Watch*"],
  "bindings": [{
    "suite": "ios-unit",
    "file": "iOSUnitTests/MobileWatchAudioTests.swift",
    "test": "MobileWatchAudioTests/testOptInRetainsPlayableAudioAndOffDeletesOnlyInboxCopy"
  }]
}
```

The real catalog also records paired-device acceptance steps. Simulator tests cannot prove
disconnected Watch transfer, real microphone/system capture or physical-device readiness.

## Commands and enforcement

```sh
make bdd-check                         # change-aware check against origin/main
make bdd-check BDD_BASE=origin/parent   # actual base for a stacked PR
make bdd-test BDD_SUITE=core
make bdd-test BDD_SUITE=tooling
make bdd-test BDD_SUITE=ios-unit IOS_DESTINATION='platform=iOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=ios-ui IOS_DESTINATION='platform=iOS Simulator,id=<dedicated-UUID>'
make bdd-manual                        # lists required acceptance; does not mark it passed
python3 scripts/test-bdd.py            # offline gate regression tests
```

Create a fresh dedicated simulator for iOS tests and delete it after preserving evidence. These
commands never reset a shared simulator, alter macOS permissions or authorize a production release.
The iOS BDD commands select exact methods; the full iOS suite still runs in `make validate-local`.
`make ios-test` preserves its native output and verifies every bound iOS unit/UI selector passed,
so a skipped or filtered-out bound scenario cannot satisfy the full local gate.

The checker rejects missing/duplicate IDs, empty Given/When/Then steps, unscoped patterns, missing
test files/methods, mismatched suites and behavior files without a scenario. Its change-aware gate
requires an updated scenario covering each changed behavior path and a new/changed bound test
method. A changed file header or unrelated test in the same file does not satisfy it. New unknown
code roots fail until they are assigned a scoped contract. Docs, release copy and test-only Swift
changes do not demand an unrelated production scenario. Python test helpers remain tooling.

The required **ListenToMeCore tests + coverage** CI job checks PR changes against their actual base,
tests the gate, executes bound core/tooling scenarios and retains the 95% core coverage floor.
The existing macOS and iOS build checks remain required. No additional branch-rule setup is needed.
Local `pre-push` and `make validate-local` include the structural/change-aware check. The latter also
tests the gate, checks observed iOS binding results and retains all native, helper and real model
contracts. Python execution checks exact verbose selectors rather than accepting aggregate counts.

BDD runs save source, working-tree state, input hashes, commands, selectors, logs and results in
gitignored `dist/bdd/`. A successful native process with zero tests, missing passing selectors or
skipped bound tests fails the BDD runner. Running the checker alone does not execute scenarios.
Manual acceptance always needs separate source-matched evidence; a catalog entry is not a pass.

## Adopting existing work honestly

The initial catalog binds existing representative regression tests across the repository. These
are **baseline adoption**, with no invented historical red evidence and no claim of exhaustive
legacy behavior coverage. Existing unit/integration tests remain valuable and stay in normal
suites; they do not need cosmetic Given/When/Then renaming. As each backlog issue or older branch is
integrated, add/update the relevant examples and record a real regression reproduction for its
behavior changes. Do not silently exempt old branches from the change-aware gate.

Automation checks structure and observed execution, not intent, causality or test quality. An
independent reviewer must compare each scenario with its assertions and verify red/green evidence.
Do not satisfy a behavior change with an unrelated test or weaken coverage/manual acceptance gates.
