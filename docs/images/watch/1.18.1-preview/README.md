# Watch review previews

Native English (US) captures of the existing Watch app. The earlier watchOS 26.5 set contains
[Series 11, 46 mm](series11-46-home.png) (416 × 496) and [Ultra 3, 49 mm](ultra3-home.png)
(422 × 514). That runtime cannot run Series 12 or Ultra 4; their profiles require watchOS 27.

The matching **watchOS 27.0 (24R362)** runtime is now installed. Fresh captures from source `f608b58`
cover the requested models, with all Watch app/native-test sources unchanged from main `a594077`:

| Model | Native pixels | Home | Microphone recovery |
| --- | --- | --- | --- |
| Series 12, 42 mm | 374 × 446 | [Preview](series12-42-home.png) | [Preview](series12-42-microphone-recovery.png) |
| Series 12, 46 mm | 416 × 496 | [Preview](series12-46-home.png) | [Preview](series12-46-microphone-recovery.png) |
| Ultra 4, 49 mm | 422 × 514 | [Preview](ultra4-49-home.png) | [Preview](ultra4-49-microphone-recovery.png) |

All **three unit tests and one UI test passed on each of these three simulators**, with zero failures
or skips and every Watch BDD binding verified. These are executions of existing tests, with no
invented historical red. Independent review verified the source, image hashes and dimensions, and
the denied-microphone/recovery/offline-remote assertions. The six images above were visually
inspected and are readable; the three scrolled offline captures have system-clock overlap and are
retained only as external diagnostics. They are not polished store screenshots. The
[new provenance](runtime27-provenance.json) retains exact source/binary evidence location and
per-image hashes. All three owned simulators were deleted and verified absent; the runtime remains
available for future testing.

These images are saved for maintainer review. **iOS 1.18.1 build 36 does not contain the Watch app**, so these are not customer listing uploads or evidence of shipped Watch support. A Watch-enabled build must pass the separate #181 release gates before its screenshots can be submitted.

The earlier Series 11/Ultra 3 denied-microphone/offline UI runs also passed. Their original home
images remain unchanged, with [separate provenance](provenance.json). Full external evidence for
both sets includes original attachments, diagnostics and command logs. No microphone recording
or physical-device transfer was performed. All images preserve native resolution without resizing.
