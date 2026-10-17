# Canonical private require/eval assembly — source only

This is a new assembly review unit after closed65c and corrected73b. Their
earlier reviews do not qualify this change. No Main, C/H, Engine or shared
helper changes, formatter/AST/compiler/runtime/Node jobs, default selection,
Source expected rewrite or full public createJiti claim occur here.

`native_jiti_core_graph.createCanonical(engine, cells.CanonicalBindings)` is
the canonical composition entry. The old65c host API remains for compatibility
and historical controls, unselected and not upgraded into a completed builder.
Canonical CoreDependencies/FrontendDependencies/RequireDependencies contain
only actual external inputs: no caller-supplied require/core/eval counterpart
slots, no fake callback, partial module namespace, registry or identity alias.

## Transaction and actual dependency

The canonical entry suppresses diagnostic formatting before declaring native
callables or allocating. This prevents OOM error formatting from running Source
getters before linking. `linkCanonical` also guards its direct host entry.

1. Declare the real hard-wired createJiti/evalModule bodies using the already
   charged/marked private cells. They remain unavailable to public exports.
2. Preflight actual borrowed dependencies without guest property reads/calls,
   check the original Engine/phase, and require matching shared module imports
   across core/frontend/require: debug, transform, resolver, actual path and URL
   functions. Strict equality is noncoercing. Real module-lifetime resolver regex
   constants remain the caller's actual shared objects.
3. Enter linking phase, then call unchanged reviewed
   `native_jiti_require.create(engine, actual Inputs{eval_module=record.frontend})`.
   The actual declaration is ordinary/constructible jitiRequire length3. Its
   own native callable constructor reserves/charges its native state/root array,
   duplicates every actual capture and traces/frees them through VM GC. No
   function from another graph is used as the frontend or require counterpart.
4. Stage complete actual core/frontend import values in fixed local structs.
   Both get the SAME newly created require; real frontend/core counterparts are
   the record's declarations. The existing fixed record slots were precharged.
5. Duplicate those JS roots without allocation, then perform a nonfallible field
   commit and transition to linked. Release the local owned require reference;
   the committed record owns two actual import edges, while require captures
   this exact frontend. This creates the real module cycle, not a dummy facade.
6. Run the original actual platform initializer after complete linking. Only
   successful initialization permits owned export access/public factory calls.

Any construction failure restores declared phase and leaves import records
uncommitted/unpublished. Native callable failure cleanup owns its partial
allocations. If function/prototype cycles remain after a late failure, they
remain VM-visible and charged until actual collection. A failed initializer
retains the existing failed phase; the canonical producer drops its owned graph
root. It never caches or exports partial namespace/functions. OldSource callback
names, arity, constructibility, receivers, raw values and error flows are kept.

Only three existing product paths change: cells, canonical graph entry, and
the single core_factory local `ignored` -> `ignored_result` rename requested
by Root's AST finding/29e6f8f5. It has no Source behavior change. The require and
resolve dependency files are included byte-identical to closedca974 and Main:
BD29C7EDB624BEE507E667F03733A1FEA12BF292C39335F1C8CD5426368FE731 /
AB6A7BC912E5FB74B07CA0A1AF01316FFD0530B493C3BF89E8686CA5BE0C2712.
Root intake must retain its existing equal copies rather than replace them.

## Prepared controls and limits

Six native controls require completed actual module namespaces. They use the
canonical hard-wired entry, never generic Bodies injection: exact same require
identity in both imports with captured frontend identity; missing dependency
preflight without commit; mismatched real shared imports; exhausting the actual
combined memory ledger before require construction, then retry after releasing
only the owned reservation; retaining only the actual core across GC, checking
the actual cycle survives, then checking charged storage releases after final
root drop. No output/expected data is created.

The shared memory ledger also includes VM allocations and context-lifetime
class registry storage. A false equality assertion against a preconstruction
baseline is deliberately avoided; strict release after dropping the live cycle
is checked. This does not claim all VM/class-registry storage or Graph2 pinning
is reclaimed. Full allocator-position failure, teardown/owner absence and actual
Source caller/cycle execution remain native qualification obligations.

Independent review of first bbf7 found one concrete entry blocker: an actual
VM exception already pending could survive declaration/link/platform success
and let the record become ready. The Source producer/AF/shared runtime provides
no universal clean-entry guarantee. The source successor therefore captures
that actual event under balanced diagnostic suppression before allocation in
createCanonical, before host-record/preflight work in direct linkCanonical,
and before host-record/phase/platform work in initialize. No input flag or
historical diagnostic slot is used to infer this current event. Capture keeps
the exact reason without allocation/coercion, phase mutation or platform call.

The sixth control exercises all three direct entry boundaries with an actual
non-OOM pending VM event, verifies exact captured reason, zero ledger change,
balanced diagnostic count and no platform call. It then initializes the same
linked graph successfully after test-driver event consumption, proving the
entry guard did not mutate the initialization phase. The supplied actual
platform function is observed by the original delegating Proxy input; it does
not fabricate a return value. bbf7's original prepared manifest is retained in
authority as the immutable prior source seal, not rewritten into a pass.

Missing real namespace/policy inputs stay declared. In particular the actual
nativeImportOrRequire declaration wrapper remains required by the frontend;
this transaction does not substitute one. Public package wrapper/default native
transformer, Source module cache wiring, remaining resolver dependencies,
esmEval and Graph2 lifecycle/interop qualification remain separate. No bounded
API12a compiler is relabeled as full Babel/default behavior.

An explicit followup blocker is the historical-data flag test in old65c
eval_frontend.importFallback. Root requested a separate finite correction and
causal review after this assembly seal/review. This packet does not treat the
historical frontend as whole-parity qualified, or silently edit it here.
