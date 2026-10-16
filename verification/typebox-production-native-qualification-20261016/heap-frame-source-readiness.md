# Source-only bounded TypeBox frame repair

The last exact native batch at de6d0bfc compiled and independently exposed the
four expected test metadata names. Runtime failed1/4 with complete strict frozen
posthash/inventories0 and independently absent owner69328/global native0.
Source52 matched its first40 original rows after the exact original52-row input
was restored. Source396 matched its first391 original rows. Original rows and
goldens remain unchanged; these are retained partial results, not qualification.

Actual PDB records from that compiled artifact show InstantiateDeferred f_9
uses35672 stack bytes and InstantiateImmediate f_62518456. InstantiateType f_1
uses2984. The Windows executable PE reserves16777216 bytes; the actual Engine
VM guard remains1048576 bytes. actual-old-native-stack-evidence.json binds the
artifact/PDB/tool hashes and original S_FRAMEPROC measurements. The Source
library's128 instantiation limit was not reached before the guard: actual
14assign/102create and RangeError differed from original129assign/792create
and the original excessive-instantiation Error. No limit/counter/expected text
was changed, and the guard was not raised or disabled.

The static authoring pass now stores generated JSValue operand temporaries in
a GPA-backed array for each native callback. The array stores borrowed values;
the same original Scope, lexical cells, guest arguments and callback captures
retain their existing GC roots and ownership. Array storage is freed by the
callback defer before that callback's Scope closes. Normal error propagation
and native allocation failure behavior are retained; this adds no allocation
coverage claim.

The585 original conditional/logical expressions have direct compiled Zig branch
helpers. Each executes its original predicate once, then exactly its selected
arm. Nested conditional chains use explicit always-tail calls with identical
helper signatures, shared caller-owned operand storage, and no helper-owned
cleanup. This retires mutually exclusive native branch frames rather than
accumulating every alternative's Debug temporaries. The caller's Scope and
lexical environment stay alive throughout the chain. Source function declarations
remain hoisted, source variable/class initialization order and lexical TDZ remain
intact, and user receiver/callee/argument evaluation order is unchanged.

These helpers are static native code, not a runtime AST, bytecode evaluator or
JavaScript checker host. Module counts250/declarations880/native callbacks1669
are unchanged. Each callback's heapOperandSlots and all branch source spans are
retained in lowering-map.json. f_9 uses436 operand slots and f_625225; native
stack sizes after the repair remain to be measured through a granted compile.

Compiler non-callable diagnostics were committed separately as21384994. Every
direct generated compiler call keeps its original JS call, but a non-callable
callee logs exact Zig source file/line/function and primitive flags before that
same call. Diagnostics do not inspect user getters or coerce user objects. This
is intended to locate the first compiler TypeError before any semantic repair;
the compiler's functional issue is not claimed fixed.

Preparation ran only static Acorn authoring, short formatting/AST checks after
fresh zero-other-native observation, and git diff checks. No native compile or
runtime has run for this heap-frame proposal. No C/H, dispatcher, stack reserve,
Engine guard, fixture golden, timeout or cancellation test was changed. In
particular, whole191 C9h dispatcher work was not incorporated. The component's
RootC12 baseline and Root's combined/C9h qualifications remain separate.
