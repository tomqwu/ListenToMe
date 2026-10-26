# Behavior-driven development

ListenToMe develops behavior from examples across the whole repository: Mac, iPhone/iPad, Duo,
Watch, shared services, imports, data ownership, privacy and build/release tooling. The rules live
in [AGENTS.md](../AGENTS.md); the executable examples live in [Behaviors](../Behaviors/).

Each JSON feature groups observable scenarios with stable IDs, a name, `given`, `when`, `then`,
scoped repository-relative `covers` patterns and `bindings`. This is a native-test adapter: Swift
XCTest and Python unittest execute the assertions. JSON carries the behavior contract and exact
test selector, so there is no duplicate Cucumber implementation or dependency to keep in sync.

## Working an issue

Finish the current change through validation, review, CI and merge before opening another feature
PR. Future work stays in GitHub Issues. Work down existing drafts sequentially and consolidate
multiple drafts for the same issue without deleting their source or acceptance evidence.

1. Understand the issue and choose concrete examples before writing production code. State the
   starting condition, user action/event and observable outcome. Add edge cases, failures, data
   erasure, cancellation and off-device consent as the behavior requires.
2. Add/update a scenario in the appropriate feature. Narrow `covers` to the affected files or
   domain; baseline platform globs route ownership and do not prove exhaustive behavior coverage.
   Bind it to a specific `Class/testMethod` and source file in `core`, `ios-unit`, `ios-ui`,
   `mac-unit`, `watch-unit`, `watch-ui` or `tooling`. A scenario may need multiple bindings across platforms.
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

## Speaker model accuracy is behavior

The #310 regression exposed a missing boundary: fake diarizer IDs proved label mapping, not that
actual voices were separated. `SHARED-001` now explicitly describes already-diarized groups.
`SPEAKER-001`–`SPEAKER-016` bind actual model inference, streaming lifecycle, timeline authority and
native controls separately. The Mac native suites call the same `productionDiarizer()` selected on
physical iPhone/iPad; the unit/UI host substitutions cannot satisfy these quality contracts.

`make mac-test` and `make validate-local` run the checked-in synthetic stock-voice WAV fixtures
through real CoreML inference. First preparation may download public model weights from Hugging Face;
subsequent runs use the excluded-from-backup cache. No microphone, private conversation, audible
playback or cloud inference is used. Assert each known turn's correct voice identity, single-voice
controls, a second voice pair, successive overlapping windows, returning voices and edited names
through silence, bounded long-run state, final flush, cancellation and cleanup. Merely finding two
raw speaker IDs is insufficient: swapped identities must fail. These fixtures are regression gates,
not proof of the original private recording, physical-device performance or universal accuracy.
The separate three-person diagnostic still merges two voices and is documented as a known limitation.
Native property tests also need reachable user controls: the opt-out contract includes a rendered
Settings-switch test while recording, rather than treating a direct property assignment as UI proof.
See [speaker evidence and acceptance](speaker-identification.md).

## Device compatibility is behavior

For each affected feature, specify its supported and unavailable states before implementation.
Do not infer support from the OS version or Apple Intelligence eligibility alone: local speech,
summary AI, model readiness, microphone access and paired-device connectivity are separate capabilities.
This applies to iPhone/iPad (including Duo), Apple Watch and Mac.

Use the shared `DEVICE-001`–`DEVICE-004` readiness contract together with concrete platform scenarios:

- Given supported hardware and language, when listening starts, then current microphone speech is
  transcribed even if summary AI is unavailable. An available local dictation engine is a valid fallback.
- Given an unsupported engine/language, when the screen opens, then Start is disabled and the reason
  and supported alternatives are visible before a tap; no microphone request or download starts.
- Given denied permission or missing setup, when the feature is shown, then execution is blocked
  with an applicable recovery action. Unknown permission may still be requested by an explicit tap.
- Given unavailable Apple Intelligence, when choosing AI, then it cannot be selected as a working
  provider; saved choices remain intact, with explicit alternatives and no automatic cloud routing.
- Given changed language, permissions, model readiness or connectivity, when availability refreshes,
  then obsolete asynchronous checks cannot re-enable an unavailable action. Stop remains usable.
- Given an unreachable or incompatible paired iPhone, when the Watch remote appears, then Start is
  unavailable with a recovery reason; the Watch's independent offline recording remains separate.

Bind platform adapters and control behavior to native tests. Generic readiness booleans alone do
not establish native integration. Record coverage gaps explicitly and retain physical-device,
rendered UI and real Mac OTHERS acceptance where applicable; a simulator pass cannot replace them.

## Commands and enforcement

```sh
make bdd-check                         # change-aware check against origin/main
make bdd-check BDD_BASE=origin/parent   # actual base for a stacked PR
make bdd-test BDD_SUITE=core
make bdd-test BDD_SUITE=tooling
make bdd-test BDD_SUITE=ios-unit IOS_DESTINATION='platform=iOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=ios-ui IOS_DESTINATION='platform=iOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=mac-unit
make bdd-test BDD_SUITE=watch-unit WATCH_DESTINATION='platform=watchOS Simulator,id=<dedicated-UUID>'
make bdd-test BDD_SUITE=watch-ui WATCH_DESTINATION='platform=watchOS Simulator,id=<dedicated-UUID>'
make bdd-manual                        # lists required acceptance; does not mark it passed
python3 scripts/test-bdd.py            # offline gate regression tests
```

Create a fresh dedicated simulator for iOS tests and delete it after preserving evidence. These
commands never reset a shared simulator, alter macOS permissions or authorize a production release.
Native BDD commands select exact methods. Full local validation runs the iOS unit/UI, headless
native Mac adapter/control and Watch unit/UI suites. Supply dedicated `IOS_DESTINATION` and
`WATCH_DESTINATION` simulator IDs; Watch commands refuse a missing ID or wrong platform.
`make ios-test`, `make mac-test` and `make watch-test` preserve native output and verify every bound
selector passed, so a skipped or filtered-out scenario cannot satisfy the gate. Mac native tests
compile production framework adapters and menu controllers without opening the app or user data.
Watch tests run the actual app/client/recorder on watchOS Simulator; they do not establish real
paired transfer or microphone acceptance.

The checker rejects missing/duplicate IDs, empty Given/When/Then steps, unscoped patterns, missing
test files/methods, mismatched suites and behavior files without a scenario. Its change-aware gate
requires an updated scenario covering each changed behavior path and a new/changed bound test
method. A changed file header or unrelated test in the same file does not satisfy it. New unknown
code roots fail until they are assigned a scoped contract. Docs, release copy and test-only Swift
changes do not demand an unrelated production scenario. Python test helpers remain tooling.

The required **ListenToMeCore tests + coverage** CI job checks PR changes against their actual base,
fetches the current target branch for PRs (including stacked PR targets), tests the gate, executes
bound core/tooling scenarios and retains the 95% core coverage floor. A push compares against its
event’s before commit. Failed target fetches fail the check; they never fall back to a stale PR base.
The existing macOS and iOS build checks remain required. Main also requires branches to be up to
date before merge, so older drafts must incorporate the current BDD workflow. The three required
check names are unchanged; the live Main ruleset's strict up-to-date requirement was enabled and
read back on October 25, 2026.
Local `pre-push` and `make validate-local` include the structural/change-aware check. The latter also
tests the gate, checks observed iOS, Mac and Watch binding results and retains all native, helper and real model
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
