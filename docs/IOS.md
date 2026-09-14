# ListenToMe for iPhone and iPad

The first iOS version is a standalone app, separate from the macOS release. It requires iOS/iPadOS
26 or later. The bundle identifier is `com.tomwu.ListenToMe.ios`, version 1.10.2 (24).

## iOS 1.10.2 (24)

A fresh install now defaults to on-device Apple Intelligence, falling back to Ollama with a stated reason only where Apple Intelligence cannot run. A provider chosen in an earlier build is untouched. Settings gains an optional **Server URL** so Ollama requests — summaries, Quick, Deep and speech correction — can go to an Ollama server you run on your own network instead of ollama.com. Use the computer's `.local` name; no API key is needed, and a saved Ollama Cloud key is never sent to a server you entered. The destination host is shown in the status text. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.2.txt).

## Attributed summary input

Summary, Deep and Quick all read the transcript with speaker labels and the user's typed notes
marked as `Notes:`. Summaries can therefore attribute a question or a commitment instead of
reporting the owner as unstated, and never present a typed note as something that was said.

Local speech is labelled `You` in prompts, the same label macOS uses, even though the transcript and
the Markdown export display it as `Microphone`: a device name is not a participant, and the review
prompts are told never to invent names. Remote or diarized speakers keep their own label.

The label format and the `Notes:` marker are shared with macOS; the two platforms still assemble the
full-review source differently (chunking and provisional-speech handling).
See [the shared policy](SHARED-LIVE-SUMMARY.md#attributed-input-and-user-directives-for-automatic-output)
for the exact rule and the known differences.

## iOS 1.10.1 (23)

An in-app What’s New screen shows the installed version/build and recent changes after an update. Continue acknowledges that exact build; future launches go straight to the workspace. More → What’s New reopens the offline changelog. Large text scrolls independently of the pinned Continue button. [What to Test](../metadata/ios/en-CA/what-to-test-1.10.1.txt).

Release notes live in `iOS/MobileReleaseNotes.swift`. Update its newest release entry when bumping the marketing version; an app-hosted test checks it against the installed bundle. The shown build number always comes from the bundle. This screen belongs to the app; Apple's TestFlight introduction remains managed by TestFlight.

## iOS 1.10.0 (22)

Auto now connects Quick evaluation to automatic Summary and Deep generation with the selected models. Medium/high recommendations run serially, coalesce pending context and preserve previous output on failure. Manual Generate takes priority and remains available after Stop. The UI describes event-triggered evaluation and shows full-review status. Quick allows enough bounded response room for GLM planning preambles, with a 30-second deadline; displayed recaps remain limited to three short bullets. See [the shared policy](SHARED-LIVE-SUMMARY.md#automatic-full-reviews-ios-1100) and [What to Test](../metadata/ios/en-CA/what-to-test-1.10.0.txt).

## iOS 1.8.0 (16)

Auto Quick Summary now uses an event-driven evaluator: completed speech and note changes enqueue
five-second batches, with no model polling during silence. Each read accumulates context and decides
whether to keep the displayed bullets or publish a meaningful update. Corrections send the previous
and current wording. Summary/Deep recommendations show a grounded reason and qualitative AI confidence;
they remain manual actions. Quick reads can run alongside a manual Summary or Deep response.

This release also stabilizes the transcript's reading position while new speech arrives. The history
view stays still while recording continues; Latest reveals the newest text and resumes following.

See [the scheduler's events, actions and tests](IOS-LIVE-SUMMARY-SCHEDULER.md). Calls have a 15-second
deadline; failures keep previous results and retry with backoff. Stop cancels pending reads, and manual
Refresh includes the stopped transcript. Automatic evaluation reads long input in bounded batches;
manual full-snapshot summaries retain their provider input limits. Working context is rebuilt from
original finalized text after reopening a conversation. Auto remains opt-in.

## iOS 1.7.0 (15)

Intelligent speech correction is optional and off by default. Tap the sparkles row in Live transcript,
or open Settings, then enable **Correct speech with AI** and select an API-listed Flash model.
The correction role is independent of Quick, Summary and Deep; it can also run alongside Apple
Intelligence summaries using your Ollama key. It sends only new completed phrases and up to 2,000
characters of nearby recognized speech. Notes, attachments and microphone audio are excluded.

Apple's live partial text appears immediately. A separate bounded queue checks finalized phrases,
with a 350 ms delay and a 12-second deadline per request. At most six phrases wait behind the active
request; under sustained overload the oldest waiting phrase stays as recognized. Phrases longer than
1,200 characters are kept unchanged. Failures never stop recording or replace the original; later
phrases are still checked. Turning correction off, changing its model/key, backgrounding or opening
another conversation cancels pending work. Stopping normally lets the final check finish.

Applied edits show **AI corrected**. Tap to compare the original and corrected wording or **Restore
original**. Both wording versions persist with the segment, and Markdown exports include an originals
section. Future summaries use the current transcript; existing summaries refresh only through their
normal manual/Auto updates. The model is instructed to preserve names, dates, numbers and negation;
local checks also reject number/negation changes and large rewrites. These checks are conservative
filters, not proof of accuracy. Review edits where wording matters.

The Cloud request uses streaming chat, `think: false`, temperature 0 and a small output budget.
[Ollama Cloud does not support schema-constrained output](https://docs.ollama.com/capabilities/structured-outputs),
so responses are parsed and validated locally. A complete final JSON object with exactly one text
field handles the GLM Cloud reasoning preambles observed with and without a closing think marker.
Trailing prose, malformed objects and partial JSON are rejected; reasoning is never shown.

## iOS 1.6.0 (14)

History uses native row actions: swipe right to Share, left to Delete, or touch and hold for both.
Sharing opens the system share sheet for the selected conversation without switching the active one.
Delete always asks for confirmation, including from the context menu; a full swipe cannot delete it.
VoiceOver exposes Share and Delete as custom actions. See [the interaction design and checks](IOS-NATIVE-INTERACTIONS.md).

Auto Quick Summary resumes at the remaining 15-second cooldown after an AI request finishes. Speech
received during a slow response is picked up as soon as the cooldown has elapsed, without another full
interval or a Refresh tap. Auto remains opt-in. Its panel shows off, waiting, updating, paused, up-to-date
and retry status, plus the actual error if generation fails. Failed updates keep the previous result.
The timer belongs to the recording session and continues when another workspace tab is selected.

## iOS 1.5.0 (13)

The waveform logo now appears in the workspace and Settings. A violet canvas, distinct accents for
transcript and each summary role, refined cards and a prominent recording button give the app a
consistent identity in light and dark mode. Empty states show what belongs in each panel. The compact
transcript, auto-follow behavior and independent model controls remain available. See the
[GUI review and design decisions](IOS-GUI-REVIEW-1.5.md).

## iOS 1.4.1 (12)

Live now gives more space to Quick Summary. The transcript takes about one-third of the reading
area, capped at 260 points, and follows the latest words as partial and final text arrive.
Scrolling back pauses following; scroll to the end or tap **Latest** to resume. Use the expand
icon to read the full transcript. Landscape and accessibility text sizes show a short latest-text
preview with the same expand action, keeping Quick Summary reachable in one scrolling column.

## iOS 1.4.0 (11)

The meeting workspace now has direct Live, Summary and Deep tabs on iPhone. Live keeps the transcript
above Quick Summary; iPad displays review beside the live conversation. A compact recording bar keeps
Notes close at hand. See [the design rationale](IOS-DESIGN.md).

Each summary shows its provider/model and opens that role's chooser. Quick Summary can use Flash;
Deep Summary requires a non-Flash model. Existing inherited Flash assignments are repaired using the
API catalog, while valid full-model choices are preserved. A fresh setup prefers Flash for Quick,
a full model for Summary and an available Pro variant for Deep. No Flash fallback is used for Deep.

## iOS 1.3.3 (10)

Use **More → Import from Calendar**, or the same action in **Notes**. Connect Calendar when prompted,
choose a date and event, preview the details, then tap **Import**. The app appends meeting context to
existing notes and names an untitled conversation after the event. It does not edit Calendar events.
Imported notes — the title, time, location, attendee names, the event's own notes and its link — become
part of your notes, and your notes are sent to the selected AI provider by every summary, including
Auto summary, and are included in **Share**. With Ollama selected that means they leave the device.
Two kinds of detail are therefore filtered out during import:

- **E-mail addresses.** Attendees are kept as display names only, as on macOS (an invitee with no
  display name is left out), and any address written in the event's location or body is removed.
- **The secret-bearing part of every link.** The event's own URL and any link inside its location or
  body keep scheme, host and path only; the query string, fragment and user info — where a join
  passcode such as `?pwd=…` or Teams' `?context=…` lives — are dropped.

Nothing else is filtered: the title, times, the event's body text, dial-in numbers and meeting IDs are
imported as written, so review the notes before summarizing if the invite contains anything you would
rather not send. Notes imported by an earlier version of the app are stored text like any other and may
still contain a passcode or an address — edit those notes if you want them gone.
Only calendars configured on this device are available; no direct server login is needed.

Reading existing events uses Apple's full Calendar access level and
[`NSCalendarsFullAccessUsageDescription`](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).
Denied/restricted access and dates without events have distinct messages. Permissions are requested
only through Connect Calendar, and rechecked when returning from Settings.

## iOS 1.3.2 (9)

Fixes automatic Quick Summary for short transcripts and failed-request retries. The recording session
owns automatic updates, independently of the visible screen. Settings remains usable while listening
and offers separate Quick Summary, Summary, and Deep Think model pages with a cached API catalog.

## Included

- Foreground microphone transcription using Apple's on-device SpeechAnalyzer. Language assets
  download on first use. Unsupported device/language and permission errors are shown in the app.
- Partial and final transcript text. Everyone picked up by the microphone is labeled **Microphone**;
  this version does not infer who is speaking. Unfinalized text is retained and labeled accordingly.
- Editable titles and notes; atomic local saves after finalized utterances/notes, explicit Save,
  save-before-New, local History, restoration on launch and Markdown through the share sheet.
- On-device Apple Intelligence summaries by default, or Ollama summaries — Ollama Cloud, or an Ollama
  server you run — with streamed results and secure API-key storage.
  Apple Intelligence accepts up to 8,000 characters (`PromptBudget.appleIntelligenceCharacters`, the
  shared cap macOS also clamps its Apple prompts to); Ollama accepts up to 60,000. Oversized input is rejected explicitly. AI output needs review.
- Recording stops/saves on backgrounding, audio interruption or microphone disconnection. The screen
  stays awake during active recording. No raw audio is saved.
- Version/build information in Settings.

System/call audio, background recording, Mac sync, audio-file import, WhisperKit and
per-person speaker identification are not included. A local/LAN Ollama server is supported only when you
enter its address yourself; the app performs no discovery and never switches servers on its own. Notes and saved
transcripts remain usable when the speech model or Apple Intelligence is unavailable.
App data is local to the sandbox; normal OS backup policy applies. Sharing explicitly exports text.

Summaries can run while recording: each request uses a snapshot of the notes and transcript at
that moment. Stop listening remains available during generation. A disabled summary action shows
its reason (empty text, model unavailability, microphone transition or an in-flight response).
Check again re-reads readiness. Apple model-not-ready status does not prove a download is active.

Summaries render headings, bullets, bold, italics and inline code, including streamed responses. Fenced code remains monospaced. Saved conversations and Markdown exports keep the original output.

## Conversation actions

History supports swipe right to share, swipe left to delete, and a touch-and-hold menu. Deletion asks for
confirmation and removes that conversation's transcript, notes, original attachments and all three AI outputs. Deleting
an active conversation creates an empty active snapshot so the deleted content does not reappear
on restart. Other conversations are preserved.

The **Live** tab shows the transcript above a full-width **Quick Summary**. **Deep Think** has its own tab with room for longer analysis. Landscape and accessibility text use a scrollable page. Start/Stop remains available in either tab. **More → Full summary** also offers **Summary**, **Quick Summary** (up to five concise bullets) and **Deep Think**
(a deeper analysis of decisions, tradeoffs, risks and unresolved questions). Each result is stored
separately, restored with its conversation and included when sharing. These are distinct prompts;
Deep Think does not promise a provider-specific reasoning mode. Requests use the selected provider
and preserve previous completed output on failure or cancellation.

## Photos, files and Apple Notes

Open **Notes** from the main toolbar. Take a photo, choose an image from Photo library, or use
**Add files** to copy a document into the current conversation. Each conversation supports up to
20 attachments, each nonempty and no larger than 20 MB. Tap a filename to preview it; its menu
shares the original, removes it, or copies selectable text into Notes. Text extraction supports
PDF, UTF-8 TXT, Markdown, CSV and JSON; scanned images need OCR elsewhere. Summaries receive only
notes and transcript text, never the original photo/file. The main Share action exports Markdown
and attachment names; use **Share original** to export an attachment's bytes.

For Apple Notes, choose **Share → Send Copy → ListenToMe → Import**, then return to ListenToMe.
This creates a new local conversation while preserving the current one. The share extension also
accepts compatible text, images and files from other apps. It queues imports in the signed App Group
`group.com.tomwu.ListenToMe.ios`; repeated delivery of the same batch does not duplicate conversations.
It does not browse or synchronize your Apple Notes library. Paste text or add an exported PDF if a
source app does not offer a compatible share representation. Apple Notes rich formatting may be
flattened; verify that any scans or embedded documents you need were included.

## Provider default

A fresh install defaults to **Apple Intelligence · on-device** whenever
`AppleIntelligenceProvider.unavailableReason` is nil — a value that depends only on
`SystemLanguageModel.default.availability`, never on a locale. On a device that cannot run it the
default falls back to Ollama and Settings states the reason: ineligible hardware, Apple Intelligence
turned off, the model not ready, or an unlisted reason reported by the system ("Apple Intelligence is
unavailable. Choose another provider in Settings."). That explanation is shown only while the device is actually on the
unchosen Ollama fallback; once you pick a provider yourself it disappears, and it is never shown to
someone who selected Apple Intelligence deliberately. A provider you have chosen before is always
kept across updates — the default applies only when no choice has been saved. Automatic Quick Summary requires Ollama, so it
stays unavailable with an explanation until you select Ollama yourself.

On Apple Intelligence every AI output goes through `AppleIntelligenceProvider`, the same transport
macOS uses. **Manual Quick Summary asks the on-device model for the bullets in prose** rather than for
the automatic evaluator's JSON envelope: a small on-device model cannot be held to that schema, so the
JSON contract stays with the Ollama-backed Auto loop. The prose answer is read back leniently: list
markers, numbering, a "Here is the recap:" preamble and stray code fences are tolerated, and an answer
carrying no takeaway shows "No key takeaway yet." in the pane (a *failed* request is what keeps the
previous summary). Generation failures are stated in plain language instead of a developer message:
a conversation longer than the on-device context window, a guardrail refusal, a busy or undownloaded
model, and an unsupported language each say what happened and that Ollama can be selected instead.

The language check is per conversation, not per device: if the on-device model does not support the
**conversation's** language (the recording language shown in Settings), Generate is blocked with that
reason before the request is sent. Whether Apple Intelligence is available at all — the fresh-install
default above and the macOS status line — does not depend on any locale, so a device used in an
unsupported UI language still defaults to Apple Intelligence. macOS behavior is unchanged by this;
only the shared provider's failure wording is now the same on both platforms.

## Ollama (Cloud or your own server)

Open **More → Settings → Summary provider → Ollama Cloud**. Enter your key and tap **Save API key**,
then **Refresh models from API**, select a **Model role**, **Choose model**, and **Test connection**.
Each of the three roles has an independent model selection. When a new key is entered, the test
button becomes **Save key and test connection** and saves that key before sending the request. Keys are stored in
iOS Keychain with `WhenUnlockedThisDeviceOnly`, never in preferences, session exports or the app binary.
Enter the key separately on each device. Remove API key deletes it from this device.

### Your own Ollama server

**Server URL** is blank by default, which means `https://ollama.com`. Enter an `http://` or `https://`
address — for example `http://your-mac.local:11434` for an Ollama server running on your own Mac on the
same Wi-Fi network — and tap **Save server URL**. Only the scheme, host and port are kept; anything that
is not a valid http(s) URL with a host is rejected and the previous server stays in place. Entering
`https://ollama.com` yourself is recognised as Ollama Cloud, not as your own server. **Use Ollama Cloud
instead** clears the setting.

**Use the computer's `.local` name, not its IP address.** The app declares
`NSAllowsLocalNetworking`, which exempts plain `http` only for `.local`, link-local and loopback
names — not for a numeric private address such as `192.168.1.10`. A plain-`http` URL whose host is a
private IPv4 literal (`10.x`, `172.16–31.x`, `192.168.x`) is therefore refused at save time with a
message naming the `http://your-mac.local:11434` form, instead of failing opaquely on the first
request. `https://` to any address, and `http://127.0.0.1`, remain accepted. Reaching a LAN address
uses iOS local-network access, so iOS asks for that permission the first time.

**Your Ollama Cloud API key is never sent to a server you enter.** The saved credential belongs to
ollama.com; requests to any other host go out without an `Authorization` header, so a private endpoint
cannot collect it. The key stays in the Keychain and is used again as soon as the server is Ollama
Cloud. No API key is needed for your own server; one is still required for Ollama Cloud.

Nothing is discovered automatically and the app never changes the server for you: the destination
is shown as **Server: …** in Settings and repeated in the refresh, connection-test and error status text
so you can always see where a summary would go. A server you enter is your own machine, not ollama.com.

Refresh calls `/api/tags` on the selected server (`https://ollama.com` unless you entered one) with Bearer
authentication when a key is saved, and preserves exact returned
model IDs. The recent-family section picks the newest API modification time for each advertised
standard/Pro/Flash variant of DeepSeek, GLM, Qwen and Kimi. All API models remain available, including
other families. This is API update recency, not an independently verified release chronology.
No unavailable Flash/Pro name is invented. Refresh preserves your selected model; if it disappears,
choose another. Model refresh does not prove key validity: Test connection verifies a complete streamed
`/api/chat` response using only a synthetic prompt. Cloud models run remotely; `/api/pull` is not needed.

Selecting Ollama is opt-in; a fresh install summarizes on-device. Generating any of the three AI outputs
sends the current notes and transcript to the selected Ollama server (Ollama Cloud, or the server you
entered); microphone audio continues to be transcribed on-device. Quick Summary has an opt-in **Auto** toggle (off initially; your choice is remembered across launches). While listening, new completed transcript text triggers an evaluation in five-second batches. A valid evaluation either keeps or updates the visible Quick Summary and may recommend a manual Summary/Deep review. No unchanged-input requests are sent; failed reads retry with backoff. Enabling Auto with Ollama selected sends those snapshots to Ollama. Deep Think stays on-demand. Existing output remains visible while the next response streams; failures keep the last completed result.
The last complete summary is preserved on HTTP errors, incomplete streams and cancellation. Streamed
text is shown separately until completion. Backgrounding cancels an active summary request.

## Build and run

Use Xcode 26+, XcodeGen and an installed iOS 26 simulator runtime:

```sh
make ios-build
make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

Open `ListenToMe.xcodeproj`, choose **ListenToMeIOS**, then a simulator or connected iPhone/iPad.
For a physical device, trust the Mac, enable Developer Mode and select your development team under
Signing & Capabilities if building with a different account. For device tests, override
`IOS_SIGN_FLAGS=-allowProvisioningUpdates`; the default test signing is for simulators. `make ios-archive` creates a signed
Release archive with automatic provisioning using the configured team.

**Simulator limitation:** live speech transcription is unavailable in the tested iOS 26.5 simulator.
Start listening explains this before requesting microphone permission. Notes, History and export
remain usable. Granting permission or changing language cannot enable the missing speech engine.
Use a physical iPhone/iPad for recording acceptance. Simulator builds and UI tests do not validate
live speech. The legacy recognizer also failed to load its model despite reporting local support.

The shared Swift package supports iOS 18+ for reuse; the actual app requires iOS 26 for SpeechAnalyzer
and Foundation Models. iOS does not depend on the Mac WhisperKit or FluidAudio binaries.

## Validation and release

Follow [the TestFlight release runbook](IOS-RELEASING.md) for exact archive, export, upload, account-recovery and tester-verification steps. A connected device is not required to upload an authorized beta; physical-device acceptance remains a separate production-readiness gate.

Maintain the [iOS listing metadata](../metadata/ios/README.md) alongside release changes. Apply the
Beta App Description and per-build What to Test in App Store Connect, and verify the uploaded app
icon and the installed Home Screen icon. Repository metadata files alone do not update the listing.

Run lint, shared core tests/coverage, the iOS build and UI tests, and a macOS build to protect the
existing product. The simulator UI tests verify the unsupported-speech explanation without a microphone prompt, retry, saving notes, New, History and restoration across app restart.
GitHub Actions builds both apps and runs the headless `ListenToMeCore` unit/integration test suite plus the 95% coverage floor as a CI check; GUI, audio, device and Ollama-e2e acceptance stay local, run on the local Mac with `make validate-local`, including iOS UI and app-hosted tests. Simulator builds use ad-hoc signing so Keychain tests exercise actual storage. The credential-dependent live cloud test is opt-in and skips unless configured locally. Before marking iOS production-ready, test on a physical iPhone/iPad:

1. First-use microphone denial, retry after granting, and unsupported language/model errors.
2. Model installation, then at least two minutes of real speech with live/final transcript text.
3. Stop finalizes the last phrase; interrupted/unfinalized text remains visible after save/relaunch.
4. Background, incoming call, Bluetooth disconnection, and repeated Start/Stop do not leave the mic active.
5. New preserves the old conversation; History and sharing include notes, transcript and summary.
6. On an Apple Intelligence eligible device, confirm a fresh install starts on Apple Intelligence,
   generate a factual summary, and verify unavailable, oversized-input and failure states keep the
   transcript and previous summary. On an ineligible device, confirm the fallback to Ollama names the
   reason. Optionally point **Server URL** at an Ollama server on your own network using its
   `.local` name, accept the local-network prompt, refresh models and summarize without an API key;
   confirm a numeric `http://192.168.…` address is refused with the `.local` hint. On Apple
   Intelligence also tap **Generate** on Quick Summary after a few minutes of speech and confirm it
   publishes bullets rather than "did not return a usable Quick Summary update", and that a very long
   conversation reports the on-device context window in plain language.
7. Camera permission denial/retry, photo capture, photo library, Files and Apple Notes Send Copy imports. Preview, share originals, extract document text, remove attachments and delete/reopen conversations.
8. Portrait/landscape iPhone and iPad layouts, large text and VoiceOver controls.
9. Import a real meeting invite with attendees and a join link, then read Notes: attendee names appear
   without e-mail addresses, and the event link carries no `?pwd=`/`#` join secret.

iOS distribution uses an Xcode archive/export and App Store Connect/TestFlight, not a DMG or macOS
notarization. A Mac Developer ID certificate cannot distribute an iPhone app. TestFlight needs an
App Store Connect app record and matching iOS distribution provisioning. A development IPA only
installs on devices in its provisioning profile; a simulator `.app` is not an iPhone installation.
Keep iOS tags (`ios-v…`) separate and never overwrite the latest macOS GitHub release with an iOS
preview. Publish a production iOS release only after device validation and successful distribution.
If provisioning or upload authentication fails, preserve the archive and report the exact error. Missing physical-device acceptance blocks a production-ready claim, not an authorized TestFlight beta upload.

Apple references: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer),
[Foundation Models](https://developer.apple.com/documentation/foundationmodels),
[ReplayKit](https://developer.apple.com/documentation/replaykit).

## iOS 1.9.0 (17)

Uses the [shared live-summary scheduler](SHARED-LIVE-SUMMARY.md) with macOS 1.4.0. Ollama was the fresh-install default in this build (changed to on-device Apple Intelligence in 1.10.2); existing choices remain saved. Auto requires Ollama and opt-in. Apple Intelligence remains available for manual summaries. See [What to Test](../metadata/ios/en-CA/what-to-test-1.9.0.txt).

## iOS 1.9.1 (18)

Quick publishes useful interim recaps while catching up with a backlog, with an explicit progress status. Quick requests prioritize three short bullets; manual generation displays only validated recap bullets. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.1.txt).

## iOS 1.9.2 (19)

Save confirms local History storage beside the bottom controls. Default Share sends readable text from the current conversation and History; More offers Share Markdown separately. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.2.txt).

## iOS 1.9.3 (20)

Automatic Quick Summary now evaluates substantial live recognition text at the shared five-second batching interval, even before Speech marks a phrase final. Short fragments wait for more words; silence does not poll. Final recognition replaces provisional wording. Status details exposes speech event, timer and model-read counts for device diagnosis without including transcript text. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.3.txt).

## iOS 1.9.4 (21)

Quick publishes its first short recap for a clear topic, problem, tentative proposal or substantive question without waiting for a decision. Questions are summarized, not answered, and ambiguous acronyms are preserved. Repetition still avoids unnecessary changes. Empty results say “Speech checked · No takeaway yet,” including after recording stops. [What to Test](../metadata/ios/en-CA/what-to-test-1.9.4.txt).
