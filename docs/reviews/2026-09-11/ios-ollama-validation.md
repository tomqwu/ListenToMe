# iOS Ollama Cloud — 1.1.0 (3)

## Behavior

Settings adds an opt-in Ollama Cloud summary provider, per-device Keychain storage, API catalog
refresh, a model picker and a synthetic connection test. The actual summary action streams the
selected cloud model, preserves the previous completed summary on failure/cancellation, and saves
the new result only after a complete response. Apple Intelligence remains the default.

Catalog IDs come from GET https://ollama.com/api/tags; no model versions are hardcoded. Recent
family/variant suggestions use API modification timestamps. The live catalog checked on September
11 includes DeepSeek V4.1 Flash, V4 Pro, GLM 5.3/5.3 Flash, Qwen 3.5 and Kimi K3. No Qwen Flash or
Kimi Flash entry was returned; future API entries will appear on refresh. Cloud usage does not
require downloading weights with /api/pull.

## Validation

- Shared suite: 244 tests, two opt-in network skips, zero failures; core line coverage 96.76%.
- Catalog tests cover exact model IDs, authentication headers, malformed/error responses,
  deduplication, missing variants, date offsets and version ordering.
- App-hosted iOS tests cover real Keychain create/update/read/delete and settings persistence.
- iPhone and iPad simulators: UI and app-hosted tests pass, credential-dependent live test skipped.
- The opt-in public catalog check passes through the production Swift API client against ollama.com.
- UI tests cover key save/relaunch/removal, notes/history/relaunch, and simulator recording errors.
- SwiftLint: no errors. macOS Debug build and signed iOS Release archive pass.
- Simulator build commands now sign ad hoc to exercise Keychain access. An explicit app Keychain
  access group is included in the device archive as well.

The opt-in testLiveCloudCatalogConnectionAndSummary consumes a locally staged
Library/Application Support/OllamaLiveTestKey file in the test app's data container and immediately
deletes it. It uses the actual app API/catalog/summary path with synthetic notes, verifies persisted
output and invalid-key failure preservation, then restores the prior Keychain/settings. No key is
committed, logged, packaged or provided to hosted CI.

At source review preparation, that live test is waiting for OS Keychain authorization. Do not count
the skipped hosted test as a real cloud pass. Local execution/export logs are retained in
`dist/ios-1.1.0-evidence`. Physical-device acceptance of this new cloud feature remains pending;
this is a TestFlight beta, not a claim of production readiness.
