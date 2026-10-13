# Native session control and shared AI cleanup - in progress

This private implementation ports 19 original AgentSession idle, cancellation,
disposal, queue-mode, settings and transcript-control methods, plus pi-ai's
registerSessionResourceCleanup and cleanupSessionResources. The cleanup registry
is shared within an Engine and retains original ordinary function construction,
live Set iteration, unregistration and AggregateError callback identities.

The e6220e1 fixture contains 33 genuine upstream factory sessions. It exercises
shared idle promises and the ambient Promise constructor, live callback reads,
real Agent queues, cancellation order, disposal and cleanup callbacks, settings,
real transcript projection, original method/function descriptors and aggregate
errors. Unexpected TypeErrors reject capture; only the deliberately false abort
controller compares the built-in error category. The first caller left fake
compaction owners active after abort and produced unsettled top-level await;
that negative is retained. Corrected caller-owned controllers clear their own
fields, and the unchanged original methods then complete all 33 cases.

First Windows Debug execution completed 10/12 selected tests. The complete
33-case comparison and explicit garbage-collection test passed. BOTH allocation
sweeps failed with SwallowedOutOfMemoryError and remain unresolved. They are
retained unchanged, with first-failure allocator stack diagnostics added for
investigation. This is not native control qualification. ReleaseSafe and
cross-platform validation are pending.

The failed Debug run retained full 4811 source and 19546 compiler file preimages
and zero-drift posthash receipts. Original source/runtime/Node full posthashes
show zero drift over 1945/31064/1774 files. Local diagnostic retry was refused
before launch when available RAM fell below the authorized admission threshold.
The private candidate workflow provides bounded hosted diagnostics with the
same 33 cases, both allocation sweeps, 120 second test limits, 10000 ms host
awaits and 300 second runtime bound; cold compilation is separately bounded at
1320 seconds. A run is successful only if all 12 selected tests pass.

No public AgentSession factory activation, automatic provider-resource cleanup
integration, full class assembly, bridge removal or complete Pi certification
is claimed by this component. Successful full model runs and the remaining
ordinary class/runtime dependencies still need integration and validation.
