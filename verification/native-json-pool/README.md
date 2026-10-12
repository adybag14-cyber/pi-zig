# Native JSON allocation qualification

Use Zig 0.16.0. From this directory run:

```text
zig build test-json-path-cmalloc -Doptimize=Debug -j1 --test-timeout 120s --summary all
```

The build derives instrumented copies from the current production QuickJS and
engine allocator sources. Three exact allocation-hook anchors fail closed on
source drift. It preserves the small-block pool and injects one genuine failed
allocation at each selected index after compilation and setup finish.

The three cases cover Unicode constructor diagnostics, deep array/object cycles,
and a getter that reenters native stringify and triggers GC. Each induced failure
must preserve either real allocation failure or the exact original diagnostic
when an optional allocation fails. Each runtime must release every tracked native
byte and every retained owner reference. This qualifies the selected paths;
other VM operations and compiler allocation failures remain separate requirements.

The October12 Debug run passed3/3 tests and every index in allocation universes
25,29,44 (98 total). The earlier backing-allocator probe reached only two failure
indices. A first pool-level probe exposed an incorrect test assumption: constructing
the callback argument inside the getter can fail before the callback runs. The
maintained test prepares that argument during setup and retains its strict getter,
callback and GC assertions. The earlier failed observation is preserved externally.
