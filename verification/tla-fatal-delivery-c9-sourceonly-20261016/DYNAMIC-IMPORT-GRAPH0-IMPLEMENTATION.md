# Explicit-base genuine queued import: source-only successor

The exact 5141149eee943fcee489f1cd7b78f3e701678e07 proposal was independently
closed by async_c_review_resume before Root's conditional source-only authoring
grant was used. This successor adds one C ABI declaration/entry point and
extracts existing guest import setup into a shared private helper. It does not
select a production binding or change Engine, module loading or Promise policy.

JS_PiDynamicImportGraph0 borrows a primitive-string basename and a specifier.
It rejects a nonstring basename without coercion and duplicates a valid one.
The helper consumes its owned basename on capability failure and through all
existing done/exception paths. Specifier ToString, options processing, intrinsic
capability creation, exact five-argv job dispatch and cleanup use the original
implementation. The guest wrapper still captures script/module basename and
performs AtomToValue/error cleanup before invoking that common setup. Existing
JS_LoadModule remains immediate and untouched. No second Promise is created.

Physical absolute/NUL path admission remains the sealed SDK helper's obligation.
The new C operation never consults an ambient frame and has omitted options and
attrs. It adds no context ownership: existing JSJobEntry.ctx is raw, so the host
must keep its context valid until execution/cleanup. No module-token GC claim,
private graph identity, opaque graph handle, filename alias or ABI serialization
change is introduced.

Seven prepared raw-ABI controls in src/native_dynamic_import_graph0_test.zig use
actual lazy C-module export getters, the public Promise.prototype.then getter,
actual queued jobs, registered source modules, TLA, and the real loader
normalizer. They cover ordering before initialization, a throwing public then
getter with the import still queued, no/foreign ambient-frame explicit base,
GC after releasing caller-owned string references, distinct import Promises
and concurrent canonical namespace, ordinary coercion/module rejection identity,
noncoercing basename admission, and normal host-owned pending-job teardown.
The seventh control adds a distinct host-owned JSContext, a loader compiling
the actual module in its callback context, and public execution-context hooks:
set marker A, enqueue, set marker B, release A's caller owner, GC, then require
the first job/hook to carry A and the foreign context. Module/global realm
markers prove execution in that foreign realm. Both contexts remain host-owned
through all job/value cleanup. This does not claim the raw job ctx owns itself.
The JS used here is test input executed by the linked C VM. It does not implement
the production import operation or stand in for actual SDK getter controls.
The prospective build snippet is unselected; actual compiled metadata count is
unknown, including any imported anonymous storage test.

The exact C/H successor and prepared controls require independent implementation
review and an explicit Root native grant. No compiler/formatter/AST, Node,
generator or native test execution is claimed. Qualified a3 focused34/core116
and C2FA/H341 receipts remain immutable; this additive header has a new identity.
Root main's C2FA intake remains authoritative and is not modified by this lane.

Required later integration controls remain explicit: actual sealed getCreateJiti
and getVirtualModules cached selector Promise identity/admission with complete
real authorities; Graph2 private caller to this explicit Graph0 operation does
not inherit the caller graph; guest private capture/owned anchor must remain
before coercion and transfer once into its seven-argv path when composed. Graph2
is not present in this successor and is not copied from an older C tree.

Inherited ignored JS_EnqueueJob return, JS_LoadModuleInternal void attachments
and exception conversion/INIT/allocation-fatal policies remain separate. This
delta deliberately keeps those existing import semantics rather than claiming
that scheduling extraction qualifies them. Ordinary/catchable behavior is not
relabeled and rejected-value flags/tags cannot establish an active fatal reason.
