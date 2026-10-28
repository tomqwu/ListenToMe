# Listen To Me — Mac privacy policy

Effective October 26, 2026. Developer: Tom Wu. Contact: [tom@cloudnativity.io](mailto:tom@cloudnativity.io).
This covers the native Mac app, including the Mac App Store version being prepared. The
[iPhone/iPad policy](ios-privacy.md) describes those platforms separately.

## Recording and local data

While listening, the app processes the microphone and system-audio channels you enable. Apple's
speech frameworks or optional WhisperKit models transcribe on your Mac. macOS controls microphone
and Screen & System Audio Recording access. No recording audio is sent to the developer or an AI
summary provider. Optional model downloads carry no conversation content. Optional speaker analysis
runs locally; temporary audio and voice-analysis state are not a reusable cross-recording voice profile.
Saved labels and edited speaker names remain part of the transcript.

Conversations, notes, AI outputs and the meaning-search index stay in local app storage. Saving audio
for playback is off by default. When enabled, recordings are retained locally with the conversation;
existing audio can be deleted separately or with its conversation, and automatic retention can be set.
Turning saving off stops new retention but does not erase audio already saved. Files you export or
share are outside the app's deletion controls. macOS backup and disk-encryption settings apply to this
Mac; iPhone/iPad data-protection guarantees are not a claim about Mac storage.

## AI requests and credentials

Apple Intelligence runs locally on supported, configured Macs. You may choose an Ollama server,
an OpenAI-compatible endpoint or a cloud AI service with your own credentials. Requests then send
the included transcript, notes, instructions, names and reference context to the provider you choose.
Automatic summaries send requests when enabled. History questions can send the selected excerpts
and question to that provider. Audio is not part of those requests. Remote providers have their own
retention, privacy and billing terms; see the [provider disclosures](ios-privacy.md#optional-cloud-ai-services).
The app has no developer-operated conversation server, advertising SDK or tracking SDK. Credentials
are stored in Keychain. Remove a provider's key in Settings to stop using it; uninstalling an app may
leave Keychain items behind.

## Selected files, Calendar and exports

You choose reference files/folders, audio/video imports, Calendar context and export destinations.
Included reference text and names can be sent to the selected AI provider. Calendar access is
requested when you use that import; imported notes become conversation context.

The Mac App Store build uses sandboxed storage and saved security-scoped bookmarks for selected
reference files/folders and the Markdown vault. They preserve your selection across relaunch and
are not uploaded. Clear detaches references and removes their saved grants; select again if access
expires. An already-running file read may finish, and clearing references does not erase answers
or text already sent to a provider. Save to folder writes Markdown notes into the folder you choose;
iCloud Drive or another provider may sync that folder under its own terms. Deleting app history does
not delete notes or exports already written outside the app.

## Your controls and support

Use History to delete conversations and their app-owned audio and search entries. Manage backups
and macOS permissions separately. The Store installation does not automatically import the standalone
DMG app's history, settings or permission grants. Only record and share content you are authorized to use.

If you contact support, we receive the information you send and use it to respond and troubleshoot.
Do not send passwords, API keys or private transcripts. Contact the address above for support-data
access/correction/deletion requests. The app is a general productivity tool and is not directed to
children. Material policy changes will be reflected here with a revised effective date.
