# Whole-tree contracts and the c268 source target

The reviewed source target is
`c268154ca1171c2f9eefe75d3d7372a68aada2d5` (Pi 1.3.0).
The actual native capture and verification completed on 17 October 2026.
[tree-c268154c.json](tree-c268154c.json) contains **1,941 tracked records**;
verification reported `added=0 removed=0 changed=0` against that same clean
detached source. The scheduled workflow now checks this generated inventory.

The file is an exact 354,411-byte copy of the accepted native output, SHA256
`588657E89849CDF6E7162FA3729A12C1DEFFB0972264441C1CD6DE1DAC3D3773`.
The independent acceptance's original SHA256 is
`D1306FB30A3988623BDD269C8B63CA6B95EAA20CC7E26BAF0397ACB4B1679DE5`;
a labelled public projection is retained in
[c268-native-capture-20261017.json](c268-native-capture-20261017.json).
Its capture/verify root Zig owners exited zero, complete Main/compiler/source
and control seals matched, and independent final owner absence closed. The
actual source records also match the official c268 Git tree. Utility provenance
comes from the frozen build graph, verbose invocation and hashed artifact;
no separately observed utility-child PID is claimed.

The historical `tree-97195ec3.json` and all earlier contracts remain unchanged.
The [source preparation record](../c268-authority-docs-contracts-sourceonly-20261017/README.md)
retains its original prospective deltas: 107 additions, 183 removals and 310
changes from the old scheduled baseline, versus 10 additions and 15 changes
from the immediate 8efd source. Those older-baseline deltas were source-tree
analysis, not an executed native verification against 97195.

This proof certifies structural capture and comparison. Runtime, full native
application, default selection, hosted CI and release parity remain separate
gates. The model catalog and generated schemas were not regenerated here.

The following descriptions and target labels are historical observations.

The whole-tree contract records every tracked upstream path, mode, object kind
and Git object identity at the reviewed Pi commit. It detects added packages,
removed APIs, content changes, symlink/executable mode changes and submodule
changes. Object identities avoid Windows checkout line-ending differences.
Both SHA-1 and SHA-256 object formats are represented; a format change requires
review. Dirty tracked source, malformed identities, duplicate paths, unsupported
path encoding, source drift and commit changes fail explicitly.

The newest immutable observation is `04566631c2b51fb688486bc1f040f60d1518c126`.
`tree-04566631.json` records all 2,023 paths using the native capture tool against
a clean detached checkout. Its new durable CodeMode replay and sandbox-outcome
contracts are migration requirements still in progress. Capturing this tree
does not change the release-parity guard or certify those native behaviors.

Run `zig build maintenance -- verify-upstream-contract <upstream-checkout>
verification/upstream-contract/tree-89e5c2c0.json` before reviewing a new target.
The command prints all changed paths and fails with UpstreamContractDrift.
Even a different commit with an identical tree requires provenance review.
After review and original/native contract regression updates, create a new
immutable record with `capture-upstream-contract <checkout> <expected-commit>
<new-manifest>`. Existing reviewed records should be retained.

This is structural detection, not a promise that unknown behavior is compatible.
Semantic changes require the corresponding original-source captures, native
implementation and process/ownership/parity gates. Untracked local files are
outside the upstream Git contract. Invalid UTF-8 paths fail instead of being
silently normalized. Case-distinct paths are retained as distinct Git paths.

The preceding migration target was
`42a3497d03ad17e308a2299fa824727894f2c0ec` (Pi 1.1.0 plus newer commits).
The native capture command records all 1,988 tracked paths and verifies them
against the clean upstream checkout. Previous immutable manifests remain
available. The earlier `f1b2e77` worktree context-file correction remains
qualified in Windows and native Linux, Debug and ReleaseSafe.

The new target changes Durable tool tasks to version 2, adds nested tool calls,
structured output, caller restrictions, restart cancellation and Session failure
semantics. Those are semantic migration requirements, not automatically
compatible changes. Their source captures, native implementation and lifecycle
checks are still in progress. The SDK, extension runner, TUI and MCP source used
by the preceding focused qualifications did not change in these two commits.

The subsequent `42a3497d` change adds Durable image reads and optional Photon
image processing, with new image interfaces and read-tool behavior. Its 20-path
diff leaves the SDK, TUI, MCP and task driver source unchanged. The Durable image
and read-tool migration is still in progress; advancing this structural baseline
does not certify that new behavior. The earlier `eba84973` manifest is retained.

This selected-source drift baseline records the migration target. The native
migration is still in progress; changing this baseline does not certify the
remaining SDK, UI, transport or public-API contracts, enable the native default,
or replace the separate release-parity guard.

The current migration target is
`89e5c2c075535e2f427c30fc74720d65b2944ff9` (Pi 1.1.0 plus newer commits).
`tree-89e5c2c0.json` records its complete tracked tree using the native capture
tool against a clean detached upstream checkout. Earlier records remain intact.
Subsequent upstream changes therefore remain visible as explicit drift.

The newer source includes retention timing, custom input entries, image worker
boundaries, the `pi.dev` schema URLs, omission of thinking from compaction
summaries, and persistent compaction failure reporting. Each behavior needs its
own source comparison and native lifecycle checks. The schema projection is
generated from the immutable archive; the other migrations have independent
implementation and qualification status. Updating this structural target does
not certify full compatibility, change the native default, or authorize bridge
removal or release.
