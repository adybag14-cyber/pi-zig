# Preserved negative source checkpoints

These files are exact source Git blobs retained for audit, not alternate runtime
implementations. Original status/manifest/control bytes elsewhere in this packet
are unchanged. No historical observation is regenerated or rewritten.

- 6ac7ae83ff48054d88136be954f4ae52232c59ef: original async mkdir, before the owned
  pending/cleanup frontier corrections.
- 5122dfdf0d39c9a9f488eef973515dbea97335bd: first escrow implementation, before
  the post-entry current captured-slot correction.
- 5472f76bed88805cd97447e7e6e0f6f1462acb7f: current captured-slot correction,
  before the first-fatal no-replacement OOM condition.

The checkpoint snapshot manifest records the source path, exact commit and Git
blob, and snapshot SHA256. Only current f79 products belong in src/extensions/.
The final independent f79 receipt records closure and explicit unrun limits.
