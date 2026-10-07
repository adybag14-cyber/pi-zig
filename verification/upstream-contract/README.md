The whole-tree contract records every tracked upstream path, mode, object kind
and Git object identity at the reviewed Pi commit. It detects added packages,
removed APIs, content changes, symlink/executable mode changes and submodule
changes. Object identities avoid Windows checkout line-ending differences.
Both SHA-1 and SHA-256 object formats are represented; a format change requires
review. Dirty tracked source, malformed identities, duplicate paths, unsupported
path encoding, source drift and commit changes fail explicitly.

Run `zig build maintenance -- verify-upstream-contract <upstream-checkout>
verification/upstream-contract/tree-28dcce2.json` before reviewing a new target.
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
