# Private original uncaught-handler declarations

This packet implements the complete exceptionHandlerState, capture setter/getter, original noop, and fresh anonymous-handler factory from retained Node internal/process/execution.js. It keeps their mutable ordinary state, evaluation order, live process property reads, exact strict comparisons, original catch scope and actual fatal completion behavior.

The production body is projected-v2/src/extensions/native_node_process_uncaught_handler.zig. The prior draft is preserved. Its sole correction requires the original Uint32 abort-toggle type; the evidence and exact inverse are retained. The owner is private, traced and charged, with exact-input cache acquisition and retained callable lifetime. No process field or public module is published.

## Required assembly

Twelve required bootstrap inputs remain explicit. Their shape and repeated-acquisition equality checks do not authenticate their origin. The accompanying dependency handoff identifies the actual current Environment alias facility, the missing shared abort-toggle owner, the distinction between native Environment.emitAfter and the original JS wrapper's additional pop, canonical process/require/timers and error identities, and the still-unimplemented native Message/report/exit path.

The 36 source controls use the actual VM, process installation, argument-error bootstrap and string-error registration. The async-hook and require/setImmediate callbacks and the Uint32Array in the fixture are explicit observation probes. They test declaration-body semantics, not authenticated scheduling, Environment alias acquisition, native exit, or full uncaught-exception assembly.

## Source changes

Two new source files and one 1,386-byte additive build hunk are selected. The full build projection is based on frozen d3a9, with an exact raw inverse. Future composition must apply the insertion to its current accepted build, not replace a newer build with this standalone projection. The install-only target is build-native-node-process-uncaught-handler, filter native uncaught handler, explicit executable stem native-node-process-uncaught-handler (the standard test PDB remains test.pdb).

No Zig parser/formatter, native build, metadata query, runtime, Node capture, source generator or candidate program was executed. Actual metadata and runtime results are unknown. Main and all earlier packets remain unchanged.
