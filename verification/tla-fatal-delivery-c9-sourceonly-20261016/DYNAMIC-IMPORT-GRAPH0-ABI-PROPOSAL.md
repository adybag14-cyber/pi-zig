# Explicit-base queued import: tiny additive C ABI proposal only

No C/header/Engine implementation is changed by this proposal. The current
reviewed/qualified product remains C2FA/H341. The accepted a3 focused34 and
selected core116 packets retain their own exact source/artifact identities.
No compiler, Node, generator or native test job ran for this design.

## Actual caller and concrete scheduling defect

The sealed SDK helper checkpoint e95d430c25b51162bc72b3b0358f41a314e89476 at
worktrees/sdk-assembly contains native_sdk_extension_lazy_imports.zig. Its
required Inputs.dynamic_import callable receives exactly two borrowed JS
strings: the captured physical loader filename and the selected already-string
absolute module filename. Receiver is undefined; Source omits options/attrs.
It returns the real import Promise. Ordinary getCreateJiti/getVirtualModules
then cache the exact importPromise.then(selector) result, including rejection.

Existing public JS_LoadModule creates a capability and calls
JS_LoadModuleInternal immediately. Guest js_dynamic_import instead queues
js_dynamic_import_job, specifically to avoid unexpected evaluation recursion.
Immediate loading runs lazy C-module export getters before the Source's public
.then read and can admit/observe namespaces too early. A wrapper allocating
another Promise or async outer completion would add identity/job differences.

The new SDK helper already requires the genuine binding and has removed its
JS_LoadModule fallback. Missing binding or completed namespace authorities
remain explicit admission errors. The older extension-import prototype stays
unselected and is not proof of completed jiti semantics.

## Proposed public surface

```c
JS_EXTERN JSValue JS_PiDynamicImportGraph0(JSContext *ctx,
    JSValueConst physical_basename, JSValueConst specifier);
```

Both inputs are borrowed. The required SDK caller supplies primitive JS
strings; its physical path admission already rejects nonabsolute/NUL names.
The operation owns no caller buffer and does not coerce the basename. It
duplicates that immutable JS value for the queued operation. The specifier
uses the existing js_dynamic_import synchronous ToString step; required calls
already supply strings. Options are fixed to JS_UNDEFINED, so attrs are omitted.
Do not expose an unobserved attrs/GraphID overload in this first capability.

Return the exact existing intrinsic dynamic-import Promise or existing abrupt
completion. The native JS binding must be an ordinary raw-return function
(length2) that forwards this owned value, not a genuine async wrapper creating
an additional outer Promise. No new JS global/module export is required; the
binding is a private real input to the sealed helper.

## Minimal common implementation shape for later review

1. Keep the guest js_dynamic_import wrapper's current script/module basename
   capture and AtomToValue error handling at the same point before capability
   creation and specifier coercion.
2. Factor the existing body after that capture into a private common helper
   accepting the owned basename plus borrowed specifier/options. Its existing
   capability creation, string coercion, attrs code, cleanup and job dispatch
   remain one implementation.
3. The old guest wrapper moves its owned basename into that helper. The new
   ABI passes an owned duplicate of its explicit basename, borrowed specifier
   and undefined options. It never consults an ambient caller filename/origin.
4. Reuse the exact existing five-argument js_dynamic_import_job tuple:
   resolving functions, basename value, coerced specifier, undefined attrs.
   The existing JS_EnqueueJob captures the actual execution context and owns
   those arguments. JS_LoadModuleInternal runs only inside that genuine job.

This needs an additive declaration/entry point and small extraction of the
existing setup, not copied loader logic, source evaluation or a second Promise
capability. Existing JS_LoadModule and existing guest import behavior retain
their implementations and ordering. The new C/H identity and capability
availability controls must be sealed separately from H341 before use.

## Graph and lifetime boundaries

This ABI is deliberately graph0 for shared native SDK helpers. It must not
inherit a private caller's graph or infer an owner from a physical filename.
It selects neither a graph capability nor a private module definition.

When composed with the separately reviewed Graph2 source, the common setup
must accept the existing explicit origin/anchor tuple from the guest wrapper.
The new Graph0 entry passes NULL origin/undefined anchor and uses the ordinary
five-argument job. The existing private guest path still captures its exact
lexical origin before coercion and queues its existing module token/strong
bytecode anchor. No opaque graph IDs or private-origin input are added here;
those capabilities and their qualification remain separate.

The basename/specifier strings and resolving functions are retained by the
existing job argument ownership and freed by existing cleanup. The returned
Promise is owned by the C caller. Module definitions/namespaces remain owned by
the context's existing loaded-module machinery and preserve normal shared
cache/namespace identity. No nonce or synthetic physical filename is introduced.

JSJobEntry.ctx is still raw. The host must keep that context valid through job
execution/cleanup, as with current guest import. This proposal adds no new
context pin and makes no claim that a module token alone is a GC owner.

## Required focused controls before selecting the binding

- A real lazy C-module export getter records initialization. Calling the SDK
  getter must return/cache its .then result while initialization count is zero;
  pumping the actual import job then evaluates the getter once.
- A mutable Promise.prototype.then getter is observed before module init. If
  it throws, the SDK cache assignment does not happen, but the already queued
  import retains its genuine behavior. This distinguishes queued import from
  immediate JS_LoadModule without inventing extra Promise/tick machinery.
- C/API calls from a foreign or absent ambient script frame still normalize
  against the exact captured physical loader basename. Record the real loader
  callback's base/specifier and physical module metadata; no filename aliases.
- Raw ABI calls allocate distinct import Promises while repeated ordinary SDK
  getters return their exact cached .then Promise. Concurrent imports retain
  the canonical namespace and existing module/TLA/cache semantics.
- Ordinary load/evaluation failures and selector/getter failures preserve raw
  rejection/cache identity, including rejection cached by the SDK getter.
- Queue argument lifetime through GC and normal context teardown, actual ABI
  availability/admission, and the existing execution-context capture are checked.
  Do not count a manually completed namespace/Promise as an import observation.
- Actual getCreateJiti and virtual-module helpers still require complete real
  jiti and all nine real authorities. This ABI does not qualify a partial jiti
  facade, the old namespace-only adapter or the full default SDK by itself.

## Explicit inherited policy, not silently claimed repaired

Current js_dynamic_import/JS_LoadModuleInternal paths have their own exception
conversion/attachment/enqueue policy (including existing ignored enqueue and
void-loader return sites). This tiny scheduling capability does not repair or
relabel those paths. Ordinary errors use the actual existing import operation;
native fatal/INIT/queue-allocation boundaries need their own concrete audit and
controls before any broader allocation/fatal-delivery claim. Rejected data's
bit/tag alone never authorizes fatal reconstruction. No speculative shared
Promise rewrite is included in the proposed extraction.

Root and independent async C-owner review must close the exact extraction,
Graph0 admission and controls before implementation/composition. Current a3 C,
headers, qualified packets and main remain unchanged.
