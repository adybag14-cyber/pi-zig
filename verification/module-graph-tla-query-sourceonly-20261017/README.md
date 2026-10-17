# Readonly static module-graph TLA query: source-only candidate

Base: qualified C3 `c83c8b1364ef92479c83e8d7db8459372f4d7bf1`, C
`DA14DFBB7E73DED032E9FCD742FD2E49FDAF45273F48D24D6089018539601614`, H
`A79E75A40D34C9E7CAFB9AB31359B7EE925FE205636603F2022CF764CFC18346`.
This isolated worktree preserves that Graph0 API and the prior C2 fatal fixes.
It does not copy old C2 or the private-module-graph proposal into current C.

Only one public query is added: JS_PiModuleGraphHasTLA(ctx, borrowedModule,
intOutput). No Engine or Main file is edited. Existing C3 qualification remains
evidence about its exact older candidate, not this source-only successor.

The actual context loaded-module list supplies membership before any candidate
pointer is dereferenced. An open-addressed, checked power-of-two table has
capacity >=2*M and load <=1/2. Mark-on-enqueue bounds the worklist to M. A single
VM-charged allocation holds both arrays; structure size preserves pointer
alignment for the trailing worklist. Every loop/probe calls existing
js_poll_interrupts, and a pending completion is checked even if a host poll
returns success. Only the trusted nonreentrant Engine interrupt callback is
admitted; host context lifetime and absence of concurrent mutation are required.

The query does not call loaders, normalizers, linkers, module initialization,
namespace creation, promise hooks, evaluation or job pumping. Every reachable
static edge is checked even after finding TLA. Unrelated loaded modules affect
membership storage but not the answer. Cycles/diamonds cannot enqueue duplicates.
Only graph-resolved modules with valid context-owned edges are accepted; status
LINKING fails, but binding status UNLINKED is allowed after complete resolution.
An unresolved deserialized module or partial resolution fails without repair.

The output is written only after the successful walk and native scratch free.
Entry pending failures are returned unchanged before any allocation. Query-owned
scratch has no JS values/finalizers, so its native free cannot replace a pending
reason. VM allocation and impossible-size overflow use the existing VM OOM path;
there is no new private tag, native-generation rewrite or catchability policy.
Actual allocator failures still pass through the existing configured VM allocator.
No flag or rejected data is used to infer a fatal reason.

The independently closed source proposal is Core commit
`dbf0f29b53ce42421a6c6dcc6bdd20a977aeac6f`, path
`verification/node-jiti-commonjs-core-sourceonly-20261017/TLA-GRAPH-QUERY-PROPOSAL.md`.
That proposal's Node24 authority identifies instantiate-before-TLA-error policy.
The readonly query does not validate bindings. A separate real link-only prepare
and the actual synchronous ESM loader/namespace/facade/error policy remain
unimplemented prerequisites for Node require(esm). No link-only API or Node caller
is added here, and a false query result is not a substitute namespace.

Fourteen named causal native controls are prepared, with actual compilation,
module resolution, serialization, C modules, contexts, GC and trusted Engine
budget pressure. They have not been compiled, queried or run; imported anonymous
metadata entries and total compiled count remain unknown. The build snippet
installs canonical test.exe through the normal build machinery only after Root
review/intake. No jobs or default Node bootstrap selection are authorized here.
