# Listen To Me — iPhone and iPad privacy policy

Effective October 23, 2026. Developer: Tom Wu. Contact: [tom@cloudnativity.io](mailto:tom@cloudnativity.io).

## Your conversations

Listen To Me transcribes microphone audio on your device using Apple's speech frameworks. The app does not save raw microphone audio or send it to the developer. Transcripts, notes, summaries and imported attachments are stored in the app's local storage, written with device data protection so the files stay encrypted until you unlock the device after a restart. Your device backup settings may include app data in backups managed by Apple; Settings has a toggle that keeps conversations, attachments and shared imports out of iCloud and Finder backups. The app has no developer-operated conversation server, advertising SDK or tracking SDK.

A new install summarizes on-device with Apple Intelligence by default where the device supports it, and on such an install the app does not contact ollama.com at all. Speech language assets may need to download before transcription works.

## Speaker identification (on by default, on-device)

Identify speakers (Settings → Speakers) is on by default, and you can turn it off there at any time. It labels transcript lines Speaker 1, Speaker 2… using speaker models that run on your device; no audio or transcript leaves the device for it, and voices are not sent to the developer or any service. While you record, the app keeps a temporary in-memory copy of the microphone audio for this analysis, bounded to about the most recent ten minutes. That copy is never written to storage, and it is released when recording stops, once any final labeling pass finishes. To keep each person's label while they are quiet, the speaker models also produce a numeric voice summary (an embedding) for each speaker during the recording; it stays in memory, is never written to storage, saved with the conversation or sent anywhere, and is discarded when the recording ends, so the app does not recognize anyone from one recording to the next. While the setting is on and the speaker models are not on the device yet, the app downloads them once from huggingface.co, in the foreground: when the app opens, when you turn the setting on, or when you start a recording. That request carries no audio or conversation content. The downloaded models are kept out of iCloud and Finder backups and can be downloaded again. Speaker labels, and any names you give speakers in Notes → Speakers, are saved with the conversation like the rest of its transcript, so they appear in History search, shared text and exports, and are part of the conversation text sent if you choose Ollama. Turning the setting off stops new labeling; labels already saved stay until you delete the conversation.

## Automatic transcription language

When the transcription language is Automatic (the default; Settings → Transcription → Language), the app works out which language you are speaking on your device, so it can transcribe in that language. It uses a small speech model that runs on your device (the open-source Whisper "tiny" model, run with WhisperKit); your audio stays on the device and is never sent to the developer or any service for this. While you record, the app keeps a temporary in-memory copy of the first two minutes of microphone audio, so it can check the language and, if it switches, transcribe the start of the recording again. That copy is never written to storage, and it is released as soon as the check keeps the language, or when recording stops. The first time a recording in Automatic hears speech, the app downloads the Whisper language model (about 75 MB) once from huggingface.co; that request carries no audio or conversation content. The model is kept out of iCloud and Finder backups and can be downloaded again. Choosing a fixed language turns the check off.

## Optional Ollama (Cloud or your own server)

Summaries go to Ollama only when you select Ollama as the provider. Requests are sent to the server shown in Settings: Ollama Cloud (`https://ollama.com`) unless you entered the address of an Ollama server you run on your own network, in which case the conversation text stays on that network and a saved Ollama Cloud key is never sent there. When Ollama is selected and you request an AI summary, the app sends conversation text, notes and relevant context over the network. Auto summaries send new conversation context as you speak while Auto is enabled. Optional AI speech correction sends completed phrases and nearby transcript text. Imported text included in notes or context can be part of those requests. Raw microphone audio is not sent. Your API key is stored in the device Keychain and is sent only to Ollama Cloud to authenticate requests.

## Optional OpenAI-compatible server

Summaries go to an OpenAI-compatible server (for example LM Studio, vLLM or llama.cpp on your own computer, or a hosted service such as OpenRouter) only when you select **OpenAI-compatible** as the provider and enter that server's address yourself. The app never fills in or changes the address. When you request an AI summary, or while Auto is enabled, the app sends conversation text, notes and relevant context to that address; raw microphone audio is not sent. An address on this device or your own network (`localhost`, a `.local` name or a private address) is labelled "your server", because the app cannot verify where that server runs its model: a server on your network can forward requests to a cloud service. Any other address is labelled "may leave this device", and that service's own terms and privacy practices apply. Plain `http://` is accepted only for this device or a `.local` name; other addresses must use `https://`. Redirects are never followed, so a request is never re-sent to a host you did not enter. An optional API key for that server is stored in the device Keychain, is sent only to the server it was saved for, and is removed when you change servers. Speech correction is not sent there; it keeps using the Ollama connection if you turn it on. We do not receive the address, the key or anything sent to that server.

## Optional cloud AI services

Summaries go to a cloud AI service only when you choose one yourself in Settings → Summary provider → Cloud AI and add your own API key for it. Nothing is chosen by default, the app ships with no keys, and it never picks a model for you. Each service is labelled "Sends your transcript to" that vendor. When you request an AI summary, test a model, or while Auto is enabled, the app sends conversation text, notes and relevant context to the service you chose, at the fixed address listed below; raw microphone audio is not sent. Listing a service's models sends only your API key. Each service's key is stored separately in the device Keychain (`WhenUnlockedThisDeviceOnly`), is sent only to that service's address, and is kept when you switch to another service; Remove API key deletes it. Redirects are never followed. We do not receive your keys or anything sent to these services. Their own terms, retention and privacy practices apply, and you pay them for what you use:

| Service | Receives your transcript at | Privacy policy |
|---|---|---|
| OpenAI | `api.openai.com` | [openai.com/policies/privacy-policy](https://openai.com/policies/privacy-policy/) |
| Anthropic Claude | `api.anthropic.com` | [anthropic.com/legal/privacy](https://www.anthropic.com/legal/privacy) |
| Google Gemini | `generativelanguage.googleapis.com` | [Gemini API terms](https://ai.google.dev/gemini-api/terms) (Google may use free-tier content to improve its products) |
| DeepSeek | `api.deepseek.com` | [DeepSeek privacy policy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html) |
| OpenRouter | `openrouter.ai`, which forwards each request to the model provider you chose there | [openrouter.ai/privacy](https://openrouter.ai/privacy) |
| Groq | `api.groq.com` | [groq.com/privacy-policy](https://groq.com/privacy-policy/) |
| Mistral | `api.mistral.ai` | [Mistral privacy policy](https://legal.mistral.ai/terms/privacy-policy/) |
| xAI Grok | `api.x.ai` | [x.ai/legal/privacy-policy](https://x.ai/legal/privacy-policy) |

Requests to OpenRouter also name the app ("ListenToMe" and its GitHub address) in OpenRouter's optional attribution headers. With Claude Opus 5.5 or Sonnet 5.5, if Claude declines a request, Anthropic may re-run the same request on another Claude model (Anthropic's server-side fallback); the request stays with Anthropic.

Ollama operates independently. Its [privacy policy](https://ollama.com/privacy) describes transient processing of cloud prompts and responses, and retention of account and service metadata. Its account terms, usage limits and privacy practices apply when you use that service. We do not receive your Ollama credentials or cloud conversation content. You can turn off Auto and speech correction, select Apple Intelligence where supported, point the app at your own server, or remove the API key in Settings to stop future Ollama Cloud requests.

## Imports and sharing

You choose photos, files, shared notes and calendar events to import. Calendar access is requested for the calendar import feature; an imported event has join-link passcodes and e-mail addresses removed from its body and location before the text reaches your notes. Imported copies remain in the conversation until you delete them. A shared import the app cannot read is set aside and deleted after 24 hours. Sharing exports the content you choose to another app or recipient; that destination's privacy practices then apply. Deleting the original conversation does not delete copies you exported.

## Retention and deletion

Saved conversations remain on your device until you delete them from History (which has a search field for finding an older conversation) or you remove the app's data. To remove a saved Ollama, OpenAI-compatible server or cloud AI service key, use Remove API key in Settings; uninstalling an app may leave Keychain entries behind. Manage device backups separately in your Apple settings. We cannot recover or remotely delete conversations stored only on your device. Contact Ollama, the cloud AI service, or the operator of an OpenAI-compatible service you chose, directly for requests about information retained by that service.

## Support

If you email support, we receive your email address and the information you choose to send. We use it to respond and troubleshoot, retaining correspondence while needed to resolve and follow up on the request or satisfy legal obligations. Please do not send passwords, API keys or private conversation content. You may request access, correction or deletion of support correspondence by emailing [tom@cloudnativity.io](mailto:tom@cloudnativity.io).

## Your choices and policy changes

You can revoke microphone and calendar permissions in iOS Settings. Only record or share content you are authorized to use. The app is a general productivity tool and is not directed to children. Depending on your location, you may have rights to access, correct or delete information you provide to us, or to complain to your local privacy authority. Contact us to exercise those rights. Material changes to this policy will be reflected here with a revised effective date.
