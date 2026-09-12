# iOS GUI review — 1.5.0 (13)

Reviewed the installed simulator app on September 12, 2026. The waveform app icon was already present,
but its identity was missing from the conversation screen. This release brings that existing identity
into the app and gives its reading surfaces a consistent visual hierarchy.

## Findings and changes

| Finding | Change | Why it helps |
| --- | --- | --- |
| No visible identity in the workspace | Existing waveform plus Listen to Me wordmark; matching Settings header | Connects the installed icon to the app experience without consuming transcript space |
| Similar neutral panels made roles hard to distinguish | Teal transcript, amber Quick, violet Summary, orchid Deep; persistent labels and role icons | Makes each role recognizable without relying on colour alone |
| Flat background and generic cards | Adaptive violet/ink canvas, rounded reading cards, restrained border and header tint | Adds depth while keeping the text area quiet |
| Recording did not have enough visual emphasis | Strong violet recording action, dark red Stop state, labeled Save and Notes alongside | Makes the main action immediate and keeps related tools close |
| Empty panels looked unfinished | Static role illustration and a short explanation | Shows what belongs there without pretending generation is running |
| Model choices were easy to overlook | Tinted model pill with a chevron and at least 44-point touch height | Makes each role's chooser more discoverable |

The wordmark falls back to the waveform when space is limited. Decorative artwork is hidden from
VoiceOver. System text scales with Dynamic Type; the existing accessibility/landscape scrolling
layout remains. The transcript still takes about one third of Live, capped at 260 points, with
manual history reading, Latest and a full-screen reader. Notes retains its native import controls.

## Review evidence

Screenshots are actual rendered app views. Populated review screens use a synthetic product-planning
conversation through the real workspace, Notes, History and Settings; they are not evidence of an AI
request or physical microphone capture. The fixture is compiled only for Debug simulator builds.
Production archives must not contain the fixture or its launch argument.

The local evidence directory is `dist/ios-1.5.0-build13-evidence/`. It contains XCTest result bundles,
exported screenshots, contrast calculations, lint/build output and release verification. The core
colour pairs and white recording-button labels were calculated against their opaque backgrounds;
the minimum sampled contrast was 4.87:1. This calculation is not a complete accessibility audit.

Review covers light and dark iPhone screens, empty and populated content, Summary and Deep, Notes
imports, History, Settings, iPad columns, landscape and accessibility text sizes. UI regressions
exercise role selection, model persistence, native transcript scrolling and direct access to controls.
No provider, recording engine, automatic-summary timing or storage behavior changed.

Physical-device recording acceptance remains a separate check from simulator visual review and
TestFlight upload. The release runbook defines the upload, processing and Dev-access evidence.
