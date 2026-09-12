# iOS meeting workspace

The primary task is following a conversation while seeing its evolving summary. The transcript and Quick Summary stay together. A complete Summary and Deep Summary are deliberate review modes, with separate outputs and model choices.

## Layout

- iPhone: a compact conversation header, Live / Summary / Deep navigation, and one recording control anchored at the bottom. Live shares the reading area between transcript and Quick Summary. Save and Notes remain labeled actions beside recording; New and History stay in the navigation bar. Share lives in More.
- iPad: the transcript and Quick Summary remain in the left column while Summary or Deep Summary is visible on the right. Each column has its own reading area. At large accessibility sizes or short heights, use one outer scrolling column rather than nested scrolling. At accessibility sizes, the title scrolls with content and Save/Notes move into More to preserve reading space.
- Carry the existing waveform identity into the toolbar and Settings. Use a pale violet canvas in light mode and a deep ink canvas in dark mode, with elevated reading cards and consistent 20-point insets. Transcript uses teal, Quick uses amber, Summary uses violet and Deep uses orchid. Colour supplements the role label and icon; it never carries meaning alone. Keep tint mostly in headers so the reading area stays quiet.
- Recording is the strongest action: a violet button when ready, a dark red button while recording. The toolbar falls back to the waveform alone when the wordmark will not fit. Decorative artwork is hidden from VoiceOver and static; large text retains the existing scrolling layout.
- Empty states explain the next action once. Populated states prioritize readable Markdown and transcript text. Settings and provider disclosures remain reachable through the model control and Settings.

## Following the transcript

The transcript gets 34% of the Live reading area, between 160 and 260 points; Quick Summary gets
the remaining space. An expand action opens a full transcript reader. In landscape and accessibility
layouts, a four-line preview shows the latest words without nested scrolling; expand for all history.

The reader starts at the latest speech and follows both growing partial phrases and finalized text.
Only deliberate user scrolling pauses following. Content growth alone must not be mistaken for
scrolling away. Keep the older text stationary while paused; **Latest**, or manually returning to
the end, resumes following. A different conversation starts with fresh follow state.

## Model roles

Quick Summary can use Flash for short automatic updates. Summary defaults to a full model. Deep Summary requires a non-Flash model, preferring an API-listed Pro variant for a new setup. Repair the old inherited Flash assignment using a full variant from the same family where available; never silently fall back to Flash. Keep valid full-model selections stable across refreshes.

Every summary panel shows its actual provider/model and opens that role's model chooser. Only API-listed models are recommended; names and modification dates come from the live catalog, not invented release labels.

## Acceptance

Inspect empty and populated iPhone screens, iPad columns, landscape, and accessibility text sizes. Verify direct access to all three outputs, model-role persistence/migration, recording and Notes controls, Calendar and attachment entry points, and Markdown readability. Exercise growing partial text, finalization, manual history reading, resuming follow and expanded reading with real scroll gestures. Simulator screenshots supplement behavioral tests; they do not establish physical-device recording acceptance.
