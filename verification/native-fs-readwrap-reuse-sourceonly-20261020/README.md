# Native FS ReadWrap raw span and request reuse

This source unit adds the real raw-buffer read and cleaned, dequeued request reset operations to the existing shared UV service. It preserves one service, request allocation, embedded event, FIFO and stop/join owner. It does not assemble FileHandle, its native callback template or its freelist.

The final applied source is the exact v3 proposal `625A46DF`: five C edits and three header edits. Original C `FF046966` and header `A8E758C4` are retained in full. Forward and inverse verification is recorded separately. The v1 and v2 proposals are preserved as history, not intake instructions. V2 missed the embedded event's `in_use` admission reset; v3 clears that field only at actual FS dequeue under the event mutex.

Every dequeued event ticket owns its own native request and service entitlement. After Reset, an older ticket is release-only: the slot's mutable completion information and FIFO link can belong to a new operation at the same address. The old release path does not inspect or alter those mutable fields. Reset requires actual completion, dequeue and cleanup; it does not allocate a replacement request or event.

Raw read borrows the original native span. Its consumer must retain the backing through actual completion and cleanup and through the later FileHandle delivery/EmitRead use. An immediate failed raw admission supplies no event or invented callback; the original FileHandle ReadStart ignores that Dispatch status. The existing leased-read APIs retain their own original caller policy.

The fourteen new controls use actual files, native storage, the shared service and the real event tickets. They cover queued-reset exclusion, multiple outstanding tickets for one reusable address, old-ticket release after new queue insertion, FIFO preservation, raw/lease transitions, explicit request-owner retirement, cancellation/stop and native operations with an actual JS exception pending and heap allocation disabled. Original TCP12 and FS14 test roots are unchanged.

Independent source peers are retained in `peers/`: Root and VM closed the v3 protocol, VM closed controls 1/4–9, and Modules closed Fixture/File/Buffer, controls 2–3/10–14 and the eight-line build proposal. Modules also closed the original ReadStart/ReqWrap source order. All closures are source-only.

`build-intake.json` proposes one install-only `build-native-node-fs-readwrap-reuse` target against the retained current Main build hash. It reuses the same network library, QuickJS and UV include path. SDK and Main build files were not changed by this unit. There is no run edge.

No compiler, native test, Node, generator, formatter or AST check was executed. Complete FileHandle construction, callback routing, native trace, backing-store retry/GC policy and bootstrap integration remain separate units.
