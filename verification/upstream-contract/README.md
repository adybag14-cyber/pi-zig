# Whole-tree contracts and the c268 source target

The reviewed source target is
`c268154ca1171c2f9eefe75d3d7372a68aada2d5` (Pi 1.3.0). Its native-generated
whole-tree contract is **pending**. No `tree-c268154c.json` has been created or
hand-edited. All existing immutable `tree-*.json` files remain unchanged.

The scheduled workflow currently checks `tree-97195ec3.json` (2,017 records).
Read-only analysis of the pinned official c268 Git tree predicts 1,941 tracked
records. Against that scheduled baseline the expected structural delta is 107
added, 183 removed and 310 changed paths. The immediate 8efd-to-c268 change is
different: 10 added, zero removed and 15 changed paths. These are prospective
counts from source metadata, **not executed native checker results**.

After a separate Root grant, use the existing native maintenance commands
`capture-upstream-contract <clean-detached-c268-checkout> <full-c268-commit>
<new-manifest>` and `verify-upstream-contract <checkout> <new-manifest>`.
The [c268 preparation record](../c268-authority-docs-contracts-sourceonly-20261017/README.md)
contains the exact pinned command plan, input hashes and acceptance conditions.
Switch the scheduled workflow's manifest path only after that real capture and
verification have passed and their source/evidence has been reviewed. This
documentation change does not bypass drift or release gates, regenerate the
model catalog, or certify native/application parity.

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
