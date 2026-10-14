# Native algorithm operator boundary

`JS_PiBinaryOperator` duplicates two borrowed operands and passes the owned
copies to QuickJS's existing interpreter arithmetic or relational slow path.
Those paths consume both operands on success and failure; success leaves the
owned result in stack slot zero and failure retains the original context
exception. The wrapper neither evaluates source nor implements alternate
numeric coercion rules. Its operation indices cover add, subtract, multiply,
divide, less-than, less-or-equal, greater-than and greater-or-equal at indices
0 through 7. Index 8 is the original remainder operator and index 9 is the
original exponentiation operator (`OP_pow`). Existing indices retain their
meaning. Exponentiation must not call the mutable guest `Math.pow` function.

`JS_PiIncrement` follows the same borrowed-value contract with a single owned
stack operand and the interpreter's `OP_inc` unary slow path. Its actual
`ToNumeric` operation retains BigInt behavior, including large BigInts, rather
than applying `ToNumber`. The caller receives the updated value; postfix old
value handling remains the caller's responsibility.

`JS_PiDecrement` uses the identical ownership contract with the interpreter's
`OP_dec`. It preserves `ToNumeric`, including BigInt retry counters, rather than
subtracting the Number value `1` from an operand of unknown numeric type.

The project-owned ABI is additive. The pinned upstream implementation and
license remain unchanged outside the wrapper and public declaration. Native
algorithm callers must free the returned result, preserve original exceptions,
and must not reuse a value after transferring its ownership.

The focused native test compares the ABI with real guest operators for ordinary
numbers, signed zero, NaN, infinities, strings, BigInts, mixed numeric types,
undefined/null, coercion hint/order and original exception identity. Broader
native image API integration and platform qualification remain separate.
