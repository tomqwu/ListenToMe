# iOS 1.2.0 (4): session actions and AI modes

History now exposes a trash button and swipe deletion with an explicit confirmation alert.
Deleting an active conversation replaces its active snapshot before deleting the archive file,
preventing a deleted conversation from returning on restart. Other conversations remain intact.

Summary, Quick Summary and Deep Think use separate prompts, independently saved outputs and
independent Ollama model settings. Existing summary settings and records remain compatible.
Quick Summary requests at most five brief bullets; Deep Think asks for grounded analysis of
tradeoffs, risks and unanswered questions. This does not enable a vendor-specific reasoning flag.
All outputs are retained in session records and Markdown exports.

When key text is present, Test connection becomes Save key and test connection and saves that
text before creating the request. This corrects the path that could test an old saved key while
a replacement was visible. It is not proof of the cause of the user's reported HTTP 401.
The live 1.1.0 app connection path was independently rerun successfully on September 11; the
user's device-specific failure remains unresolved without its selected model and saved-key state.

Tests cover individual archive deletion, legacy migration without resurrection, invalid IDs,
active-session deletion across restart, independent output persistence/export, role-model
persistence, and missing-model isolation. UI coverage exercises cancellation and confirmation of
deletion, both new mode selectors, and the save-and-test action label with a replacement key.
The opt-in live cloud test now generates all three outputs and verifies they persist separately.
Physical-device acceptance is still required. Local release evidence belongs in
`dist/ios-1.2.0-evidence`; hosted CI runs core coverage, macOS build and iOS app/UI tests.
