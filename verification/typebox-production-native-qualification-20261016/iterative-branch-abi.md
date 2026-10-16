# Debug-safe compiled native branch dispatcher

Actual8bcb Debug compilation failed LLVM verification because musttail calls
returning the JSValue error union did not immediately precede LLVM ret. The
original error log and complete strict posthash0 are retained under
typebox-production-build-seventh-8bcb73f3-20261016. Owner70800 was independently
absent/globalnative0; no compiled artifact or native qualification followed.

The replacement uses this native ABI:

```zig
const BranchResult = union(enum) { value: c.JSValue, jump: usize };
const BranchHelper = *const fn (*rt.Scope, c.JSValue, c.JSValue, []c.JSValue) anyerror!BranchResult;
```

Each of585 compiled helpers evaluates its original predicate once. A selected
nested tail expression returns its static child helper index; a completed arm
returns a borrowed JSValue. runBranch loops over a static function-pointer
table, using a single error-union result and propagating errors unchanged.
There is no recursive helper call for a tail jump and no LLVM musttail request.

Caller-owned Scope/environment/GPA operand storage remain live across every
jump. Helpers add no allocation, cleanup, or independent ownership. The
original callback still duplicates completed return values before its storage
and Scope close; the existing try/finally completion/errdefer path is unchanged.
Nested predicates and operand expressions still call runBranch recursively
where their original expression structure requires a non-tail result. Guest
callbacks, getters, receiver binding and argument order remain real VM actions.

The function-pointer table selects only statically compiled predicate/arm code;
it is not a generic runtime AST, opcode walker, source evaluator or checker host.
Module250/declaration880/callback1669 identities, original fixture rows and
goldens, lexical TDZ and module initialization order remain unchanged. Engine
guard1MiB and actual reserved Windows stack16MiB remain unchanged. Actual new
PDB frames and strict original replays are still required before claiming a
stack reduction or native qualification.
