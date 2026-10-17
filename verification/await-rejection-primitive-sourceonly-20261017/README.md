# C3 native AF ordinary throw-completion / actual event successor

Source-only successor of immutable b6a8ca562e71a27f6a3f7d1bb7015ee30aef787d.
No execution, compiler/parser/AST or Main edit. H/Engine/AF adapter unchanged.

The native AF action THROW is owned ordinary Source completion DATA. It calls
only the existing intrinsic outer reject function, without JS_Throw of the
payload or clearing its bit/tag. Actual pending events are taken before native
body entry and before any resumed-input/output/result/frame/capability release.
Only actual pending errors participate in fatal selection. First actual fatal
is owned outside pending; cleanup ordinary errors cannot replace it. Frame roots
are detached and invocation marked inactive before per-value release, so late
queued reactions cannot reenter freed Source state. Hidden capability references
are retired after settlement/host-abort; already-published Promise settlement is
not undone. Host fatal does not synthesize ordinary rejection settlement.

The related native call failure tail uses the same owned drain for its unpublished
Promise and native-frame teardown. Incoming actual pending at native call entry
returns JS_EXCEPTION before allocating a frame or entering Source. The generic
bytecode AF, generator, query, C4/C5, TLA and CallSite paths are unchanged.

JS_EXCEPTION returned without pending is an explicit native callback contract
violation, converted to an actual InternalError. No attempt is made to undo
extra guest work performed inside an invalid C callback before returning.
Finite native finalizers are supported; deliberately nonterminating C callbacks
are outside this ownership proof.

The unchanged nine b6a8 regression definitions remain normative. Their formerly
known-negative ninth escaping-flagged-DATA definition is expected to expose the
old C3 bug and exercise this new code, but has NOT run against either candidate.
Two additive genuine VM declarations in native_async_throw_cleanup_test.zig are
imported by that root, for a total eleven actual definitions:

- An actual Promise constructor getter transfers/throws a sole-owned ordinary
  Error I. Real Await setup resumes the body with I; the body's returned R is
  initially ordinary success. VM release of owned resumed-input I raises actual
  pending A through its token finalizer. Freeing returned sole-owned R raises
  fatal B; ordinary A's finalizer raises C; private frame retirement raises D.
  The first actual fatal survives every cleanup. A second mode marks A fatal and
  verifies A wins B, retaining its token until the host releases chosen A. No
  callback returns a value with an illegally pending exception to stage this.
- Actual pending fatal at native call entry, with genuine armed GPA failure,
  prevents callback entry/allocation and preserves exact reason. This complements
  the source check of pending before every resumed native_body/private-stage get.

All native marker Errors are real JS_NewError objects. Expected/observed/reference
outputs remain absent. All old b6a8 packet bytes are retained. The C source patch
requires independent peer review and Root component/composed qualification before
intake/selection. No full runtime/Agent/SDK success claim follows from this source.
