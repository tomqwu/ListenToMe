# Listen To Me — Mac support

Contact [tom@cloudnativity.io](mailto:tom@cloudnativity.io) or [report a problem](https://github.com/tomqwu/ListenToMe/issues).
Include your Mac model, macOS version and app version. Do not include keys or private conversations.

The native Mac App Store version is in preparation and has not been submitted. The current public
standalone Mac download remains the signed/notarized 1.4.4 DMG. Source documentation can describe
features that are not in that older download; see [the changelog](../CHANGELOG.md).

## Listening and AI

Requires macOS 26 or later and an available speech language/engine. Microphone and system-audio
capture have separate OS permissions. If a channel is unavailable, read the recovery message before
starting. A checked permission on a standalone DMG or Dev build does not grant access to the Store
installation's separate identity. Use normal macOS consent; do not reset other applications' permissions.

Speech recording does not require summary AI. Apple Intelligence requires compatible hardware and
setup; alternatively configure your local server or an explicit remote provider in Settings. Check
the named destination before sending conversation text. Optional models can need a first download.
Speaker labels can be uncertain, especially with similar voices or overlap.

## Saved files and playback

Enable Save audio recordings before listening to retain audio for later playback. Open the saved
conversation's audio controls to play or export it; earlier unsaved audio cannot be recovered.

For Save to folder, choose a vault in Settings. For reference context, use Add files / folders.
The Store version preserves these selected grants across relaunch. If a folder/file is deleted,
revoked or unavailable, select it again. Clear removes saved reference selections. History deletion
does not delete a Markdown note or export already written to another folder.

The Store app has its own container, settings and permissions. Your existing standalone app's data
is not automatically migrated. Read the [Mac privacy policy](macos-privacy.md) for local storage,
optional cloud requests and deletion controls.
