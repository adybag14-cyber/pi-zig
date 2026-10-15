# TypeBox Compile/Validator native production candidate

This checkpoint is **source-only and unqualified**. Source74 has not been run,
native compilation has not been run, and expected output is absent.

The authority is the actual `typebox@1.3.27` package in the immutable fullruntime
31064 dependency artifact. The product code contains direct Zig function and
class bodies. Parse-only Acorn extraction and PowerShell authoring happened
outside the product tree; no runtime AST, JavaScript compiler host, or generated
checker JavaScript is executed by the native compiler backend.

`native_typebox_compile_production.create(engine, shared)` takes the actual
shared `{Memory, Settings, Type}` graph. `Type` is the mutable export builder
before namespace sealing. The generic operator implementation and the Partial
algebra share this graph. The compiler adds the genuine Codec builders and
`IsCodec` dependency. The existing actual Format registry and Hashing body are
reused. No Engine, SDK, shared build, main, release, or activation file changes.

The dependency catalog has 271 actual source modules. Native bodies include
Compile/Code/Validator, BuildResult/EvaluateResult, Build/Check/ErrorContext,
the original reference Stack and Resolve algorithms, all schema keyword
build/check/error visitors, Guard/EmitGuard, localization, and the required
Clean/Convert/Create/Default/Parse/Decode/Encode/HasCodec visitors. Public
Validator fields and methods remain live, ordinary class methods have the
actual constructor/prototype relationships, and callback captures retain VM
lexical cells. These are not aliases for the private plain tool-validator.

The native accelerated backend records typed nodes during the actual native
EmitGuard build. This preserves the code-generation walk and captures emitted
scalar operands without a second schema traversal. Native nodes implement
logical/type/numeric/object operations, ordinary member/call/new evaluation,
arrow closures, statement blocks, const declarations, returns, conditional
statements, array every/some/forEach/reduce, recursive checker functions, and
live External variables. `Code()` is the original generated text. Dynamic mode
uses the actual directly ported CheckSchema/Stack/CheckContext bodies and live
settings/schema values. Per-build native maps follow reentrant builds, and a
detached native checker retains its IR and actual external callbacks through
GC.

The 74 prepared genuine controls include public metadata and class identity,
borrowed methods, subclass setters, prototype descriptors, constructor/context
identity, parse cause descriptors, value transformations, full keyword
examples, accelerated-versus-dynamic schema/settings/ref/const/enum mutations,
getter order/errors, refinement function identity, live error limits, actual
Codec builders, reentrant compilation, standalone Code external sharing,
shared Memory metrics, and detached-check GC.

Remaining qualification risks are explicit: semantic compilation is unrun;
arbitrary guest replacement of BuildResult `Functions`/`Entry` with new source
text is not yet lowered by the native IR; mutation of compiler-owned argument
arrays by overridden built-in `join` methods needs further source-order audit;
the internal WeakMap ownership seam needs lifecycle/fault-injection coverage.
These risks are not covered by formatting or AST checks. No fake acceleration
flag, dynamic checker alias, fabricated golden, or allocation-coverage claim is
made.
