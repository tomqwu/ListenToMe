# iOS meeting workspace

The primary task is following a conversation while seeing its evolving summary. The transcript and Quick Summary stay together. A complete Summary and Deep Summary are deliberate review modes, with separate outputs and model choices.

## Layout

- iPhone: a compact conversation header, Live / Summary / Deep navigation, and one recording control anchored at the bottom. Live shares the reading area between transcript and Quick Summary. Save and Notes remain labeled actions beside recording; New and History stay in the navigation bar. Share lives in More.
- iPad: the transcript and Quick Summary remain in the left column while Summary or Deep Summary is visible on the right. Each column has its own reading area. At large accessibility sizes or short heights, use one outer scrolling column rather than nested scrolling. At accessibility sizes, the title scrolls with content and Save/Notes move into More to preserve reading space.
- Use a neutral grouped background, white/system cards, consistent 20-point insets and restrained indigo accents. Status, model, action and content have distinct typography. Avoid tinted blocks and repeated explanatory paragraphs competing with the conversation.
- Empty states explain the next action once. Populated states prioritize readable Markdown and transcript text. Settings and provider disclosures remain reachable through the model control and Settings.

## Model roles

Quick Summary can use Flash for short automatic updates. Summary defaults to a full model. Deep Summary requires a non-Flash model, preferring an API-listed Pro variant for a new setup. Repair the old inherited Flash assignment using a full variant from the same family where available; never silently fall back to Flash. Keep valid full-model selections stable across refreshes.

Every summary panel shows its actual provider/model and opens that role's model chooser. Only API-listed models are recommended; names and modification dates come from the live catalog, not invented release labels.

## Acceptance

Inspect empty and populated iPhone screens, iPad columns, landscape, and accessibility text sizes. Verify direct access to all three outputs, model-role persistence/migration, recording and Notes controls, Calendar and attachment entry points, and Markdown readability. Simulator screenshots supplement behavioral tests; they do not establish physical-device recording acceptance.
