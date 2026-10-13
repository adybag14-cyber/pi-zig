# Native cache warming

Implementation commit `d5e9a9169a68b842947e3cd6ff34b3c0c51690d9` ports the
original CacheWarmer class and its lifetime, pricing, provider-environment and
formatting dependencies from upstream `e6220e1316f86af818a0ccbfe1c09d7e918b41cf`.
The implementation is Zig calling the linked C language runtime. It does not
install a public cache-warming module or activate the native session factory.

The ordinary class fields and fourteen prototype entries retain the original
order, descriptors, function names, arity and async identities. Refresh uses
native promise continuations for the decision and provider-response awaits.
Each continuation retains the actual receiver and run, checks cancellation,
preserves fixed expiry margins and safety horizons, and persists successful
usage before invoking the current onWarmed callback. Guest failures retain the
original best-effort behavior; private native allocation failures remain fatal.

The cost helper observes live pricing tiers and getters, including original
one-hour cache-write arithmetic. Provider-environment lookup retains scoped
and process precedence and the private one-time Bun fallback cache. The native
process shim exposes the actual Zig and QuickJS versions for feature detection.
Formatting uses live number/string methods and the engine's captured intrinsic
regular-expression constructor, preserving literal behavior if RegExp is replaced.

Genuine Source execution uses the isolated latest source tree, its official
hydrated model catalog, audited unchanged external dependencies, and Node 24
with observed official export resolution. No original class or function body
was rewritten. The fixtures contain 70 lifecycle/helper cases and 34 formatter
cases. Reference verification retained 1,945 latest source/catalog files,
31,064 reused runtime/dependency files and 1,774 tool files with zero drift.

Windows Debug and ReleaseSafe each passed all six selected tests, including
all 104 original cases, a real timer refresh/cancellation with explicit GC,
and every induced host allocation failure across construction, refresh,
environment lookup and formatting. Both runs retained 4,662 source and 19,546
compiler files with zero post-run drift. A binary git cat-file comparison checked
all 4,662 committed blobs against the successful ReleaseSafe source manifest
and found zero byte drift. The first Debug attempt correctly failed at the
then-missing process.versions object; its negative receipt remains preserved.

Portable receipts are under verification/cache-warmer-e6220e1-20261013.
The candidate workflow separately compiles cold artifacts, then runs the
original 120-second test guards within a five-minute runtime step. It freezes
the exact checkout and full compiler distribution and requires every named
Source/GC/allocation comparator in the actual compiled inventory to pass.
Windows, Linux and macOS each run Debug and ReleaseSafe. Hosted qualification,
full session-factory integration and complete Pi parity remain separate gates.
