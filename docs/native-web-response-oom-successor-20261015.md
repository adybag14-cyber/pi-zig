# Response native OOM retirement successor

The earlier tested source `aea1001f72c5ca06e000b865ddfedf0101fc3936` passed the
actual central OAuth HTTP403 header-before-EOF wire and Response ownership tests
(4/4 including wrappers). Its unchanged strict Source176 Response projection
matched 109 of 114 rows. Five differences remain recorded: locked and disturbed
stream input without the public iterator, native URL inner-cause text, multipart
FormData, and the bundled lexical class name in a call without new. Expected
Source176 and projected114 fixtures were not edited.

The selected OOM gate measured 233 host allocations. Offsets0 and58 rejected as
trusted native OOM and freed every byte. Offset116 induced a real allocation
failure but stranded the module promise. This negative was preserved, followed
by the diagnostic-only source `f7e103f854fe05e08388bafbe36be17ca8e2c400`.
Its first-failure trace identifies `native_sdk_prompt_scope.own` growing its
ArrayList during `native_readable_stream.continueValue`'s `owner.agent` lookup.
The tee catch repeated that allocating lookup, so permanent host OOM prevented
error delivery to the actual branch readers. Native generation/tag2 and full
storage release were observed, while the required OOM assertion still failed
with `JavaScriptPromiseUnsettled`. Both negative runs have zero full posthash.

The exact two product leaves from Env source-only
`4594aec9b6291956f1b7fe180e8d37d33a1e62e5` (after `bb4dc948` and `c67dde03`) are
now intaken. Their hashes are:

- Core: `5EE40393B9B3D531E6E3BC89B6DF681656BBABB8680D42B4D03744FA56D179A2`.
- Facade: `D3AEB8D8EA08B3DFE1F534B6BFDD63289993285C7F850AE390FC71293DFB0A99`.

The failure path uses direct private JS roots and class IDs, errors both actual
branch streams and the source, and rejects the existing cancellation owner.
It does not reinterpret an unsettled promise as OOM. The normal32a stream path
is retained. A deterministic regression arms permanent host failure after real
source enqueue/close and before the tee continuation, requiring trusted OOM and
complete host storage release.

This successor also preserves `_Response` as the bundled lexical class name
while exporting the function name `Response`; explicitly configures actual
fixture IO; and constructs transport responses through real internal state,
with basic type and direct HTTP status rather than public ResponseInit limits.
The actual transport tests now require basic type. These source changes require
fresh matching gates; no result is asserted by this candidate note.

Root approved NATIVE1 for all five targets: strict Response source, actual
transport, selected Response OOM, deterministic stream OOM retirement and
unchanged genuine byte Source12. Env will run FileHandle8 separately against
these exact core leaves, avoiding unrelated FileHandle/UV imports into this
tree. The full frozen-input and normal16GiB/max4/-j1/1320/300/120/10 contract is
unchanged. Broader iterator, multipart and public graph source successors are
deliberately excluded from this negative-to-positive OOM gate.
