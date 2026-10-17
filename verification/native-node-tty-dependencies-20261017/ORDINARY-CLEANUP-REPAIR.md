# Socket-local ordinary exception ownership

Original negative successor: 59764cc9689a43d3df9c4e144ee26602b116bd05.
Its 13-path proof/manifest and the earlier e570/9a34 authorities remain intact.

Body source review closed its actual RootBfb producer reuse for fatal B/no-C,
then identified a distinct ordinary case: a live lookup returns a sole native
holder A, a later lookup throws ordinary B, and A's cleanup throws C. RootBfb
retains current fatal producers, while an ordinary B needs separate ownership
before temporary/receiver/provider cleanup. Shared Scope/Engine are unchanged.

native_node_socket_scope is local to this Socket/cache unit. captureUnwind is
registered AFTER the Scope defer at each fallible Socket scope, so it owns the
actual JavaScriptException reason before any temporary root is released. Its
Cleanup keeps the selected current reason outside both VM/Engine slots, keeps
diagnostic DATA separate, snapshots both new cleanup slots before discarding
either owner, drains after each destructor, preserves first ordinary B against
ordinary C and promotes only the first actual fatal cleanup event. A marked
historical diagnostic never enters current-event classification. A raw fatal
finalizer is recorded through the actual Bfb producer before another root can
produce a later event. A newly raised ordinary cleanup event stays pending;
successful code cannot turn it into historical diagnostic DATA.

The namespace-local native_node_socket_function implements an ACTUAL ordinary
callable/constructor with name, length, own prototype, configurable/writable
nonenumerable prototype.constructor, normal call receiver, new-target prototype
lookup, constructor return rules, GC-visible captures and charged native state.
It uses actual Bfb checkNativeEntry/NativeInvocation/leave over the WHOLE invoke.
The local Scope also owns the constructed receiver and returned value, so an
ordinary B remains protected while the receiver's own native roots retire.
This replaces direct use of Root's generic function only where the new local
ordinary escrow is needed; it neither aliases a typed Kind wrapper nor changes
Root's callable/shared policy. RootBfb remains a required retained prerequisite.

The same local creator also preserves the pinned net.js descriptor shapes for
the admitted properties: anonymous assigned ordinary methods retain empty names;
the pending accessor's descriptor method is nonconstructible; ordinary get
function expressions retain a prototype; named protoGetter callbacks keep their
names. Configurable/enumerable flags follow the retained Source definitions.
The prepared original/native control checks these exact admitted members. This
is source inference from net.js plus ECMAScript's identifier-only assignment
name inference, not a new Node capture:
https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-assignment-operators-runtime-semantics-evaluation

The provider-cache inner factory now uses the same local Scope for net/holder
roots, with an additional captureUnwind placed AFTER its provider defer. This
protects B before both actual provider roots are released on rollback. Bundle
keeps its own net reference when that root transfers to the private cache.
Socket State, adopter registry, callable state/captures, cache Bundle and shared
completion owner have native budget charges paired with their actual finalizers.

The projected Hub additionally brackets each NEW Resource.poll VM delivery in
the same actual Bfb invocation producer, with balanced diagnostic suppression
and success/pending normalization before later resources/checkpoints. It keeps
the prior Task completion path unchanged. This is a projected Source delta only;
no live/shared Hub file is edited in either checkout.

New causal native controls (all UNRUN):

* Install actual native process and stream namespaces, temporarily replace the
  genuine streams.Duplex export getter, return sole native witness A, then throw
  B from A.prototype. A's actual finalizer emits ordinary C, marked current fatal
  C, or a genuine one-byte FailingAllocator OutOfMemory followed by Root's actual
  fatal OOM producer. Assert exact B/C identity, one lookup/finalizer, no private
  cache publication, expected genuine allocation-generation delta and a popped
  producer stack. No fake successful Duplex/process/provider is admitted.
* An actual new Socket-local ordinary constructor attaches a sole native witness
  to its REAL newly allocated receiver, throws B, and releases that receiver.
  Assert B survives ordinary C, current fatal C alone promotes, finalization is
  exactly once and the actual Bfb invocation is popped.
* Retain the prior current-capture/success/real-GPA/marked-history controls through
  the SAME new actual callable used by Socket constructor and methods.

The native witnesses only produce controlled VM events; they are not fake OS
handles/processes/TTYs. The actual namespace failure precedes any Duplex call or
endpoint admission. No physical console/runtime conclusion is inferred.
Adopter resolve order is context, Engine, SAME Socket receiver, actual handle,
actual options. Stream's existing receiver-first implementation matches it.

Independent review continues. No compiler/formatter/AST/Node/native/generator
job, Main/shared Scope/Engine/C/H edit or public/default activation occurs.
