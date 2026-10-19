# Native object Global cells

This source unit provides the actual object lifetime primitive needed by Node's AliasedBuffer Globals. A new cell holds one external strong object root. Its no-callback weak transition attaches to QuickJS's real target weak chain before releasing that root. A later Get returns one owned temporary value; it does not keep the target alive beyond that value.

The selected original authority is Node v24.13's pinned V8 Persistent/Global implementation and Node AliasedBuffer. The complete retained headers, implementation, native Local proof and acquisition hashes are in authority. The no-argument V8 SetWeak records the owning slot address and clears that slot before releasing the native node. Node makes each actual alias weak after the original publication operations. No public WeakRef construction or dereference is used by the production adapter.

## Native ownership

JS_PiNewNativeGlobal borrows a live object and returns one uniquely owned stable native cell. It allocates the embedded weak record at creation. The strong JSValue is an external counted root, not a wrapper-internal mark edge.

JS_PiNativeGlobalSetWeak performs no allocation. It installs the weak link before dropping the strong root and performs no later cell access: target finalization can clear and dispose the cell during that release.

Target disposal removes and clears the native records before any property or class finalizer can observe the object. Existing WeakMap, WeakRef and FinalizationRegistry records continue through their original two-pass cleanup. Get also rejects zero-reference targets waiting on the real DECREF queue and targets already marked for cycle removal, before their own free_object visit.

JS_PiFreeNativeGlobal publishes an empty disposing cell before reentrant native cleanup. It keeps the cell allocation valid until the owned value has retired. SetWeak and Free preserve the first actual pending reason, promoting a later actual fatal only when the earlier reason is ordinary. A retained flagged DATA value alone does not create an exception event.

The API is deliberately limited to the selected object Globals: owner VM thread, unique cell ownership, and release before JS_FreeRuntime. It adds no weak callback, ClearWeak, move, cross-runtime access or post-runtime operation.

## Controls and registration

The root src/native_vm_native_global_test.zig declares 18 controls. They use actual native-finalizable objects, real typed arrays and JS property roots, genuine cycles, the existing DECREF queue, actual public WeakMap/WeakRef/FinalizationRegistry records, direct VM allocation limits and actual JS_Throw events.

The controls distinguish a real external strong root from an incorrectly marked wrapper edge, an owned Get Local from kept-object retention, early weak reset from finalizer-time observation, queued and doomed targets from reachable objects, and normal cleanup from native reentry. Probe storage outlives the runtime; every native Global is freed before runtime teardown, including assertion-failure paths.

The install-only build-native-vm-native-global target uses the shared QuickJS library once. Its six-line build addition has no execution edge. Names and exact source hashes are recorded in source-status.json.

## Qualification

Production, all 18 controls and the six-line build addition have independent finite source reviews. The bounded receipts and their exact pins are recorded in source-status.json. No native build, Node run, generator, test execution or runtime qualification was performed for this unit.

The selected behavior follows original V8 Global ownership through the actual QuickJS root/weak machinery. It does not claim V8's moving-GC storage layout or V8 scheduling of object finalizers. The SDK adapter and complete BindingData graph retain their separate integration gates.
