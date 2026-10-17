# Separate link transaction successor to the reviewed VM composition

The first composition remains immutable at
`6b78423f727f428d52ec3b8e495cfee2475ab57d`. Async independently source-reviewed
that checkpoint. This successor applies only the reviewed link transaction
delta from `328eab6e` to `3c49496a`, including its two private C include files.
It does not replace the composed C/H with an older standalone file. The patch
check and application succeeded without conflicts over the existing C4 query,
C5 iterator and CallSite union.

The unchanged standalone link packet is retained under
`verification/module-link-transaction-sourceonly-20261017`. Its product commit
is `87a8bcec`; Async closed that source at `3c49496a`. Its recorded C/H hashes
describe that historical standalone candidate. This directory's manifest binds
the actual new composed C/H. Original C3/150, current11, C4 fixture negatives,
C5 fixture history and CallSite source inputs remain unchanged.

## Caller contract

The link API is opt-in. A caller MUST attest a genuine capture-only native
Error-stack owner, balanced diagnostic suppression, Engine's trusted interrupt
callback, a live owner context, and no guest formatting, graph mutation,
disposal or reentry while preparing the graph. A non-null callback is not proof
of those properties. No production caller or default selection is added here.
Query remains independently readonly; iterator acquisition and ordinary C3
paths do not acquire link-transaction behavior outside the actual link call.

The genuine link control root and allocator-control C source are copied byte
for byte from `3c49496a`; all 25 original assertions remain. Both the individual
link target and the combined target link that same real allocator-control file.
The eight measured allocator sweeps in that control source remain unrun here.
No module fields are fabricated, and no generated expected result is introduced.

The combined root adds one control using a real compiled module: query before
link, actual link with body still absent, query after link, actual evaluation,
C5 acquisition of its real async generator, and strict CallSite function/receiver
hiding. It uses the genuine native Error-stack owner and explicitly balances the
link suppression scope. Its expected scalar23 is the literal yielded by its
input module, not an authored Source golden. This control remains unrun.

## Install-only targets and pending gates

`build-native-vm-c4-c5-callsite-link-controls` aliases the install-only composition
group. Individual suffixes are `-query`, `-iterator`, `-callsite`, `-link` and
`-combined`; each installed artifact has a distinct name. The combined static
named census is 14 + 13 + 9 + 25 + 1 = 62. Actual compiled metadata and imported
anonymous entries are unknown and require separate discovery and review.

The separate original C3 fifteen-group150 and queued/binding11 install targets
are unchanged from the first checkpoint. Their original metadata is authority
for future exact selection, not a new pass. Neither aggregate nor individual new
targets run a test or attach to the default build/install selection.

Independent combined source review, actual compile, complete metadata, runtime,
GC/allocator and retained-regression qualification are still required. Node
require(esm), CJS compilation, EventStream generator-function/producer-exit APIs,
whole SDK/Pi parity and runtime restoration are outside this composition.
No compiler, parser/AST, formatter, Node, native or LLVM job ran during authoring.
