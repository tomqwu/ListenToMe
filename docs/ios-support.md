# Listen To Me — iPhone and iPad support

Contact **[tom@cloudnativity.io](mailto:tom@cloudnativity.io)** for help. Include your iOS version, device model, and the app version shown in Settings → Release. Do not include API keys or private transcripts.

## Getting started

Requires iOS or iPadOS 26 or later. Tap Start listening and allow microphone access. Speech language assets may download on first use; your language choice is remembered across launches. Recording works while the app is open; it does not record other apps or phone calls. A call, Siri or an alarm pauses capture, the status line says why, and recording resumes when the interruption ends.

Use Notes to add context, Save to keep a conversation, and History to reopen, search or share it. Sharing offers readable text and Markdown. More → What's New shows the release version and recent changes, and appears after an update only when those notes actually changed.

## AI summaries

A new install summarizes on-device with Apple Intelligence where the device supports it. To use Ollama instead, enter your own Ollama Cloud API key in Settings, or the address of an Ollama server you run on your own network — use the computer's `.local` name, for example `http://your-mac.local:11434`, because a plain-`http` numeric address such as `192.168.1.10` is refused. Ollama account limits apply and internet access is required for cloud features. The app is free; third-party service access may have its own costs.

Auto reacts to new speech. Quick provides short key points; Summary and Deep update when the conversation merits a fuller review. They can also be generated manually. When Auto appears inactive, open Status details and check the provider and model status. A brief pause to combine incoming speech is normal; unchanged input does not require a new summary.

## Common fixes

- No transcript: check microphone permission, selected language and downloaded speech assets.
- Cloud error: test the connection in Settings, check your key and account limits, and refresh the available model list. For your own server, check the `.local` address and allow local network access.
- Apple Intelligence unavailable: check device support and enable Apple Intelligence in system settings, or select Ollama.
- Recording stopped: backgrounding stops recording and saves the conversation; a call, Siri or an alarm pauses it and it resumes on its own.
- Missing from a restore: check whether "Exclude conversations from iCloud backup" is on in Settings.

Read the [privacy policy](ios-privacy.md) for storage, optional cloud processing and deletion information.
