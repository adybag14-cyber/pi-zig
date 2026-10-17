# Actual CallSite strict/top-level visibility and receivers: source only

Isolated base c83c8b1364ef92479c83e8d7db8459372f4d7bf1, qualified C3
C DA14DFBB7E73DED032E9FCD742FD2E49FDAF45273F48D24D6089018539601614,
H A79E75A40D34C9E7CAFB9AB31359B7EE925FE205636603F2022CF764CFC18346.
Historical C3/C4/query/other Source proofs are unchanged. This delta does not
copy the older C2 or private-module-graph proposal. No Engine fields, public C
ABI/header changes, module-failure policy or nested-bytecode guards are added.

Exact pinned Node f657bb8ed86365ff3fdbe32e27563e778b41486a primary authorities:

- deps/v8/src/builtins/builtins-callsite.cc: GetFunction returns undefined for
  strict or top-level frames; GetThis returns undefined for strict frames.
- deps/v8/src/execution/isolate.cc: CallSiteBuilder poisons each visible frame
  from the first strict function through all older frames. Skipped/filter frames
  do not first poison the visible sequence. Builtin hole receivers become
  undefined when appended.
- deps/v8/src/builtins/x64/builtins-x64.cc: CallFunction enters the callee realm
  and binds non-native sloppy receivers before invocation, using the realm
  global proxy for nullish values and ToObject for primitives. The builtin
  constructor stub supplies a hole, not new_target, as the stack receiver.

All three whole inert primary files and their V8 BSD license are retained and
hashed. They are source authority, not actual Node runtime observations.

Private implementation changes:

1. Every actual stack-frame creation path owns its supplied receiver. Ordinary
   and coroutine JS activations perform the actual sloppy binding once in the
   bytecode's realm; OP_push_this then receives that same bound value. This is
   needed even when the function body never reads this, so repeated captures
   expose the same actual box. Native C callbacks retain their actual raw call
   receiver; native constructors must not leak the new_target ABI argument as a
   receiver. Native AsyncFunction frames retain their already-owned native this.
2. Ordinary/native frames clear and release this root on every completion. An
   already pending reason is owned outside the pending slot over this added
   cleanup and restored exactly. Coroutine init failure frees its temporary
   binding; suspended frames mark receiver alongside current function/this/local
   values and release it once in async_func_free. That extra release precedes
   the existing separately owned this_val, so it does not retire the actual
   receiver's last coroutine root. No raw frame pointer escapes into CallSite.
3. A runtime-only flag on each function object marks actual eval/module closure
   creation. All generic/native-AF creators initialize it false; module closure
   creation and EvalFunction's actual eval closure set it true. This does not
   infer top-level status from a filename, function name such as '<eval>', or
   serialized bytecode content, and does not change the bytecode format.
4. Real captures and the legacy prepareStackTrace capture retain receiver plus
   strict visibility/top-level metadata. Clone, transfer, GC mark, success and
   allocation-failure cleanup include the added value. GetFunction and GetThis
   enforce the recorded visibility; names/locations remain available. The raw
   function remains an internal GC root, as in V8, rather than a guest escape.

Nine named prepared native tests cover sloppy object identity after return/GC,
younger-sloppy/strict/older poisoning, actual top-level versus a '<eval>' method,
legacy Error.prepareStackTrace, one primitive box across captures, coroutine
suspension/resume/GC, native AsyncFunction frame initialization and an actual
strict module declaration prologue before body execution. The prologue test
uses the real pinned 10000-step VM interrupt cadence: it primes to an actual
interrupt, makes 9998 real noop calls, then captures at the actual module
prologue if_false poll and returns a real trusted interruption. It neither
writes internal frame/module fields nor executes a fabricated prologue. It
requires the physical module filename, hidden function/receiver, no body flag
and no pending jobs. Its execution is unobserved until a Root-granted gate.

The six-row original Node caller uses only actual node:vm, native Error stack
APIs and an actual physical ESM fixture. Expected/observed outputs are absent.
The module-body row is an actual Node visibility input, not a claim that Node's
private prologue was observed. The native prologue control is grounded in the
actual C emitter and branch polling, while strict visibility comes from the
pinned V8 contract. Full Native CallSite method coverage, cross-realm/ShadowRealm
policy, native/API constructor frame classification and all Node stack shapes
remain separate gates; this finite patch does not claim those are complete.

No compiler, parser, AST, metadata, Node or native job ran during authoring.
The nine named declarations are not an observed compiled count. The build
snippet is only prepared source; Root owns all grants and later composition.
The separate readonly TLA query fixture successor b814eac6 and CommonJS lazy
provider source remain in their own worktrees and were not overwritten.

Independent review found the same missing-PC branch also reachable through
legacy build_backtrace with prepareStackTrace installed. The common metadata
helper now preserves the real filename and uses unavailable line/column -1
instead of subtracting NULL pointers. A separate actual legacy-prologue
variant installs prepareStackTrace, triggers the real cadence interruption,
and requires hidden function/receiver plus null position metadata. This is a
new source control, not a passing runtime observation. Nonconstructor native
calls retain the original activation receiver even if their internal C ABI
uses its argument slot differently; only a constructor activation has the
builtin hole/undefined receiver described by the pinned V8 source.
