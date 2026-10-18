# Actual core/exec.ts supplier — prepared source only

`native_sdk_exec.create(engine, Inputs{spawn, wait_for_child_process})` returns
an owned private module namespace with the genuine AsyncFunction `execCommand`
(name execCommand, length 4). Create it once for the actual core/exec module
graph and share its function. Nothing is default-registered or activated here.
Both imports are genuine captured functions, called bare with an undefined
receiver. There is no command runner, Source host bridge, fake ChildProcess,
custom wait implementation, session-command or PackageManager execution alias.

The physical base is Root c3888788a1af513f3e8ba9f4659221a22b2888e9. The actual
child transport is a separate Root composition prerequisite: FS's reviewed
`native_child_process_sdk_transport.create` / `createForFrontend` graph supplies
`child.node.spawn` and `utilities.waitForChildProcess`. Its public child,
Socket/EventEmitter, wait, IO pump, lease and host inputs must be real. They
are not replaced or copied into this unit. A function-shaped stand-in does not
satisfy this contract. The create validation is not a provenance certificate.

The pinned Pi primary is core/exec.ts Git blob
`5afe9ec367257ae4b7bd62fd1502e9b1fa275684`, SHA-256
`1A55E7416847EA0C548775B28596BB817C8CD4AA97BC36B8DA7403959FCD350F`.
Current c268 and retained 8efd bytes match. The original restored runtime's
published exec.js map embeds exactly the same TypeScript bytes. Four selected
original JS/map copies match the original 31,064-file manifest; the complete
runtime EFEC acceptance is byte authority only, not a new capture execution.
The Pi license is retained. The wait module's own source/version qualification
belongs to its transport owner; this unit consumes its real function.

There are **zero Source Await boundaries**. Calling execCommand creates the
VM's real async outer Promise and return-adopts Source's one `new Promise`
expression. The live global Promise lookup precedes executor allocation. A
custom constructor can retain/call the actual arrow executor; its length is 1
and each invocation gets its own lexical cells. It captures the original raw
command/args/cwd/options values. The cells are ordinary private null-prototype
objects, traced through real native callback captures, not a global registry.

The executor preserves this Source order:

1. Actual spawn with `{cwd, shell:false, stdio:["ignore","pipe","pipe"]}`.
2. Initialize stdout/stderr/killed/timeoutId and one killProcess closure.
3. Optional signal reads, pre-abort kill or actual abort subscription.
4. Optional timeout reads/comparison, live setTimeout call and stored handle.
5. Actual stdout and stderr optional `on("data", arrow)` subscriptions.
6. Bare waitForChildProcess call, live `.then` before its success arrow, then
   live `.catch` before its failure arrow. Executor returns undefined.

killProcess sets its lexical killed flag before the live proc.kill("SIGTERM")
call and creates the actual 5000ms force timer afterward. The force callback
reads proc.killed before optionally calling live kill("SIGKILL"). No force timer
is cleared beyond what Source does. Data callbacks save the old accumulator,
then call actual data.toString and perform real binary addition. Both terminal
handlers clear a truthy timeout first, reread options.signal and remove the
same killProcess callback, then resolve a real object in the original key order.
Success uses code ?? 0; rejection uses code 1. Rejection input is ignored DATA,
with no name/tag/flag checks. A cleanup/resolve throw follows the actual chained
Promise semantics; no synthetic result or fallback completion is supplied.

All owned scopes finish through the unchanged SDK completion helper SHA-256
`41AAFFBFED0B2B598D51E8B46432E1B53A373BA101DC7B0F4C396201E65432B6`.
An actual raw pending reason is recorded before a successful returned carrier
can retire. Direct root-storage OOM is published before releasing its root.
Successful property statuses check actual events before another Source step.
The local construction holder accepts only an independently retained
`NativeInvocation.first`, never captured diagnostic/rejected-input flags. It
holds the first actual callback fatal while the constructor is active; later
retained-executor invocations cannot pin new events into a past construction.
Holder storage is charged and traced, including partial-construction cleanup.
No Engine/Scope/C/H/shared helper or global Promise semantics are changed.
Shared VM/AF/ordinary-callable factory and finalization frontiers remain their
own prerequisites; this packet does not qualify or replace those implementations.

The proposed original caller has 9 ordered rows: real child output/zero/nonzero,
timeout, pre-abort, live abort, missing/invalid command, live option getter order,
and actual function metadata. The actual child program is user command input;
it is not used by the implementation. Original captures use the restored
published Pi module and its genuine original dependencies. The identical caller
is embedded for the actual native frontend observation. The five native control
entries cover metadata, start/accepted-row comparison, actual pending-before-
entry identity, and a real native fatal through a real Promise construction.
No child/wait callback graph is fabricated. IO controls require a separately
granted real owner, matching original acceptance, full pumping/retirement and
all exact child/descendant absence receipts.

Everything is uncompiled and unrun. Neither expected nor native output JSON
exists. No Node/compiler/parser/AST/formatter/generator/native jobs ran. No SDK,
transport, GPA, GC, cancellation timing, full VM or default-selection claim is
made. Root alone owns execution, qualification and narrow integration.
