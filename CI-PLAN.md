# CI verification and evidence

The `CIF library` workflow runs on pushes, pull requests and manual dispatches.
The root module is `dongxuan2012-2/cif`; owned examples use the same account
namespace and local workspace membership. CI builds this repository's source,
including its public-package consumers, without requiring a published CIF package.
Read the run's `head_sha` and every required step's actual conclusion for the
submitted commit. A source manifest or an earlier green run is not a final-head
CI result.

- Install Node 24.11.0 and the official pinned MoonBit release using
  `scripts/setup-ci.sh`, then resolve the declared public dependencies.
- Record runtime versions and Git HEAD. Check, build and test the core library
  with warnings denied on JS and Wasm-GC. Run the Lunar, batch, selective and
  annotated consumers on their existing targets, plus formatting/interface drift.
- Run the existing append, file, saved-preview, target-validation, catalog,
  curated-removal and provenance recipients. These retain their original scope;
  the review renderer change does not modify parser, editing or numeric APIs.
- Run `examples/value-reader/verify.mjs`: two complete independent raw files
  (Pair-only CIF1 and explicit-frame CIF2) must yield the complete expected
  `values` JSON. Deliver those actual JSON files to an isolated public CIF and
  pinned Lunar module, checking physical source hash/spans, literal kinds and
  real numeric receiving with caller-selected metres. Check nine read-only
  scope/error controls, a legacy loop query/apply chain including existing-output
  rejection, and recipient rejection of changed source/span. Keep every raw
  command stream and actual compiler/source/output identity in its evidence.
- Run `examples/file-workflow/tests/review-browser.mjs` in an installed Chromium.
  The gate requires a browser rather than silently skipping. It builds the real
  CLI, consumes six independent complete source/result fixtures, runs preview,
  HTML review and hash-constrained apply, and reads the physical output back.
  It checks CR-only lines, CR-containing literal/replacement text, CRLF crossing
  either or both highlight boundaries, and ordinary LF/CRLF controls.
- The browser parses an identified copy of each generated page with a separate
  observer appended. It compares DOM text, per-character vertical positions and
  preformatted line heights against independently specified physical-line text
  in the same document. The original generated HTML remains separately hashed.
  Highlight whitespace and all source/plan/golden bytes are also checked.
- Upload the gate's raw command streams, generated HTML and observed test copies,
  screenshots, browser receipts, complete input/output files, compiled JS and
  identity summary as `review-browser-<head SHA>`, including on failure. Browser
  profiles and compiler caches are omitted; the executable identity and actual
  user agent are recorded in the summary.

The relevant local pass for a renderer-only change is the new browser gate and
`tests/saved-preview.mjs` (hash/span/replay rejection, existing-output protection,
and offline use). The unchanged core and older scientific cases need not be
repeated locally; the complete workflow remains required for the final commit.
For the additive `values` file reader, use its complete value-reader gate and
the included legacy query/apply controls; do not rerun the unchanged browser or
old scientific generators locally. CI still runs the full existing workflow.
Its separate `values-reader-<head SHA>` artifact retains raw streams, physical
deliveries, recipient source and compiled JS. Local and CI recipient workspaces
are independent public modules; whether they are also outside the Git checkout
is reported from their actual paths rather than assumed.
CI artifacts and local artifacts identify their own compiler/browser/output
bytes. Do not infer cross-host binary equality from a successful job. Six
Chromium newline cases do not certify every browser, visual layout or external
scientific adoption; source and preview hashes do not grant approval.

For an account namespace alignment, regenerate the existing interfaces for all
owned modules, check/build the root's JS and Wasm-GC targets, and run the actual
value-reader public-package/file consumer with unchanged behavior expectations.
Review generated interfaces for namespace-only changes. The full existing
workflow remains required at the final head; no string-replacement mirror tests
or large reference generators are needed for this metadata-only change.
