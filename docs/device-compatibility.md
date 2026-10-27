# Device and feature compatibility

The iPhone/iPad compatibility changes below are published in [TestFlight 1.18.0 (35)](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.18.0-build35).
Current-source physical acceptance remains pending. Mac changes are merged but unreleased, with
installed GUI/OTHERS acceptance explicitly deferred by the maintainer; see [HANDOFF](HANDOFF.md).
TestFlight 1.19.0 (38) includes the [Watch beta](watch-beta.md), with uploaded-package signatures and Apple’s processed identity verified; physical acceptance remains pending. Native lifecycle tests check cancellation/Stop and readiness again after permission returns, before audio activation.

An OS version alone does not establish feature support. The apps require version 26 or later of
their platform OS, then query the actual framework, selected language, permission and model state.
Apple Intelligence eligibility is separate from speech recording. No compatibility check selects a
cloud provider, sends conversation text, requests microphone permission or downloads a model.

| Feature | Runtime check and supported action | When unavailable |
| --- | --- | --- |
| iPhone/iPad live speech and Watch-file transcription | Prefer supported SpeechTranscriber; otherwise use supported on-device DictationTranscriber. Install the chosen local language assets only when transcription is requested. | Disable live Start with its device/language or denied-microphone reason. Offer recording settings or the applicable microphone settings action. Unexpected preparation failures still show the full startup alert. |
| iPhone/iPad language choices and Automatic | Use the union of languages supported by the available local speech modules, with installed/downloadable status. Automatic filters against the same catalog. | Keep unsupported choices explanatory; an unavailable detection model does not turn recording into cloud ASR. |
| Apple Intelligence summaries | SystemLanguageModel runtime readiness and the conversation's language; refresh on foreground/settings. | Do not offer Apple as a working provider. Preserve saved choices, explain setup/eligibility and require an explicit alternate provider/server/model/key. Recording remains independent. |
| Mac transcription | Check the selected engine/language and microphone access. Legacy SpeechRecognizer also needs local recognition support and its Speech permission. WhisperKit retains explicit first-use model preparation. | Hide unsupported engine choices, explain the saved unavailable choice, and block Start with settings/permissions recovery. Unknown microphone permission can be requested by an explicit Start. |
| Mac AI | Offer Apple only when its runtime model is available; gate its execution for the conversation language too. | Preserve saved provider settings and show the reason. No automatic local/cloud switch; capture remains independent. |
| Watch local recording | Check its own microphone access, battery and storage. Refresh while active. | Explain the local reason before Record/Continue. Phone connectivity is independent; finished audio stays queued for later sync. |
| Watch iPhone remote | Require reachability, matching protocol and explicit current phone recording capability. | Block Start with recovery for an unknown/older phone or unsupported capture. A reachable active recording can still be stopped even if Start capability is lost. Commands are never queued. |
| Normal iPhone/iPad simulator app | Live capture is unsupported. Notes, history and export remain usable. | Explain before Start and do not request microphone access. Synthetic release fixtures explicitly supply a compatible profile; their screenshots do not prove microphone acceptance. |

Live and Summary show a compact recording compatibility cause, settings recovery and an Info action
for the full instructions. VoiceOver retains the full reason. Short landscape and accessibility
layouts keep the recovery usable and let the user scroll to model controls. Native engine menus
clear old language choices while checking; late or cancelled checks and retained menu actions cannot
restore an unsupported choice. Apple AI actions recheck current native readiness before selection.

Start preparation has cancellation ownership across asynchronous checks. Stop, New and window close
invalidate an old Mac request before permission, capture or a late denial can affect a new
conversation. A superseded iOS foreground handler cannot consume shared imports after backgrounding.

The connected iPad Pro 12.9-inch (4th generation), on iPadOS 27.0.1, reported advanced transcription
unavailable and Apple Intelligence device-not-eligible, but supported English on-device dictation.
Its prior installed build reproduced the failed Start; a development candidate with the dictation
fallback then produced new real microphone words and retained opt-in audio with Play/Pause controls.
This is evidence for that device and path, not a claim about every iPad/language or an accepted
TestFlight upload. Final source acceptance and remaining limitations belong in the release evidence.

Compatibility is part of [BDD](BDD.md): `DEVICE-001`–`DEVICE-010`, `CAPTURE-001`–`CAPTURE-009` and
`CAPABILITY-001`–`CAPABILITY-003` bind policy, native adapters and controls to concrete tests.
Core policy tests alone do not establish native UI or physical readiness. Keep simulator, actual
microphone/OTHERS capture, Watch pairing, accuracy and publication evidence separate. See
[manual acceptance](manual-smoke-test.md) and [iOS distribution](IOS-RELEASING.md).

The #310 live speaker fix, published in TestFlight 1.18.1 (36), prepares its optional on-device models separately from speech
and AI readiness. Model failure cannot disable microphone recording or select a cloud service.
Native real-model tests establish bounded fixture outcomes; simulator substitutes only establish
controls. See [speaker model compatibility and limits](speaker-identification.md).

## Translation (#330, unreleased)

Mac and iPhone/iPad (including Duo) check Apple Translation's exact source/target installed-pair
status separately from speech and Apple Intelligence. Installed pairs run locally; missing packs
require explicit **Prepare languages**; unsupported pairs show a reason without sending text. The
Summary page can translate a saved summary even if its original AI provider is unavailable. Neither
translation path enables capture or changes providers. Watch offers no translation engine; imported
text can translate on phone. See [translation](translation.md) and `TRANSLATE-001`–`TRANSLATE-014`.
