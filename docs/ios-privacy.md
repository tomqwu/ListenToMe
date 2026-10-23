# Listen To Me — iPhone and iPad privacy policy

Effective September 15, 2026. Developer: Tom Wu. Contact: [tom@cloudnativity.io](mailto:tom@cloudnativity.io).

## Your conversations

Listen To Me transcribes microphone audio on your device using Apple's speech frameworks. The app does not save raw microphone audio or send it to the developer. Transcripts, notes, summaries and imported attachments are stored in the app's local storage, written with device data protection so the files stay encrypted until you unlock the device after a restart. Your device backup settings may include app data in backups managed by Apple; Settings has a toggle that keeps conversations, attachments and shared imports out of iCloud and Finder backups. The app has no developer-operated conversation server, advertising SDK or tracking SDK.

A new install summarizes on-device with Apple Intelligence by default where the device supports it, and on such an install the app does not contact ollama.com at all. Speech language assets may need to download before transcription works.

## Optional Ollama (Cloud or your own server)

Summaries go to Ollama only when you select Ollama as the provider. Requests are sent to the server shown in Settings: Ollama Cloud (`https://ollama.com`) unless you entered the address of an Ollama server you run on your own network, in which case the conversation text stays on that network and a saved Ollama Cloud key is never sent there. When Ollama is selected and you request an AI summary, the app sends conversation text, notes and relevant context over the network. Auto summaries send new conversation context as you speak while Auto is enabled. Optional AI speech correction sends completed phrases and nearby transcript text. Imported text included in notes or context can be part of those requests. Raw microphone audio is not sent. Your API key is stored in the device Keychain and is sent only to Ollama Cloud to authenticate requests.

Ollama operates independently. Its [privacy policy](https://ollama.com/privacy) describes transient processing of cloud prompts and responses, and retention of account and service metadata. Its account terms, usage limits and privacy practices apply when you use that service. We do not receive your Ollama credentials or cloud conversation content. You can turn off Auto and speech correction, select Apple Intelligence where supported, point the app at your own server, or remove the API key in Settings to stop future Ollama Cloud requests.

## Imports and sharing

You choose photos, files, shared notes and calendar events to import. Calendar access is requested for the calendar import feature; an imported event has join-link passcodes and e-mail addresses removed from its body and location before the text reaches your notes. Imported copies remain in the conversation until you delete them. A shared import the app cannot read is set aside and deleted after 24 hours. Sharing exports the content you choose to another app or recipient; that destination's privacy practices then apply. Deleting the original conversation does not delete copies you exported.

## Retention and deletion

Saved conversations remain on your device until you delete them from History (which has a search field for finding an older conversation) or you remove the app's data. To remove a saved Ollama key, use Remove API key in Settings; uninstalling an app may leave Keychain entries behind. Manage device backups separately in your Apple settings. We cannot recover or remotely delete conversations stored only on your device. Contact Ollama directly for requests about information retained by its service.

## Support

If you email support, we receive your email address and the information you choose to send. We use it to respond and troubleshoot, retaining correspondence while needed to resolve and follow up on the request or satisfy legal obligations. Please do not send passwords, API keys or private conversation content. You may request access, correction or deletion of support correspondence by emailing [tom@cloudnativity.io](mailto:tom@cloudnativity.io).

## Your choices and policy changes

You can revoke microphone and calendar permissions in iOS Settings. Only record or share content you are authorized to use. The app is a general productivity tool and is not directed to children. Depending on your location, you may have rights to access, correct or delete information you provide to us, or to complain to your local privacy authority. Contact us to exercise those rights. Material changes to this policy will be reflected here with a revised effective date.
