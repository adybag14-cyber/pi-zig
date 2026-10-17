# Owned pending/cleanup completion repair

Source-only successor to review findings at immutable6ac7ae83. The original
source packet, manifest, controls and primary sources remain unchanged. No job,
Main, Engine, Hub, shared callable or C/H/VM implementation is modified here.

The new mkdir-local native_node_fs_mkdir_exit leaf holds one chosen owned reason
outside both pending/captured slots in a transient owner-stack frame. Only these
native owner invocations are linked by thread-local stack provenance, separately
matched by Engine; no worker/native registry or async suspension retains a stack
pointer. Frames leave before handing their result/Await/throw back to C3.

Entry snapshots older captured history and clears that slot before taking an
actual pending VM event. History is released as DATA, without treating its old
uncatchable flag/private tag as a current event. After every native destructor,
new actual pending/captured cleanup events are owned before another destructor
can overwrite them. Current-event selection retains the first actual reason,
promotes the first actual cleanup fatal over ordinary, then retains that first
fatal over later ordinary/fatal cleanup. Returned values, temporary roots,
resolver roots and displaced diagnostic history all use this same escrow.

This implements the finite C5 priority pattern read from exact
7cfcf0513efa89390910bfb1e60a9b3c34cb053a,
worktrees/runtime-c3-c4-c5-callsite-20261017/vendor/quickjs/quickjs.c,
JS_PiGetAsyncIterator. That source is a read-only semantic authority; this repair
does not edit or claim qualification for C5/VM internals. Existing C3 ordinary
THROW/DATA/prebody review prerequisites remain separate Root-owned API work.

The mkdir body, ordinary rejection handler and direct factory/installer entries
now finish after their inner cleanup defers have run, while the escrow remains
active. Actual host/metadata failures are recorded before local JS-root cleanup.
Fresh allocation classification is scoped to the actual operation; normal
returned DATA is not classified by its tag/flag. No diagnostic toString is run.
Fatal completion is published as the same actual pending reason after slots are
drained. Source return/rejection DATA is handed back without invented fatalness.
As in the existing bounded native owned-exit contracts, mixed direct host OOM
with a pending primitive is not an admitted host profile; genuine native OOM
Errors and ordinary raw non-Error Source reasons retain their separate paths.

Request.complete checks entry before filesystem error/result allocation or
resolver settlement. A preexisting event aborts that completion. An ordinary
failure born inside completion can reject its actual inner Promise. Both resolver
fields are cleared and released in the same protected owner frame BEFORE the
Hub receives return/error. Consequently Hub's deferred Request.destroy performs
native-data destruction only on that path and cannot displace the propagated
fatal. Abandoned-task destroy guards its still-owned resolver cleanup separately,
without invoking either resolver; actual teardown events remain pending.

The worker Packet, filesystem algorithm, Group cancellation/join, capacity64,
native result publication and submit ownership-transfer contract are unchanged.
The reviewer found no additional concrete blocker in that worker scope at6ac7;
this is source review context, not an independent receipt or execution result.

New contrasting prepared controls use real opaque native finalizers that publish
actual VM reasons, including first-fatal plus ordinary/later-fatal cleanup,
ordinary plus first/later-fatal cleanup, old flagged captured history as inert
DATA, and actual Promise-resolver property finalizers. The completion control
sets a genuine pending fatal before completion, verifies the actual inner Promise
remains pending, then exercises the same resolver release/destroy sequence and
checks exact first-reason identity. It invokes no worker/file syscall; physical
filesystem controls remain separately prepared. All controls are UNRUN.

Independent source re-review is required. No formatter, AST, compiler, Node,
native helper or source generator ran. No original capture/golden was rewritten,
no default namespace activation is claimed, and no new VM/shared policy is
introduced. Full source/native filesystem effects, allocator/GC sweeps and ABI
qualification remain subject to Root's explicit controlled execution grant.
