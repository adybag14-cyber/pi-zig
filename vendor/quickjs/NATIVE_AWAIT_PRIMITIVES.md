# Native await and numeric conversion boundary

`JS_PiPromiseResolve` passes one borrowed value to the existing interpreter
`js_promise_resolve` with `ctx->promise_ctor`, exactly as the interpreter's
await path does. The helper observes the original promise's constructor,
retains a promise with the intrinsic constructor, and otherwise assimilates
through the original thenable algorithm. It never looks up a mutable global
Promise constructor. Its owned result must be freed by the caller. The input
is not consumed; the interpreter helper duplicates any retained reference.

`JS_PromiseThen`, already provided by the pinned implementation, attaches
intrinsic reactions without consulting a mutable `.then` or species. Native
async dispatch can use it after `JS_PiPromiseResolve`. Its owned result must
also be released. These operations do not evaluate guest source or introduce
a guest generator as the host implementation.

`JS_PiToNumeric` delegates to the existing `JS_ToNumeric`, which duplicates
the borrowed input and consumes that duplicate through `JS_ToNumericFree`.
It returns an owned Number or BigInt, preserves signed zero, executes the
original numeric coercion hint, and retains the original exception on failure.
For postfix updates, the host retains this old numeric value and passes it to
the separately qualified `JS_PiIncrement`; an already-numeric operand causes
no second observable coercion.

The focused native tests compare these boundaries with actual guest await and
postfix-old-value behavior, including constructor/then access, BigInts,
signed zero, coercion hints, borrowed lifetime and raw exception identity.
Actual Source527 captures remain separate authority for the complete runner
emit operation. This additive wrapper alone does not qualify full async SDK,
UI prompt handling, prototype surfaces, or other platforms.
