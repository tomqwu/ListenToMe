# Native import finalization fixture

`orion.aiff` is a locally synthesized stock macOS voice reading authored test text,
not a user conversation. It is the 12.467-second file that reproduced the installed
Mac import finalization hang on October 27, 2026.

Text: Project Orion has a clearer plan. Maya will deliver the design draft on Friday.
The budget is $120. The next review is Monday at ten. We will keep the source documents
in the project folder.

Format: mono 22,050 Hz, signed 16-bit AIFF-C PCM.
SHA-256: `2cd3af266fd6b2dd0ea662b2c35bb5518eef147082a72ecddd5054688ff02404`.

`MacSpeechFinalizationTests` passes these samples directly to the real native
SpeechAnalyzer adapter; it does not play sound, open microphones or send audio remotely.
