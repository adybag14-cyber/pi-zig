# Focused fatal module execution qualification

The focused Windows Debug proof passed on exact source
`55f65f6a4a40e6aafbbe4d32064c1020fa0b6a35`, using pinned Zig 0.16.0.
It covers seven START/dependency controls and six resumed-module controls.
Each artifact also selects the mandatory storage declaration check: actual
metadata and execution therefore contain eight and seven entries respectively.
All fifteen completed with zero failure, skip, error-log or allocator-leak flags.

The reviewed C SHA-256 is
`F06F1F2A23CB024FF381DB02CF43D1C249DE5848689D005918F7D1FB80BE9B5E`;
the unchanged header is
`341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB`.
The implementation retains first fatal reasons across module START, deferred
ancestor execution, resumed completion, public resolving hooks and cleanup.
It records cached outcomes before releasing frame roots and stops inactive or
already terminal module callbacks before they touch a retired stack.

An independent reviewer decoded the actual binary metadata and test-result
streams, verified all six process identities and exit-zero receipts, and
compared all 10,495 source and 19,546 compiler file rows before, between and
after both groups. Every comparison had zero drift. All six process IDs and
the complete native admission census were independently absent afterward.

The two archived executables were inspected with Microsoft's PE dependency
tool. Neither imports `sqlite3.dll`. This check applies to these exact test
artifacts; it does not qualify an unpublished standalone application package.

The sealed `verification/tla-focused-proof-20261016` packet contains the exact
executables, raw metadata/runtime protocol bytes, owner records, complete seals,
driver, import inspection and independent review. Every archive entry was
rehash-verified. Earlier preflight, SDK-import, metadata-count and test-syntax
negatives remain unchanged in the project evidence directory.

The subsequent scoped C regression run passed ten groups and 116 actual selected
entries on `4e94611b6f1379df92a4eb35c14cb91bc5c4531e`: foundation6, async26,
generator19, generator-GPA2, JSON11, Source51-2, operators2, Engine20, recovery23
and SDK-boundary5. Seven groups passed before the strict metadata gate found
the additional Engine private-cache test; the three-group continuation retained
all earlier results and ran the correct complete selections. An independent
review decoded all streams, checked all 32 owner receipts and rehashed every
source/compiler file and complete inventory with zero drift and final absence.

`verification/tla-core-proof-20261016` contains the raw regression proof and
independent audit. Exact executable copies remain in their original local
evidence directories; the raw-proof archive declares their hashes and does not
claim to contain those binaries. Root integrated the F06 repair after both
focused and regression acceptance.

This remains component evidence. The original Models allocation-160 case,
complete application/default SDK integration, later native-body resolving-hook
work and hosted/release profiles require separate evidence.
