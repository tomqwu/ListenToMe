# OpenAI-compatible endpoint support — Design

> Closes issue #52. Status: design approved 2026-06-30.

## Goal

Let a user point ListenToMe at any **OpenAI-compatible `/v1/chat/completions` server** — LM Studio,
OpenRouter, vLLM, DeepSeek, etc. — as an alternative AI backend to Ollama. Still bring-your-own-model,
still fully private when the endpoint is local. This closes the gap where Hyprnote/Anarlog already lets
users target any OpenAI-compatible API.

## Background (current state)

- **`LLMProvider`** (`Sources/ListenToMeCore/LLMProvider.swift`) is already provider-agnostic:
  `func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>` + `var id: String`.
  `LLMRequest` is `(system: String, messages: [ChatMessage])` (`Prompt.swift`).
- **`DeepSeekProvider`** (`Sources/ListenToMeCore/DeepSeekProvider.swift`) is **already a complete,
  fully-tested OpenAI-compatible SSE provider** — correct request body (`{model, messages, stream:true}`,
  system prepended), correct SSE parse (`choices[].delta.content`, `[DONE]` terminator), Bearer auth,
  injectable `baseURL`/`URLSession`. It is **dormant** — referenced nowhere in `App/` or the rest of
  `Sources/` except its own tests. Its only DeepSeek-specific traits: path `chat/completions`,
  `id = "deepseek"`, **required** `apiKey: String`, and a `https://api.deepseek.com` default base.
- **Providers are built per role/pane** by a factory closure
  `makeProvider: @Sendable (String) -> any LLMProvider` held on `MeetingSession`. In
  `App/MeetingView.swift` (~lines 155-157) it is hardwired to
  `OllamaProvider(model:, baseURL: ollamaBaseURL(), apiKey: ollamaKey())`. `MeetingSession.setModel`
  rebuilds a role's provider via the same closure.
- **Config surface is Ollama-only**: `ProviderSettings` (`App/SettingsView.swift`) has no base-URL or
  provider-type field; the only "provider selection" is a binary in `ollamaBaseURL()` —
  `https://ollama.com` when a Keychain `"ollama"` key exists, else `http://localhost:11434`.
- **Model discovery is Ollama-only**: `App/OllamaModels.swift` hits `api/tags` + `api/show`. No
  `/v1/models` path exists.
- **Privacy footer**: `CommandCenterFooter(cloudActive:)` is fed `ollamaKey() != nil`.

## Decision: global backend toggle

A single global "AI backend" choice (Ollama *or* OpenAI-compatible), **not** per-pane providers. Per-pane
**model** choice is preserved within the chosen backend. Per-pane backends and named multi-endpoint lists
are explicitly out of scope (YAGNI) — see Non-goals.

## Architecture

### 1. Engine: generalize the dormant provider

Rename `DeepSeekProvider` → **`OpenAICompatibleProvider`** (`git mv`
`Sources/ListenToMeCore/DeepSeekProvider.swift` → `OpenAICompatibleProvider.swift`):

- `public let id: String` — configurable, default `"openai-compatible"` (was hardcoded `"deepseek"`).
- `apiKey: String?` — **optional** (Bearer header sent only when non-empty), copying
  `OllamaProvider`'s pattern (LM Studio / vLLM commonly need no key). Was required `String`.
- `baseURL: URL` — **required, no default** (always supplied from settings). Drop the
  `https://api.deepseek.com` default.
- SSE parser, request body, and streaming stay byte-for-byte (already correct). Rename the parser enum
  `DeepSeekParser` → `OpenAICompatibleParser`.
- Error domain string `"DeepSeek"` → `"OpenAICompatible"`.

`DeepSeekProviderTests.swift` → `OpenAICompatibleProviderTests.swift`: same assertions, plus the
**new optional-key behavior** — Authorization header present when key set, **omitted when key nil/empty**
(mirroring `OllamaLiveTransportTests`).

**Base-URL convention:** the user enters the full OpenAI base **including `/v1`** (e.g.
`http://localhost:1234/v1`, `https://openrouter.ai/api/v1`). The provider appends `chat/completions`
(it already does `baseURL.appendingPathComponent("chat/completions")`), and discovery appends `models`.
This matches how every OpenAI client configures `base_url`.

### 2. Engine: settings keys

Add to `ProviderSettings` (`App/SettingsView.swift`):
- `aiBackend: String` — `"ollama"` (default) | `"openai"`. UserDefaults key `"aiBackend"`.
- `openAIBaseURL: String` — UserDefaults key `"openAIBaseURL"`, default `""`.
The OpenAI key is stored in Keychain under a **new account `"openai-compatible"`** (the existing
`"ollama"` account is untouched). Add `MeetingView.openAIKey()` mirroring `ollamaKey()`.

### 3. Engine/App: factory dispatch

`MeetingView.makeProvider(model)` branches on `ProviderSettings.aiBackend`:
- `"openai"` → `OpenAICompatibleProvider(model: model, baseURL: <openAIBaseURL>, apiKey: openAIKey())`
  (guard a malformed/empty base URL → fall back to Ollama path or surface the existing `startError`;
  see Error handling).
- otherwise → today's `OllamaProvider(...)`.

Because `makeProvider` reads settings live and `reloadAndHealModels()` already rebuilds every role's
provider on Settings dismiss, switching backend in Settings takes effect without restart (verified in the
plan).

### 4. App: model discovery

The HTTP fetch lives in the App target; the **JSON parse lives in Core so it is unit-testable**
(the App target has no test bundle):
```swift
// Sources/ListenToMeCore/OpenAIModelParsing.swift  (pure, testable)
public enum OpenAIModelParsing {
    /// Parse an OpenAI `/v1/models` response body → model ids. Empty on garbage/empty.
    public static func ids(from data: Data) -> [String]   // reads { "data": [ { "id": ... } ] }
}

// App/OpenAIModels.swift  (HTTP only)
enum OpenAIModels {
    /// GET {baseURL}/models → OpenAIModelParsing.ids(from:). No capability probe (/v1 exposes none).
    static func installed(baseURL: URL, apiKey: String?) async -> [String]
}
```
`reloadModels()` / `reloadAndHealModels()` branch on `aiBackend`: OpenAI → `OpenAIModels.installed`
(list all ids, no `isChatCapable` probe); Ollama → today's `OllamaModels.chatModels`.

### 5. App: Settings UI

In `SettingsView` body, add an **"AI backend"** `Picker` (Ollama / OpenAI-compatible). When
OpenAI-compatible is selected, reveal:
- a base-URL `TextField` (placeholder `http://localhost:1234/v1`), bound to `openAIBaseURL`;
- an optional API-key `SecureField` ("API key (optional)"), loaded/saved through `KeychainStore`
  account `"openai-compatible"` exactly like the existing Ollama key field.
Reuse the existing `init` load / `save()` persist pattern.

### 6. App: privacy indicator

Generalize the footer's cloud detection. `cloudActive` = **the active backend sends data off-device**:
- Ollama backend → `ollamaKey() != nil` (today's rule).
- OpenAI backend → the base URL host is **not** local (`localhost` / `127.0.0.1` / `::1`).
Add a small helper `isLocalHost(_ url: URL) -> Bool`. A local LM Studio therefore still reads as private.

## Data flow

Settings (backend, base URL, key) → `ProviderSettings` + Keychain → `makeProvider` builds the right
provider per role → `MeetingSession.providers[role].stream(request)` yields deltas to the pane. Model
pickers populate from the backend-appropriate discovery call.

## Error handling

- **Empty / malformed `openAIBaseURL`** while backend = OpenAI: treat as misconfiguration — model
  discovery returns `[]` (pickers empty) and a stream attempt surfaces via the existing `startError` /
  per-pane error path (`NSError(domain:"OpenAICompatible", code: status)`); the Settings field shows the
  placeholder as guidance. Do not crash; do not silently fall back to Ollama mid-session.
- **Non-2xx from the endpoint**: same as today's providers — throw `NSError(domain:"OpenAICompatible",
  code: statusCode)`, shown in the pane.
- **Discovery failure** (`/models` unreachable): return `[]`; the user can still type/pin a model via the
  existing model-pin path.

## Testing

- `OpenAICompatibleProviderTests` (renamed contract): SSE parse (delta, `[DONE]`, garbage), request body
  shape, stream stops at done; live transport via stub — 200 yields deltas (path `/chat/completions`),
  non-2xx throws `OpenAICompatible`/code, Bearer **present when key set / omitted when nil**, model in body.
- `OpenAIModelParsingTests` (new, small, pure Core): parse `{data:[{id:…}]}` → ids; empty/garbage → `[]`.
- Existing `OllamaContractE2ETests` (the `make e2e` gate) stays as-is. **No** OpenAI e2e contract test —
  it needs a live OpenAI-compatible server; the unit + stub-transport tests cover the wire contract.
- Engine tests run via `swift test`; UI changes verified by `make build` + manual `make run` (no UI tests).

## Definition of Done (per `CLAUDE.md`)

- `make build` clean; `swift test` (engine) green; `make e2e` passes.
- Docs updated: `README.md` (mention BYO OpenAI-compatible endpoint), `docs/manual-smoke-test.md`
  (a step to configure LM Studio/an endpoint and confirm a pane streams from it). The
  `docs/competition-analysis.md` ListenToMe row may note OpenAI-compatible BYO endpoints.
- **Close issue #52** in the PR; PR description states what was verified.

## Non-goals (YAGNI)

- Per-pane backends; named multi-endpoint lists.
- `/v1/models` capability filtering (list all ids).
- A separate OpenAI e2e contract test.
- Reviving the dormant `ModelRouter` (the per-role `providers` dict is the routing mechanism).
- Per-vendor SDKs (DeepSeek/OpenAI/etc.) — all are reached via the one generic endpoint.

## File summary

- `Sources/ListenToMeCore/OpenAICompatibleProvider.swift` (renamed from `DeepSeekProvider.swift`, generalized)
- `Tests/ListenToMeCoreTests/OpenAICompatibleProviderTests.swift` (renamed from `DeepSeekProviderTests.swift`, + optional-key test)
- `Sources/ListenToMeCore/OpenAIModelParsing.swift` (new, pure — `/v1/models` body → ids)
- `Tests/ListenToMeCoreTests/OpenAIModelParsingTests.swift` (new — parse ids; empty/garbage → `[]`)
- `App/OpenAIModels.swift` (new — HTTP `/models` fetch, delegates parse to Core)
- `App/SettingsView.swift` (ProviderSettings keys + backend UI)
- `App/MeetingView.swift` (`makeProvider` dispatch, `openAIKey()`, discovery dispatch, privacy `cloudActive`)
- `README.md`, `docs/manual-smoke-test.md` (DoD doc updates)
