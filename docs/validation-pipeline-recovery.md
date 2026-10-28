# Local validation failure propagation and Settings recovery — #347

The full integrated Mac candidate at `02528bf9529291d86232aef5a31bdb49e84ada1a` is **failed**.
One iOS Save-to-folder UI test failed three assertions. Xcode reported failure, but Apple's GNU make
3.81 returned zero and continued the later stages because it did not honor `.SHELLFLAGS`.
The external supervisor inspected native events and rejected the run with exit 1. Its successful
child-process exit is not an aggregate pass. All 970 tracked input hashes match the source commit.

The [independent receipt](releases/mac-candidate-02528bf-failed-validation.json) records the actual
components: Core 1,266 tests / 7 optional skips / 98.2004% coverage; iOS 83 UI tests / 5 skips /
1 failed method (3 assertions), and 504 unit tests / 7 skips / no failures; Mac 74, Watch 29 unit +
5 UI, and four real-server contracts passed. All previously bound selectors passed, but the failing
legacy Settings method was not among them. This illustrates why binding traceability never replaces
the full-suite result. The real Mac English-to-Chinese branch also passed; it is not phone acceptance.

## Make pipeline regression

`DEV-009` binds six methods in `scripts/test-make-pipelines.py`. Before the tracked fix, those tests
loaded the actual repository Makefile and exercised ordinary pipelines plus the native iOS/Mac/Watch
recipes through harmless command stubs. The real repository red produced **10 assertion failures**
across 28 cases; failed producers could return success and reach later verification. The unpiped
build controls already rejected failures. Both available make executables are GNU make 3.81.

The smallest correction puts `-eo pipefail` in `SHELL`, which the older make uses, and leaves
`.SHELLFLAGS` as `-c` for implementations that support it. The same **six methods / 28 cases pass**:
failure exits propagate, logs remain, later verification does not run, normal success continues,
and paths with spaces work. Independent review reran the suite and verified the retained red and
green outputs. Modern/Linux compatibility was code-reviewed, not locally executed; hosted CI remains
a separate check. No compiler, microphone, model server or private data is used by these offline tests.

The suite runs inside `make validate-local`; the existing core CI's tooling BDD execution selects all
six bindings. Reproduce the focused checks with:

```sh
python3 scripts/test-make-pipelines.py -v
make bdd-check BDD_BASE=63628537cc12dc049dafb2d6251f6b0769b31139
```

Raw evidence is under
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-mac318-integration/make-pipefail-probe/`:
`repository-outcome.json`, repository red/green logs, command outputs and `independent-review.json`.
The smaller external toy red/green preceded the actual-Makefile regression and remains separate.

## Save-to-folder UI test repair

`VAULTUI-001` adopts the existing user journey rather than claiming a new product behavior.
The failed native PNG and accessibility hierarchy show Settings still open after the Files picker
was cancelled, with Save to folder **on**. Its toggle begins at y843 in an 874-point window; lower
disclosure/recovery rows had not been revealed. Stopping at a partly hittable toggle did not prove
that its footer, status or inserted Choose folder button were present in the lazy form.

The corrected test reveals each complete target within the Settings viewport, excluding its toolbar
and home-indicator edge. It reads the disclosure before enabling saving, confirms that reading leaves
the switch off, opens/cancels the real picker, confirms the switch stays on, and reveals both Choose
folder and the needs-folder status. Text queries match the target label inside the Settings form.
The missing-form path explicitly fails instead of returning silently. No app folder code changed.

The first focused invocation had an incorrect relative project path and exited 66 without running a
test. A revised helper then failed because a page-wide query selected the warning behind the sheet;
that failure was corrected by scoping queries to the form. The next focused run passed in 25.464
seconds with two native screenshots and 687 native inputs unchanged. Independent review inspected
both screenshots and caught the missing-form false-pass path before the final test was accepted.
After the explicit missing-form failure assertion, the final focused run passed: one test, zero
failures, 25.514 seconds; native process exit 0/reaped in 33.5858 seconds, with all 687 native input
hashes unchanged. Independent review viewed both final screenshots and cleared the correction.
The full combined run still requires its own terminal result; these focused passes do not turn the
original failed aggregate into a pass.

Evidence is retained under the same root in `vault-failed-attachments/` and `vault-ui-repair/`.
These are simulator UI/harness checks, not physical folder-provider persistence or recording checks.

## Installed Mac evidence and release limits

The [source-specific installed receipt](releases/mac-candidate-02528bf-installed.json) separately
records actual transcript editing/Copy/reflow and real Chinese Summary translation in the signed Dev
sandbox. Its independent visual/AX review preserves the distinction between captured outcomes and
input-event records. The completed Dev session was archived and cleaned only under its exact `.dev`
identity. No source-specific acoustic/route gap is waived by these results.

PR #318 still needs passing final-source local validation, independent review, required hosted CI
and its remaining installed audio acceptance before merge. This tooling/test repair does not change
app behavior, require an app version bump, submit the Mac Store draft or publish another beta.
