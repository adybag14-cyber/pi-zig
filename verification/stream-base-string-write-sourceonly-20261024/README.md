# StreamBase fixed-encoding WriteString successor

This source packet implements the complete four fixed-encoding WriteString callbacks from retained Node24.13 stream_base.cc 337–443: ASCII, LATIN1, UTF8 and UCS2. It consumes the actual Write/WriteWrap owner in the prior immutable Write packet. Main remains 65fac9975b25e9a5e4c00d7d7bca499aae1275c0.

## Selected sources and intake

Use only the exact six candidates in source-intake.json. The C/header and WriteString owner are under projected-v2; the selected test is under projected-v3. The dispatcher and standalone build are under projected. Earlier authoring drafts remain preserved and are not selected.

Apply this successor after the first 13-control JS-dispatch packet and the 20-control Write packet. Compose the 1,817-byte build-addition.zig.txt before the prior Write target in any newer combined build. Do not replace a combined build with the standalone projection: that projection contains the Stream prerequisites but not other agents' later Module additions.

The QuickJS C/header change is a narrow allocation-free flat-string code-unit view. It returns no JS surrogate object or guest-visible facade. The genuine primitive String is first flattened with the existing intrinsic JS_ToString API under the operation's allocation boundary, and its owned flat result stays retained throughout the data borrow. The view rejects ropes and nonstrings rather than casting them to the wrong storage representation. Existing str8/str16 resolve normal, sliced and indirect storage.

A fresh QuickJS library is required for the new C ABI. No current binary qualifies these changed bytes.

## Original behavior preserved

ASCII and LATIN1 keep the low eight bits of each UTF16 code unit, including high-bit bytes, NUL and surrogate units. UTF8 combines valid pairs and replaces lone surrogates with U+FFFD. UCS2 emits little-endian code units without surrogate replacement.

The actual original long-UTF8 boolean expression still evaluates StorageSize after Size succeeds. Consequently its final capacity remains three times the UTF16 length. The implementation preserves this, including the 16 KiB immediate-write decision, instead of implementing the different optimization suggested by the preceding source comment.

Direct DoTryWrite increments the native byte counter only by bytes actually consumed. An immediate result reports the entire encoded length. A partial write copies the exact remaining byte suffix into one uninitialized native backing store and calls Write with skip_try_write=true; no second try-write occurs. The returned byte result then includes the synchronous prefix.

The unique native backing token moves only to the actually returned WriteWrap. Native result-pointer retirement precedes disposal of an untransferred backing token. Ordinary init-hook exceptions preserve accepted native writes and their backing. A failed error Set keeps its actual pending reason and original result bookkeeping.

The IPC branch continues to require a real HandleWrap unwrap/GetHandle owner. Non-IPC streams ignore object send handles exactly as the source does. The existing concrete FileHandle returns UV_ENOSYS. No incomplete public FileHandle constructor is published.

## Focused controls

Eighteen authored declarations cover the flat-view contract and an actual VM rope; all four dispatch entries over a physical FileHandle; exact ASCII/LATIN1, UTF8 and UCS2 bytes; immediate success/error and partial-write accounting; asynchronous backing ownership through logical Dispose and final native retirement; input-root release; threshold and long-UTF8 capacity; empty writes; non-IPC send objects; failed error Set; ordinary init-hook throw; and absent/dead receiver guards.

The fixture reuses actual FileHandle, Environment, native request, managed backing and completion owners. Native virtual probes select and observe the write/try-write algorithm; they do not qualify a production socket/IPC backend or allocation retry/bootstrap policy.

No compiler, parser, formatter, metadata query, native runtime, Node capture or source generator was executed. The declaration count is source text, not observed native metadata. Independent peer review and Root's later native admission remain outstanding.

## Remaining work

Vector Writev and its full mutable encoding pipeline, external_stream, complete AddMethods/FileHandle publication, the concrete IPC HandleWrap owner, and production Environment/trace/allocation/event-loop embedding still remain. This packet does not switch the default backend, qualify whole-application startup, or remove the production bridge.
