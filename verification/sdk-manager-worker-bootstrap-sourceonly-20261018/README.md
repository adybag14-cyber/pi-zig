# Real worker manager bootstrap, source only

Base Root e95f9da1c71bf04e498ecbad8e68079e37e3e8c2, retaining actual File2 AF,
Auth, Exec, semver, Chalk, internal builtin loader and C435 helper intakes. No
Main, shared Scope, Engine or C/H change, job or backend selection occurs.

The real worker installs Bindings schemas before evaluating extensions:
native_worker.runOwner/runSdkFile -> Bindings.installSchemas -> native_tui.install
-> native_editor.install -> native_sdk.install. That original installation sets
native_sdk_class and publishes the current public coding-agent module. The
genuine application factory subsequently calls native_sdk.managerImports, whose
old guard required native_sdk_class==0 unless its private projection was already
cached. Therefore the real production bootstrap order rejected the genuine
factory with RequiredOriginalSdkManagerModuleOwner, despite already having
created the actual managers.

The correction captures the SAME SessionManager/SettingsManager values from
the actual original install record at that producer boundary, before guest code
can mutate reflection properties. It never reconstructs from prototype.constructor
or installs an opaque alias/extra class. The private import record is not a new
public module. Normal SDK class/method bodies and declaration order are unchanged.
The actual public install body is factored under a balanced diagnostic/current
event boundary; original managerImports delegates to the new private owner.

The existing fresh private route invokes that same static original installBody,
builds its two-manager projection with raw checked gets and C435 ownRoot, records
completion before retiring the temporary full record, then publishes. Normal
worker installation captures the projection only after its actual body succeeds
and that capture's roots/diagnostic retirement succeeds. Capacity is reserved
before the private cache commit. Typed storage/reservation OOM is recorded
before incoming/projection retirement. No Complete record, user-selected
installer callback, placeholder constructor or mutable constructor reflection
is accepted; the comptime installer argument is the actual private SDK body at
its sole callsite.

Five authored controls cover real TUI/editor-before-factory identity, mutated
prototype.constructor getters, the fresh private route, actual pending-before-
armed-GPA/no-class-effects, and ordinary/raw-private diagnostic cleanup before
projection publication. They are UNRUN; actual metadata is unknown. The new
build target is install-only and keeps canonical test.exe/test.pdb. These controls
do not select the unified application graph or qualify the current public SDK.

This correction does not finish public index publication or replace the old
worker public factory/session exports. The new unified owner still returns only
its genuine factory subset. Full original index exports and actual native worker
selection require the real completed owner and subsequent gates. Public Node
loader/Jiti, FS/frontend/TTY, Source comparison, current VM/G2/Promise/generator,
Original64/SDK27/166/Agent32 and production activation remain external. Existing
partial class-install/VM registration failures are sticky and require teardown;
no successful retry is invented. Existing inner SDK/TUI factory Scope/producer
and expression-GC frontiers are not silently declared repaired by this outer
capture/retirement correction. No original expected corpus is changed.
