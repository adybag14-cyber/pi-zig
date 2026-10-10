The whole-tree contract records every tracked upstream path, mode, object kind
and Git object identity at the reviewed Pi commit. It detects added packages,
removed APIs, content changes, symlink/executable mode changes and submodule
changes. Object identities avoid Windows checkout line-ending differences.
Both SHA-1 and SHA-256 object formats are represented; a format change requires
review. Dirty tracked source, malformed identities, duplicate paths, unsupported
path encoding, source drift and commit changes fail explicitly.

Run `zig build maintenance -- verify-upstream-contract <upstream-checkout>
verification/upstream-contract/tree-42a3497d.json` before reviewing a new target.
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

The selected migration target is now
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
