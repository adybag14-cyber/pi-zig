This narrow successor is based on the exact32a785a0 default queue/tee source
checkpoint. It does not include the later public prototype/BYOB/iterator graph.

The genuine Response ownership OOM diagnostic at116/233 failed the first host
allocation in Scope.own via Scope.get(owner,"agent") in readable continueValue.
Its tee continuation catch then attempted the same allocating getter, so
permanent host allocator failure prevented it from reaching either branch's
actual queued readers. Rejecting only the ignored continuation owner stranded
the module promise. Native allocation generation/tag were2/2; all bytes were
freed at teardown, but the operation returned JavaScriptPromiseUnsettled. The
terminal/fullpost0 diagnostic is retained in evidence
web-response-debug-test-oom-diagnostic-20261015.stderr.log.

The failure path now retrieves rooted private references with direct C-backed
JS property calls, validates actual native class IDs without appending Scope
roots, and errors both genuine branches plus the source's pending reads/closed.
It rejects the real cancellation owner and preserves the primary error reason
if a cleanup allocation fails. Normal non-OOM tee behavior stays unchanged.
No engine exception classification or test normalization was added.

test-native-readable-host-oom arms a real permanent FailingAllocator from the
actual native byte source pull in a queued microtask after enqueue/close but
before the already-fulfilled source read's tee continuation. It awaits both actual
tee readers and requires trusted OutOfMemory plus all host bytes freed. This
target and the exact Response116 diagnostic still require matching native
compile/runtime qualification; only Zig AST/fmt and diff checks have run.
