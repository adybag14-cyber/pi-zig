# Continuation after checkpoint 188

Checkpoint 188 advances the independent Zig rewrite from Pi 0.84.1 to the
latest authoritative upstream main available during the audit:
`853a80d26c90a14c1886f0ebb8ffaae133ca2185`, containing coding-agent and AI
release 0.84.4. The comparison checkout remains outside this repository. The
retired TypeScript/JavaScript reference is not needed and must not be restored.

The exact 0.84.4 provider catalog is reproducibly imported from the verified
release source archive and generates 1,290 models across 39 providers. The
native delta includes the new provider request metadata, reasoning/fallback
round trips, Copilot policy behavior, PowerShell and terminal controls,
model/thinking defaults, session sharing, queue/UI extension events, JSONL
repairs, package downgrade prevention, and the post-tool/terminal ordering
fixes covered by the 0.84.2 through 0.84.4 changelogs.

Future compatibility work must begin by resolving the then-current
`earendil-works/pi` main commit in a new isolated checkout, reading its
`AGENTS.md`, comparing from the recorded commit above, and refreshing the
language-neutral catalog and bundled changelog only through their pinned import
scripts. Never infer parity from version strings or restore a stale source tree
inside the rewrite repository.
