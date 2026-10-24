# StreamBase Write / WriteBuffer source packet

Status: authored source only. No Zig parser, compiler, metadata query, native runtime or Node capture was executed. Main and the prior sealed JS-dispatch packet remain unchanged.

## Implemented

The packet adds the genuine WriteWrap instance-template brand and original provider 52, two independent request/native slots, native SimpleWriteWrap creation, request completion and unique backing-store transfer. The default WriteWrap template has no own ShutdownWrap fields. Existing Shutdown construction and its missing-binding timing are preserved.

StreamBase::Write now accounts all attempted bytes before DoTryWrite, preserves original totals after partial writes, bypasses try-write for the two original conditions, uses the actual optional instance-template path, restores trigger scopes in original destruction order, and transfers the BaseObjectPtr into the returned result. Synchronous failures clear the request slot before that returned pointer retires. Early error-property failure returns EBUSY with zero result bytes and leaves the stream error uncleared.

WriteBuffer enforces the original request-object CHECK and Uint8Array predicate, uses actual native view data and byte length, preserves the original intrinsic TypeError/code Set behavior, and updates the shared Int32 result fields before retiring its result pointer. The optional IPC branch requires a concrete HandleWrap owner; FileHandle uses the original non-IPC default. FileHandle::DoWrite is the retained Node UV_ENOSYS body, not a successful fabricated filesystem write.

Write completion selects the live native listener and reuses the actual shared reporter, including CustomBufferJSListener. Ordinary callback throws still reach Dispose. Request backing storage survives logical Dispose until the final native pointer retires. SimpleWriteWrap's reverse C++ base destruction order is preserved: AsyncWrap/BaseObject retirement precedes the WriteWrap backing-store destructor.

## Controls

Twenty focused controls cover real template shape, physical FileHandle descriptor survival and ENOSYS/counters/trigger behavior, synchronous and asynchronous request lifetime, full/partial/failing try-write and bypass conditions, invalid-view predicates and result-state preservation, intrinsic error construction and an observable code setter, error-set throw/false branches (including an accepted async request that must survive a later error-set failure), ordinary init-hook throws, live forwarded/CustomBuffer completions, disabled JS completion, default native template creation, unsigned/Int32 conversion boundaries, backing ownership, receiver guards, and WriteBuffer's async result publication.

These are unexecuted control sources. The test fixture reuses current Main's concrete Environment, FileHandle, request queue and allocation observations. Native probe callbacks only exercise branch/lifetime contracts in controls and are not production adapters.

## Intake

The exact successor patch and inputs-and-outputs.json cover twelve targets. Four successor inputs come from the accepted first packet: StreamBase, FileHandle, JS dispatch, and build.zig. Six further source inputs are current Main. Two files are new: the write owner and its focused controls.

Apply the source successors after the first packet. For build.zig, compose the 1,692-byte build-addition.zig.txt with the catalog's combined Module/first-packet build rather than replacing that build with this standalone projection. The new install-only target is build-native-node-stream-write, filtered to the twenty source controls. Root owns all integration and native admission.

## Remaining work

Vector/string writer callbacks, external_stream and complete AddMethods/FileHandle publication remain required. A real IPC HandleWrap owner is independently required for an IPC stream. The public FileHandle constructor gate is unchanged. This packet does not qualify application startup or production Node bridge removal.
