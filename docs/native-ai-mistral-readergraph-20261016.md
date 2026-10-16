# Direct Mistral reader graph successor

This source-only successor preserves product 24290770c8310b0a005712d2af990fa5e97cac4e
and its actual74 proof. That product compiled successfully and passed 73 tests.
Its strict Source30 test passed all 20 Google/Vertex cases, then failed the
Mistral thinking/tools intermediate snapshots. Native thinking_end,
toolcall_start and the first toolcall_delta observed final arguments and usage
earlier than the unchanged genuine SDK observations. Full Source30 remains
unqualified; the shared HTTP/Immediate/timer/EventStream scope is recorded
separately with full zero-drift inventories and exact binary identity.

The pinned upstream readMistralEvents accepts Response.body. On first next it
gets the reader, constructs TextDecoder, creates its abort callback and installs
the optional listener before entering try/finally. The generator directly
awaits reader.read, destructures done and value before checking abort again,
decodes and yields parsed events. Finally removes the listener, awaits cancel
while suppressing guest cancellation failures, then releases the lock while
suppressing guest release failures.

The previous standard native path instead awaited the raw HTTP byte iterator.
The custom-fetch path acquired a genuine reader but inserted an ordinary
Promise-producing byte iterator between that reader and the VM generator.
This successor removes that successful-body iterator. Standard HTTP bytes now
feed the genuine shared byte ReadableStream; custom fetch forwards the actual
second Response.body observation and options.signal argument. Both enter the
same native VM generator with direct reader Await and direct cancel Await in
finally. The fetch adapter retains only response/header observations and its
separate response.text error-body continuation.

Mistral facade creation independently prepares the genuine Web/Body stream
prerequisite. getReader precedes TextDecoder and listener setup; failure during
those pre-try operations does not enter finally. Abort callbacks invoke the
live reader.cancel method and attach the Source catch handler. The native
owner keeps guest finally suppression separate from trusted host allocation
failure and interruption. There are no cloned event snapshots, sleeps,
synthetic drains, timer ticks or extra reader Promise wrappers.

Original Source30/60/20, Fetch8, framing8 and live4 expected packets and tests
remain unchanged. The first proposed gate is the exact existing 74-entry
Source30/shared scheduling cohort; the eight genuine custom-fetch traces in
the existing Source20 suite are an additional required compatibility gate.
Those traces include normal reads, reader failures, cancel rejection and abort
cleanup. Strict Source30 and full custom-fetch qualification remain pending.

Only source inspection and git whitespace validation have run. Zig formatting,
AST checks, compilation and runtime are deliberately held while Root's Async25
pair owns the serial lane. No C, Engine, shared HTTP, fixture or snapshot change
is part of this successor. Full Pi, factory/application parity, hosted profiles,
release and public activation remain false.
