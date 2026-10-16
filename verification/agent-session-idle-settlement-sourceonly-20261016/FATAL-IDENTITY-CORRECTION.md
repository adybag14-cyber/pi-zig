# Source-only correction after Root review of 2b919663

Root found that classifying a fresh captured JavaScript native-allocation
exception with `Engine.nativeAllocationError` before rethrowing its exact
reason could convert it to `error.OutOfMemory`. The async adapter would then
allocate a replacement reason. That is an identity gap in the initial source
checkpoint, not a qualified runtime result.

The correction consumes the initializer `0a7607` / event-bus `e02a` trusted
boundary pattern locally in these two leaf modules. No shared helper, C,
Engine, fixture, or Root file is changed.

## Boundary and finalizer order

1. A direct `error.OutOfMemory` with no existing reason remains an error union.
   Settlement attempts already-entered finalizers and propagates that union.
2. A captured JavaScript exception is retained with `JS_DupValue` before any
   fallible cleanup. The local trusted boundary invokes
   `rethrowRecognizedAllocation` before host classification. A fresh private
   reason is marked and rethrown as that exact JavaScript value.
3. Settlement catches only this trusted rethrow at the native adaptation
   boundary, attempts the entered Source finalizers, and rethrows the retained
   original with its uncatchable state restored. A cleanup getter, iterator
   return, idle callback, or later native failure cannot replace that original
   fatal reason.
4. Resumed rejected values are checked against the invocation's private START
   generation before ordinary Source rejection handling. An already
   uncatchable historical reason stays fatal without being reclassified as a
   fresh tag. Historical ordinary tags and guest lookalikes are not marked.
5. The control adapter uses the trusted boundary before `failureSince`.
   Therefore an exact tagged JavaScript reason escapes directly instead of
   being converted into an allocation error union.
6. IteratorClose uses the same trusted boundary first. If closing introduces
   a fatal reason while handling an ordinary primary error, idle finalization
   is still attempted, and the exact fatal close reason survives that cleanup.
   Ordinary guest close errors remain suppressed; ordinary idle-finalizer
   failures still override ordinary primary errors as in Source.

## Capture ownership and restoration

| Location | Owned references and transfer |
|---|---|
| Settlement body catch | `retained = JS_DupValue(captured_exception)` owns one reference independently of the Engine capture. Its defer releases exactly that retained reference after returning or rethrowing. |
| Fatal-finally path | Owns another duplicate for the entire finalizer attempt. Cleanup may replace the Engine capture freely. `throwFatal` transfers a new duplicate to `JS_Throw`; `Engine.checked` restores the same object as the Engine capture. The local duplicate is then released. |
| IteratorClose entry | Saves the existing owned Engine capture, temporarily replaces the field with a duplicate of the primary reason (or null for direct OOM), and owns the iterator and next-function references through their existing defers. |
| Ordinary close completion/failure | Frees the temporary/current capture and restores the saved owned Engine capture without duplicating or releasing the saved reference. The primary guest reason remains independently retained by the body or suspended frame. |
| Fatal close completion | Keeps the newly fatal Engine capture and releases the saved old capture exactly once. It must not restore the old primary over the fatal close reason. |
| Fatal close plus idle failure | `closeFatalAfterIdle` duplicates the close reason before attempting idle. It rethrows that exact retained close reason afterward; its defer releases the retained reference. |
| Resumed input | Input is borrowed from the VM frame. A fatal path duplicates it before cleanup; a normal thrown Action contains its own duplicate. No borrowed input is consumed or freed. |

Only a freshly recognized private tag or a preexisting uncatchable reason
enters `throwFatal`. Guest `name`, `message`, ordinary historical tags, and
lookalike objects do not establish trust.

## Focused controls prepared, unrun

`src/native_sdk_idle_settlement_identity_test.zig` adds four tests, exposed
through `build-native-sdk-idle-settlement-identity` and
`test-native-sdk-idle-settlement-identity`:

- Fresh synchronous control failure and fresh resumed control rejection.
- Fresh synchronous and resumed settlement failures, each with an entered
  emitting-flag finalizer that itself throws.
- Deferred rejection surviving both iterator-return and idle failures; a new
  fatal IteratorClose reason surviving idle failure.
- A preexisting uncatchable historical reason; ordinary guest lookalikes and
  historical ordinary tags retaining Source finalizer override behavior.

The owned test injector calls the actual Engine native-allocation marker and
retains the exact value before throwing/returning it. The tests compare the
final Engine capture by strict identity to that retained value, inspect its
uncatchable state, and assert entered cleanup counts. They do not infer native
trust from guest names/messages.

These are component controls over the actual installed method bodies and
caller-controlled receiver collaborators, not a full ordinary-class or
application-route qualification. They have not been compiled, syntax checked
with Zig/Node, or executed. All old immutable goldens and tests remain intact.

`native_qualified=false`, `full_factory_qualified=false`,
`full_pi_qualified=false`, `public_activation=false`.

## Second Root review: the outer Source-catch boundary

Root's review of `8838bcdd` found that an error thrown inside the existing
`resumeBody` catch could escape without the trusted boundary. In particular,
an ordinary deferred callback failure could enter Source cleanup, whose idle
finalizer then throws a fresh tagged native reason. That new fatal reason was
outside the catch that originally handled the primary failure.

The correction splits the callback into two ordinary Zig functions:

- `body` snapshots the actual invocation generation and calls
  `bodyWithSourceCatch`. Its catch invokes `trustedBoundary` first, then
  `failureSince`. This boundary includes failures from Source-catch cleanup,
  idle resolution, and reading the resulting Action.
- `bodyWithSourceCatch` retains the existing Source try/finally adaptation,
  exact-original fatal retention, and ordinary guest override behavior.

This adds no JavaScript function, Promise, await, or job. There is still one
native async invocation and the original await stages. All existing retained
reason references remain owned by their existing defers. The outer wrapper
borrows the invocation state and consumes no reason: a recognized captured
reason is duplicated/transferred by the inherited rethrow helper, which lets
the exact JavaScriptException escape before any replacement-producing host
classification.

Two additional prepared tests bring this target to six tests:

1. An ordinary synchronous deferred callback failure enters the Source catch;
   the idle finalizer throws a fresh real native-allocation reason. The final
   Engine capture must equal the retained native reason and be uncatchable,
   with idle cleanup called exactly once.
2. The idle finalizer arms the owned FailingAllocator's next host allocation.
   The next allocation is the fresh Scope used by `async_body.action` in the
   Source-catch return path. The test requires an induced allocation failure,
   an uncatchable private native reason identical to the Engine marker, a new
   in-boundary tag, and complete allocator byte balance after Engine teardown.

These controls remain uncompiled and unrun. Existing immutable Source fixtures
and their assertions are unchanged. No C, Engine, shared helper, or Root edit
was made, and no Zig, Node, source-capture, or native job ran.
