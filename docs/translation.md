# On-device translation (#330, iOS 1.20.0 candidate)

Live translation and Summary translation are separate conversation choices on Mac and iPhone/iPad,
including Duo. This work is not included in published TestFlight 1.19.1 (39). It is being prepared for iOS 1.20.0 (40); upload and device acceptance are not yet established. The Mac feature remains unreleased.

## Live transcript

On iPhone/iPad open **More → Live translation**, or **Notes → Live translation**. On Mac use
**Languages** in the left rail. Choose a target and enable **Live transcript translation**.
Completed lines gain a translated line beneath the original as speech arrives. Partial words are
not translated. Enabling it also translates completed lines already in the conversation.

Editing or deleting an original removes its obsolete translation. Turning the feature off keeps
originals and hides derived translations. Speaker labels, selection, search, audio timing and
summary grounding continue to use the original speech. Copy translation explicitly from a line's
context menu; ordinary copy/export continues to use originals.

## Summary page

Open **Summary → Translate summary**, choose a language and press **Translate**. This translates
the completed summary already on screen. It does not regenerate it, change the AI provider or
change the global AI response-language setting. The original remains below the translation; **Close**
returns to original-only reading. **Share translation** explicitly shares the derived text.
Empty or streaming summaries wait for a completed result. A changed completed summary or target
refreshes an already-requested translation; another conversation clears that request.

Headings, list prefixes, blank lines and fenced code are kept. Prose inside formatting is translated
by Apple's model; inline Markdown fidelity and translation accuracy can vary. Review before sharing.
Summaries over 100,000 characters or 512 prose chunks are refused with recovery guidance. Long prose
lines are split into bounded chunks; code blocks are not sent to the translator.

## Compatibility, privacy and lifecycle

This uses Apple Translation on the device, independently of Apple Intelligence eligibility. The
exact source/target pair and installed assets are checked before any content reaches the translation
session, and checked again immediately before translation. The language list is a choice catalog,
not a promise that every device/pair supports it. Unsupported pairs show a reason. Missing packs
show **Prepare languages**; only that explicit action opens Apple's preparation/download flow.
Cancelling preparation, changing target or closing its controls invalidates the preparation result.
No fallback sends content to cloud AI or silently downloads assets.

Language choices are saved with the conversation and survive rename/re-transcription/Watch-import
updates. Derived translated text remains in memory, is not saved as original transcript/summary,
and is cleared by New/reopening. Local archives, ordinary exports, saved audio and backup choices
retain their existing ownership. Sharing a translation is an explicit user action.

Phone background/inactive and Mac window teardown fence pending results and stop queued work.
Returning resumes the current choices. Ordinary Mac app background recording is unaffected. Only
one native request per worker runs at once; obsolete uncooperative work must return before newer
work starts. Translation does not delay capture, start the microphone or select an AI provider.

The Watch has no translation UI or engine. Its original imported transcript can be translated on
the paired phone after transcription; Watch recording and transfer compatibility remain separate.

## Verification boundaries

`TRANSLATE-001`–`TRANSLATE-014` bind original preservation, archive/checkpoint behavior, native pair
adapters, stale-result/cancellation/background handling and native controls to XCTest. UI previews
use explicit DEBUG-only synthetic translations; they prove placement and controls, not model quality.
Real Mac metadata checks for all 12 offered non-English targets from English, plus three reverse
pairs, reported missing packs without requesting downloads.
Installed-pack output quality and installed Mac interaction require separate acceptance evidence;
simulator runs are never physical-device acceptance.

See the [source-matched validation record](translation-validation.md) for commands, outcomes, screenshots
and the explicitly recorded aggregate-log failure/resumption.
