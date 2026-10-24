# Complete FileHandle callback template and StreamBase publication

Status: authored source only. No Zig compiler, formatter, metadata query, native executable, Node reference capture or generator ran for this packet. The 25 test declarations are unexecuted. Root alone selects integration and qualification.

## Selected source

- projected/src/extensions/native_node_file_handle_template.zig: the complete FileHandle prototype and its actual retained native inputs.
- projected/src/extensions/native_node_async_wrap.zig: finite successor of the accepted Write20 AsyncWrap template owner.
- projected-v2/src/native_node_file_handle_template_test.zig: all 25 declared focused controls. The earlier projected test and authored fragment are preserved and unselected.
- projected/build.zig: standalone build over the sealed External/GetExternal build. Integrators must compose only build-addition.zig.txt with a newer combined build.

The exact patch and all selected/base pins are in source-intake.json. Every earlier Dispatch13, Write20, StringWrite18, Writev32 and External10 source remains unchanged. The selected QuickJS C/header and StreamBase dispatcher are exactly the accepted External packet versions; this packet adds no C ABI.

## Production interfaces

The real fs assembler first owns its shared Environment, AsyncWrap template owner, Controller, native immediate Queue and actual BindingData target. It then calls:

1. native_node_async_wrap.configureFileHandle(engine, known_template_owner, inputs)
2. native_node_async_wrap.publishFileHandle(engine, known_template_owner, actual_fs_binding_target)

FileHandleInputs contains the genuine Controller, Queue, read and close traces, StreamBase backing-store allocator, async callback trace and optional native diagnostics. Controller and Queue must belong to the same Environment/Engine. The original native trace, allocation and reporting imports keep their existing Environment-lifetime contract. No replacement worker, fake allocation policy, fake trace, or guest-visible ownership carrier is created.

Configuration retains Controller and Queue and owns primitive handle/error/oncomplete keys before publication. It supplies the actual Bundle identity to both ShutdownWrap and WriteWrap request bindings. The Bundle back-pointer is borrowed and is not a second strong root or mark edge. Concrete Handles retain the original BindingData, whose native Global retains the Bundle through native requests. Constructors and methods also trace their captured Bundle. Repeated identical configuration is idempotent; changing any live collaborator fails.

The FileHandle constructor and stored instance template remain unavailable until this complete owner is configured. publishFileHandle admits only the current actual BindingData wrapper and performs the original SetConstructorFunction operation on that target. It does not fabricate a partial internalBinding('fs') namespace or select an application runtime factory.

## Original behavior preserved

The actual constructor receives the complete argument vector. Its existing native construct-call and Int32 CHECKs remain terminal; optional offset/length values use the original Number-only conversion. Genuine newTarget and simple-template cache behavior remain in the existing template owner.

The prototype installs close/releaseFD, fd/external_stream/bytesRead/bytesWritten, all ten StreamBase methods, isStreamBase, and onread in original order before the live parent-prototype lookup. Methods have the original names, zero length, non-constructor behavior and default writable/enumerable/configurable attributes. Accessors have zero-length, empty-name native API functions and non-enumerable/non-configurable descriptors. The pinned V8 AccessorPair source explicitly leaves getter/setter names uninferred.

Receiver conversion precedes the concrete FileHandle signature. Genuine derived instances pass; a Proxy, a prototype imitation or another AsyncWrap kind fails before native callback argument CHECKs. A cleared genuine wrapper still passes signature admission.

StreamBase callbacks use the accepted real dispatcher, counters, trigger scope, read owner, CustomBuffer listener, Shutdown, WriteBuffer, four fixed string encodings, Writev and borrowed External. FileHandle DoWrite intentionally remains the original UV_ENOSYS behavior. There is no fabricated write success.

Public releaseFD discards the native Release() descriptor result and returns undefined. It performs AfterClose without closing the descriptor. onread remains a wrapper internal-field edge even after native Handle retirement; its setter retains the original IsFunction native CHECK. Actual close returns the original Promise and actual shutdown uses the existing native request/oncomplete path.

Publication keeps ordinary Set semantics: a setter can reenter the completed constructor, a false Set succeeds, and a failed Maybe takes the original native fatal path. Failed GetFunction(...).ToLocalChecked() likewise remains terminal.

The C VM represents the accessor functions with the existing traced native callable owner. This packet does not claim V8 heap-layout, debugger side-effect metadata or lazy FunctionTemplate heap-materialization equivalence. Reflective identity, default names/lengths, descriptors, receiver signatures, call behavior and actual owned native roots are explicit.

## Focused controls

The 25 declarations cover the unconfigured gate, actual-target admission, native collaborator identity and retention, exact prototype order/attributes, constructor arguments and derived receivers, all method/accessor signatures, Proxy trap avoidance, inherited AsyncWrap methods, wrapper slots after native retirement, dead/absent stream distinctions, uint64 Number rounding and fresh borrowed External identity.

They additionally drive all six public write entries through actual WriteWrap to FileHandle UV_ENOSYS, real libuv reads into a user buffer, real shutdown/oncomplete, actual close/Promise identity, the absent-object native factory, instance-template cache behavior, newTarget fallback, init-hook reentry, ordinary publication setter/false-Set behavior, and constructor lifetime after removal of the private cache and fixture owner roots.

The shared native fixture is reused unchanged. Its CloseReq observation callbacks cast the CloseReq layout; the shutdown control therefore supplies narrowly typed observation callbacks for the different actual ShutdownReq layout. Neither control fabricates request completion or native I/O.

Positive controls do not execute process-fatal cases such as calling FileHandle without new, a non-Int32 descriptor, a non-function onread setter, or a throwing publication setter. Their original native CHECK/Maybe/ToLocalChecked owners are preserved and source-reviewed. Separate fatal-process qualification remains Root-owned.

## Integration and remaining qualification

Apply the accepted predecessor chain first. Replace AsyncWrap only after verifying its exact Write20 donor, add the new template and selected test root, and compose the 1,838-byte build insertion with the current combined build. Do not overwrite newer Module/application build additions with this standalone projection.

The genuine production fs/bootstrap assembler must supply the actual configured native collaborators and call the two interfaces above at its original binding initialization boundary. Complete fs namespace/application factory publication remains separate. No default switch, production Node bridge removal claim, print/RPC startup claim or whole-app completion follows from this source packet.

Rebuild the QuickJS library from the accepted StringWrite/External C/header chain before linking the future selected controls. No new C ABI is introduced here. Then qualify compiler/linking, exact selected metadata, runtime ownership/cleanup, public constructor behavior and regression compatibility under Root's existing native controls. All previous source/donor evidence remains immutable.
