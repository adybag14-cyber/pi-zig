# Native tracing platform and original dependency packet

This is a source-only production proposal in the modules-I/O worktree. It supplies concrete native dependencies for the existing Agent/controller drafts and the separately reviewed clock and C ABI units. It does not claim compilation, executable linkage, native execution, complete tracing assembly or target qualification.

## What is supplied

Ten production files are frozen with byte-identical snapshots in `production/` and listed in `production-proposal.json` (88552C5060C2132977BF4312BD1E12F22221E1A188D53074F5D33B89EE02BFC9):

- `native_node_tracing_platform.hpp/.cpp`: the selected original V8 Mutex/LockGuard bodies with their actual `absl::Mutex` member, signed debug level and real V8 dcheck diagnostic owner.
- `native_node_tracing_support.hpp`: a finite replacement of the previously undefined assertion adapter with the real Node assertion record/call, current synchronous diagnostic context and original abort guard. Every byte of the prior Node uv mutex/condition/ContainerOf suffix remains unchanged.
- `native_node_tracing_loop.cpp`: the complete selected original CheckedUvLoopClose failure sequence, handle walk and native symbol diagnostics.
- `native_node_tracing_recorder.hpp/.cpp/_win.cpp/_mac.cpp`: the original non-Perfetto ETW/signpost Recorder and SystemInstrumentationTraceWriter bodies.
- `build_native_node_abseil.zig` and `build_native_node_tracing.zig`: concrete archive recipes that consume real shared owners.

The original Abseil cohort under `vendor/node-v24.13.0/abseil-cpp` contains the 349 entries of Node's pinned abseil.gyp, its full Apache license and three additional literal transitive headers: 353 unchanged original files. The build recipe preserves all 110 original C++ source entries in original order. The literal source graph resolves 1,420 Abseil include edges. It is a lexical source graph, not an observed preprocessor graph.

The original V8 ETW provider declaration and V8 license are retained under `vendor/node-v24.13.0/v8-tracing`. The provider GUID, real TraceLogging registration/unregistration and original event fields are preserved.

All Node/V8/Abseil originals use Node revision `def0bdf8abee441cfcbf793a8dc24a6f3b899573`. Existing pinned originals were reused before bounded source acquisition. Complete acquisition plans, successful receipt rows, full authority bodies and original notices are retained.

## Concrete Windows SDK and toolchain selection

The build recipe consumes only the contained, unchanged Windows SDK **10.0.22621.0** `TraceLoggingProvider.h` at:

`verification/native-node-tracing-platform-sourceonly-20261020/authority/windows-sdk/10.0.22621.0/shared/TraceLoggingProvider.h`

The 294,943-byte original has SHA-256:

`C060AF7E8703386736C651A62686908D509B8B9CB627D898D72A4CA6506901A4`

The installed Windows SDK path is recorded as provenance. It is not an ambient include directory or build input. The contained directory holds only this SDK header. Its actual `evntprov.h` include and Windows declarations resolve to the already contained pinned Zig 0.16.0 MinGW headers. No SDK header body is patched and no fake ETW implementation is supplied.

The original MinGW Abseil selection is retained: its own StdcppWaiter serves the original Abseil synchronization algorithm, and its thread identity uses the original pthread key path. The build does not replace Abseil Mutex with std::mutex or force another waiter/thread-identity mode. Pinned Zig source classifies a MinGW pthread link request as libc, so the existing bundled C runtime owns that dependency.

The SDK's Microsoft extensions, metadata sections, compiler built-ins, import libraries and real provider behavior still need actual compiler/link/runtime validation. Source inspection does not establish those results.

## Source verification and retained negatives

`source-body-proof-v2.json` (69154F80BF1982B21A35018964F1B59D110008235B382FC261163A557354378D) records 41 selected original-body comparisons. Its pinned checker is `source-body-audit-v2.py` (B05D00CD609C9E4496210F7DE81F2CABAC9B8CEAFBFD70FA2ECCDBBE6A75DABB). It preserves string/character literal tokens, drops comments/whitespace and applies only explicitly listed name, allocator, feature and diagnostic mappings. It does not invoke a C++ parser, preprocessor or compiler.

Root independently read the production slice and replayed the complete read-only checker prefix, recomputing all 17 input pins and reproducing all 31,192 proof bytes and 41 equal comparisons. That is an independent source review result, not native validation. The optional `replay-source-body-proof.py` repeats the pinned construction without its output write.

Earlier local auditor negatives are retained. The first body check accidentally anchored Mutex::Lock inside RecursiveMutex::Lock and was corrected to a full declaration anchor. The first source-cohort metadata auditor failed to parse because a local variable used Python's reserved `nonlocal` keyword; no body ran and no production was edited by that failure.

Root's acquisition review found a path-schema mismatch when indexing the three added headers. The first fifteen homogeneous batches use vendor-relative paths; the five-file mixed closure receipt uses worktree-relative paths. `acquisition-path-schema-bindings.json` (51307A7DBDB591FFB5BDCAA1ECEA95F2B5CD336E2327F8C11AA4B5003E32BCE7) binds all 353 files to exact successful rows, URLs, sizes and hashes, using one explicit fixed-prefix removal for the three Abseil rows. The original receipts and manifest remain unchanged.

`instrumentation-debug-and-inherited-constructor-proof.json` records the finite responses to review questions. The instrumentation macro is required only by the selected Recorder header and is passed to each selected Recorder source. The inherited odd ScopedLock-from-ScopedUnlock initializer is byte-exact to original node_mutex.h; the selected Agent/buffer/writer contain 20 ordinary Mutex lock uses and no ScopedUnlock consumer. No speculative fix is made and no template-instantiation outcome is claimed.

Zig optimize Debug is not asserted to select the original V8 Debug configuration. Original V8 GYP explicitly defines DEBUG; the new native recipes preserve the existing C++ policy and do not add DEBUG, _DEBUG, NDEBUG or OFFICIAL_BUILD. The old core/controller drafts retain their explicitly bounded non-DEBUG DCHECK selection. Complete Debug parity and compiler predefined macros remain outside this source result.

## Build composition

`build-composition/proposal.json` (39CD6DFEB20FD08C0A8F4899647195E9DEA7DEF968C0DF291BEE05BFB4FB4856) contains a single inverse-proven 22-line insertion against the immutable Main checkpoint `f4c6abbc62ecd18b72ec50ab8fa206fe1664909f`. It has not been applied to Main.

The proposed `build-native-node-tracing` step installs three new archives: Abseil, the shared tracing diagnostic owner, and tracing. It passes the existing native-memory and network/libuv compile objects into the tracing recipe. It adds no execution edge, test root, source generator, default process startup, global QuickJS link or foundation catalog change.

The source declarations total 123 new C++ units plus one C unit on Windows and 121 C++ units plus one C unit on Linux. These include the 110 original Abseil units. They are source declarations, not observed object counts or metadata counts.

The diagnostic archive is the one proposed owner of existing native_node_diagnostic_context.c plus the separately reviewed real V8 fatal and clock diagnostic sources. The network owner continues to own Node's assertion implementation, and the existing native-memory owner continues to own its allocation TLS. The eventual final executable must also link the existing pi-quickjs engine_abi.c memory retain/release/reserve/release owner. No stub callbacks or second owners are supplied.

## Remaining concrete assembly work

Source intake still needs the frozen clock/API commits, provider fatal commit and ten preexisting Agent/controller/core/buffer/writer draft files. This finite platform review pins those drafts without asserting full algorithm qualification for them.

An actual executable link consumer remains to be admitted. Installing static archives alone cannot establish symbol resolution. Before the existing diagnostic-context test shares the tracing diagnostic archive in one binary, its direct context-C compilation must be replaced with a link to that sole owner.

Process Agent creation, retained memory ownership, publication/unpublication, original category-registry lifetime, trace-state observers, environment notifications and CLI writer selection remain separate source work. The reviewed 29 C APIs do not yet expose the complete AddTraceEvent/metadata/duration and observer lifetime operations needed by all filesystem, AsyncWrap and module event owners.

The genuine V8 fatal owner retains its original uninstalled callback state; process-specific stack/fatal hook installation remains explicit. The preexisting private V8 ring-buffer factory declaration has no selected definition, and the actual Node Agent uses its own NodeTraceBuffer. Broader V8 ring-buffer admission would need its original implementation.

Darwin Recorder/clock/Abseil source is retained. Complete Darwin Agent assembly still needs admitted Darwin network and native-memory owners; the Main proposal only creates the archive target when its actual current owners exist.

## Scope and preservation

No Main file was edited. No compiler, preprocessor, native test/program, Node reference or project source generator was executed. Only source acquisition/copying, source edits, hashing, lexical checks and review metadata were performed.

Frozen clock/API/fatal production pins remain unchanged. The seven preexisting tracked CommonJS/object-spread edits and all earlier unrelated dirty/untracked work remain preserved. New production and original vendor bytes are frozen for finite independent peer review; no commit or native lease is implied by this packet.
