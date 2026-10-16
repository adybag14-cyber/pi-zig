# Source-only canonical indexed operand repair

Actual native891 Source80 matched first52 rows, then schema-prefix-items returned
Checkfalse rather than true while Errors[] and Code matched exactly. Pinned
schema/engine/prefixItems.mjs:10 and items.mjs:11/19 pass `${value}[${index}]` into
BuildSchemaPushStack. These operands bypass EmitGuard.Member. The current native
fallback looked up the entire `value[0]` as one lexical/global name, producing
undefined rather than the actual array member. Every's real offset2 and index
bindings already skip the first two entries correctly in this case.

The repair preserves the existing External operand path first. For otherwise
unrecorded operands containing brackets, it admits a trailing canonical unsigned
u32 decimal `[N]` suffix, requires a captured IR/base identifier or another indexed
base, and iteratively peels suffixes until its first captured IR/simple base.
It evaluates that base once, then applies reversed numeric indices through real
JS_GetPropertyUint32 reads. Nested prefixes resolve inside-out.
VM getters, receiver, inherited properties and exceptions retain ordinary VM
semantics. Empty/nondecimal/negative/fractional/leading-zero/overflow indices,
unbalanced brackets and unsupported recognizable suffix/base forms fail explicitly.
Existing recorded expressions and Code strings are unchanged. This does not
evaluate JavaScript source or introduce a general expression parser.

Independent review identified unbounded recursive suffix evaluation and retained
progressively shorter UTF8 copies in the initial99f proposal. The iterative
successor retains one original UTF8 buffer, one index vector and one final base
string. Prefix lookup uses an atom freed within each iteration; only the first
captured node remains rooted. evaluateCaptured consumes that node directly,
avoiding a second lookup and preserving its priority. Real numeric gets follow
inside-out order with the original receiver/prototype/getter behavior. Native
steps poll cancellation and the existing interrupt budget at the same256-step
cadence used by native JS iterators. No new Source-visible depth limit is added.

native-ir-indexed-operands.input.mjs prepares ten ordinary input observations:
valid/invalid/short/hole prefix arrays, tuple items, own/inherited/throwing getters,
and nested arrays/getters. It records actual Compile/Check/Errors/Code and accessor
read order/receiver observations. No expected file was generated or native output
accepted as source authority. The input must first run against the pinned genuine
Source package under a separate explicit grant and full frozen evidence; the same
input can then be replayed against the actual native graph. Current Source80/52/396
inputs, goldens, guard, counters, C and shared helpers remain unchanged.

No Zig fmt/AST/compile, source runner or native execution ran for this proposal
during the Models lease. Original891 negative archives remain immutable. The
separate GPA target is still authored but unrun and ungranted.
