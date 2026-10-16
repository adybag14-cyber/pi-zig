# Local project layout

The project container holds `main`, `worktrees`, `upstream`, `evidence` and
`toolchain` as siblings. Root integrates changes in `main`; agents use their
assigned worktree. The local branch is independent of GitHub's published main
until complete application qualification and publication are finished.

Verification launchers should discover the container with
`tools/workspace/Resolve-PiZigWorkspace.ps1` and read its explicit metadata.
Do not restore hardcoded sibling directories under the user's home. Historical
proofs stay immutable; use `Resolve-PiZigHistoricalPath.ps1` with the sealed move
map when verifying a relocated historical input. A relocated proof is not a new
execution or a transfer of its original qualification scope.

The pinned dependency runtime has a separate recovery status. Its directory
existing is insufficient: complete original hashes, file inventories, workspace
links and recorded absences must pass before reference or native gates use it.

Acceptance requires `runtime_status` equal to `verified_exact_manifest`, an
explicit `runtime_verification_receipt` and its
`runtime_verification_receipt_sha256`. The receipt and its independently reviewed
full verification must be bound into each execution grant. The status string or
a directory's presence alone cannot authorize a run. The workspace admission
hold remains separate and must be checked before each execution phase.

Only pass an original historical path to `Resolve-PiZigHistoricalPath.ps1`.
Current contained paths already use the new layout and must not be projected
again. System executable paths with no relocation mapping pass through unchanged.
Mapped targets are required to remain inside the container.

The tracked `verification/workspace-consolidation-20261016/container-snapshot`
records the local layout, instructions and explicit move map at consolidation.
It is a historical checkpoint, not a current admission grant. Current container
metadata stays outside the `main` checkout so it can describe every sibling.
