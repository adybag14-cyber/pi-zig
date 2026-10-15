# Response qualification candidate

This new isolated tree starts from the immutable Response source checkpoint
`dbd839cf0a583e127ae7b74fbf85f1ebe22c12c5`. The previous public source checkpoint
is preserved. No runtime result is asserted by this candidate note.

The actual dependency closure is narrowly intaken:

- Env stream files `native_readable_byte_stream.zig`,
  `native_readable_stream.zig`, `native_stream_helpers.zig` from import-closed
  `ddbbd884983656660c6e02b16c71e96fc7da3d65`, with the real default-value queues
  and generic tee successor `32a785a005f1c3bc6c8ceeb158cfeed2a3664018` for the
  first two files. These public composition files remain source-only before
  this gate; inherited private byte/FileHandle qualification is not extended.
- Only the Engine stream-binding field and matching deinit release are added;
  the older Env Engine is not copied.
- The separately reviewed direct-C live ArrayBufferView span prerequisite is
  applied exactly from `borrowed-live-view-span-only.patch`, SHA256
  `ED69C338C2CBDCF779352FAA1552AC4820DAA391AAEA77397C7610A9FE472576`.
- Shared Body weak Response registry `a441223fb4f8bdc9dfccd464456504cdb7bb8f41`
  and optional async-iterator branch correction
  `8685b0a9185387aacd086f702e048d64b096ac6a` are intaken as dedicated commits.
- The central OAuth HTTP file is restored from
  `a9211502d3a754baf353c9bb64c4d22e08a88175`, including
  `7bf723695ff7732d1f9a8fc61a92a0ebf6b851aa`. Its auth helper file is taken
  exactly from qualified `95e4ba746780a9b8bfaa7c708646299ffb6dd986`.

The Blob/File/FormData/WebIDL/collector/decoder/native-function files already in
the Response base match the qualified Body dependency source `aa119f26` exactly;
the retained proof successor is `a8b2ef7de68e63e77f46c1d21b44de28a31391ed`.
That earlier gate covers its stated 17 Source176 observations and Headers189,
not the new stream composition, Response or OAuth wire path.

Response owner finalizers/markers now tolerate an owner allocated before a Root
allocation fails. Transport and URL-present cloned responses register the real
stream using the shared weak registry, with no JS call from a C finalizer.

The transport gate exercises the exact central OAuth boundary against a native
loopback server. The server flushes HTTP403 plus duplicate Set-Cookie headers,
then holds the body behind a native event. The guest releases that event only
after receiving a genuine immutable Response; it then consumes actual JSON.
Buffering the raw body to EOF cannot pass this test.

The 114-row replay still compares every original captured Response row exactly.
It accumulates all differing rows before failing, preserving engine diagnostic
and missing-feature evidence without rewriting goldens or filtering failures.
Generic stream support is actual native source; shared reader/controller/request
prototypes, async iteration and BYOB-aware tee remain incomplete. Shared Body
multipart and arbitrary async-iterable branches also remain explicit limits.

The owned runner compiles all three dedicated targets before runtime. Each
transport, source and selected-OOM runtime phase requires the matching all-target
compile and zero full posthash. Candidate, full vendor, compiler19546,
Node-tools1774, immutable Body176/Node368 string bodies plus undefined `configs`,
Source5ab1967, runtime31064, original84 absences and exact controls are bound.
The resource contract is Root NATIVE1, normal16GiB/max4, `-j1`, compile1320s,
runtime300s, tests120s, host await10s and owner settle10s.
