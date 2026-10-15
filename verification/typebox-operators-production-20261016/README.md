# Actual TypeBox generic operator closure, source checkpoint

This isolated lane starts from Root
`3b479da0a86a20c5fd1baf15969777733ded95c9`. It adds new operator implementation,
runtime primitives, comparator input/test and authoring/provenance files. It
does not modify shared Engine, TypeBox, SDK, C or build files. AEA5 and its
published proof remain unchanged.

**Status: source-only.** Native code has been authored and passed formatting and
Zig AST checks. Genuine Source execution, native semantic compilation/execution,
host GPA and C malloc qualification have not run for this candidate. No expected
results are fabricated or supplied. The test fails if its genuine golden is
absent. No availability, integration, whole-TypeBox or activation claim follows
from this checkpoint.

## Authority and implementation

The authority is the installed TypeBox **1.3.27** at
`C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox`.
Its package manifest SHA256 is
`C59DDFD977CE941F1E8EE8B0A0B14396C332FA27CC5FA6FA165227FFD5A3992F`.
`reachable-closure.json` identifies all **250 reachable modules**, **878 selected
declarations** and **153 exported bindings**. `lowering-map.json` maps all **1,667
compiled native callbacks** to original file spans, source hashes, names,
arities and arrow status. The TypeBox MIT license is retained alongside them.

`native_typebox_operators_production.zig` contains ordinary Zig functions and
control flow. No JavaScript source checker, AST interpreter, bytecode/source
blob or TypeBox runtime import is evaluated by the native implementation.
Arithmetic and relational operations call the existing C VM operator helpers;
regex literals use the Engine's existing captured RegExp intrinsic. Existing
value/property/iterator and native function ABI helpers are retained.

`lower-authority.mjs` is **external static authoring**, permitted for this lane.
It parses pinned authority with Acorn and emits compiled Zig operations and
literals. It never imports or executes TypeBox. Unsupported syntax or operator
vocabulary fails during authoring. Node/Acorn are unnecessary for the native
runtime. `Validate-Static.ps1` pins Zig 0.16.0, the authoring Node/parser, regenerates
the output, formats it and runs AST checks with fail-fast exit checking.

The closure includes Instantiate's complete deferred dispatch, all structural
containers, ref visiting, generic target/argument resolution and constraints,
dependent defaults, distributed calls, tail-call handling, mutable shared
instantiation counters and finally recovery. It includes the actual Extends
left/right/inference, function/constructor parameter/return variance,
intersection/conditional/mapped/interface/module/indexed/intrinsic and finite
template/pattern-parser dependencies. Existing Chord Type14 comparison and its
explicitly rejected branches are not used as completion aliases.

## One shared graph

The API is:

```zig
pub fn create(engine: *Engine, graph: JSValue) !JSValue; // owned operator namespace
pub fn install(engine: *Engine, type_builder: JSValue, graph: JSValue) !void;
```

The caller creates one mutable `graph.Type` builder and passes that same object
to `install`. The graph's sole `Memory`, `Settings` and `Memory.Metrics` come from
the other lane's `native_typebox_memory.zig`. Public Partial and Enum remain
owned by `native_typebox_partial.zig`; install preserves them. No second Memory,
Settings, Metrics, type cache or symbol registry is created here. Hidden string
markers `~kind`, `~optional`, `~readonly`, `~immutable` and actual symbol fields
flow through the shared Memory implementation.

The seven evaluation bindings delegate directly to the actual algebra in
`native_typebox_partial_evaluate.zig`:

| Source binding | Shared native operation |
| --- | --- |
| EvaluateTemplateLiteral | template |
| EvaluateEnum | enumeration, with default result array only for undefined |
| EvaluateIntersect | intersection |
| EvaluateType | evaluate |
| EvaluateUnion | unionValue |
| EvaluateDependent | dependent |
| EvaluateUnionFast | fastUnion |

Required other-lane source successors are `3851638b` (new shared files),
`95f3dd29` (Memory descriptor evaluation order) and `d1041b56` (all seven
evaluation APIs), or their reviewed later descendants. They have not been
copied over newer Root files. The supplied comparator requires this dependency
closure to be intaken before semantic compilation; it does not hide missing
bindings or provide substitutes.

Generated closures keep lexical environments and captured `this` in the existing
GC-marked native function state. Child function parameters/local declarations
shadow ancestor bindings. Receiver/key/getter evaluation precedes call arguments;
computed ToPropertyKey conversion precedes assignment RHS/object property values.
Array parameter patterns and spreads use the actual iterator protocol and
error-preserving close. The source-selected ForOf body has no early return,
continue or escaping per-iteration capture; the selected index for-loop has no
continue. Its early return needs no iterator close. The generic try/finally
executes cleanup on original failures and releases a successful result if the
finally branch fails. Source thrown-value identity is retained by the existing
engine/native callback error path. These are authored semantics awaiting runtime
qualification, rather than claims inferred from AST checks.

## Genuine probes and qualification boundary

`typebox-operators-production.input.txt` is one shared, user-style probe input
for actual Source and native paths. It covers every deferred action in resolved
and unresolved form, all Instantiate containers/modifiers/ref branches,
primitive and structural Extends branches, inferred-property shadowing,
function/constructor variance, records/tuples, Priority stability, finite and
infinite template patterns, conditional/mapped distribution, generic constraints,
defaults, named/unresolved/non-generic calls, default and low instantiation limits
with recovery, shared immutable/enumerable settings, symbol options, getter
order/thrown-value identity, GC rooting and a guest OOM lookalike.

`capture-genuine-source.mjs` validates the pinned module bytes and runs the probe
against actual installed Source exports. It refuses output overwrite. It must
only run after a Root Source slot grant under a clean seal and the standard full
candidate/vendor/Source/dependency/compiler/Node/control freezes. A double capture
must match exact rows and have zero posthash drift. Nothing has been captured in
this lane yet.

`src/native_typebox_operators_production_test.zig` reads the explicit genuine
capture path from `PI_TYPEBOX_OPERATORS_GENUINE_JSON`, compares every row and all
metrics in order, and fails at the first mismatch. It rejects a too-small probe
universe and detects trusted native allocator failures independently of guest
catches. It exposes an actual C VM GC callback for the shared rooting probes.
There is no plaintext/ordinary-error fallback for missing host dependencies.

After the Source controls qualify and Root supplies the compile slot, the next
gates are semantic Debug compilation, exact Source comparator, caller/getter/GC
and interruption/ownership controls, then a measured complete host-allocation
failure plan. Normal admission/stack/timeout bounds remain unchanged. C malloc
exhaustiveness and broader Root/compiler/value integration require their own
evidence. No native job or cache cleanup was launched here.
