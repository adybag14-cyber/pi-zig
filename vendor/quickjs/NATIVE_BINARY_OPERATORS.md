# Native algorithm operator boundary

`JS_PiBinaryOperator` duplicates two borrowed operands and passes the owned
copies to QuickJS's existing interpreter arithmetic or relational slow path.
Those paths consume both operands on success and failure; success leaves the
owned result in stack slot zero and failure retains the original context
exception. The wrapper neither evaluates source nor implements alternate
numeric coercion rules. Its operation indices cover add, subtract, multiply,
divide, less-than, less-or-equal, greater-than and greater-or-equal.

The project-owned ABI is additive. The pinned upstream implementation and
license remain unchanged outside the wrapper and public declaration. Native
algorithm callers must free the returned result, preserve original exceptions,
and must not reuse a value after transferring its ownership.

The focused native test compares the ABI with real guest operators for ordinary
numbers, signed zero, NaN, infinities, strings, BigInts, mixed numeric types,
undefined/null, coercion hint/order and original exception identity. Broader
native image API integration and platform qualification remain separate.
