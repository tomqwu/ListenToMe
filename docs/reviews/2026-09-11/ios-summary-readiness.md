# iOS 1.2.0 (5): summary readiness

The old UI disabled all AI generation whenever recording was active. The request guard also
rejected recording sessions. Generation now accepts idle or recording states and captures a
stable source snapshot. Stop listening remains enabled while a request runs; New and History
remain protected during recording or generation.

The UI and request path share a readiness check for empty source text, microphone transitions,
an existing response and provider unavailability. Every disabled AI action shows its reason.
Check again re-reads readiness. Apple modelNotReady is no longer described as an active download,
which the API does not establish.

Tests cover eligible generation during recording, blocked transitions, empty source and provider
unavailability; UI coverage checks the disabled-action explanation and recheck button. Actual
Apple Intelligence generation on the user's iPhone remains unverified. The user also requires a
successful cloud UI journey before publishing; the supplied test token returned HTTP 401 both in
the UI and in a direct documented request. Publication remains held pending those validations.
