# Native filesystem open permissions — source-only successor

## Completed supplier

This packet ports the complete original CheckOpenPermissions helper from Node v24.13.0 src/node_file.cc:2115–2142. OpenFileHandle calls that synchronous permission helper at line 2202 before selecting either its asynchronous or synchronous request route. An asynchronous open therefore still throws a permission denial synchronously.

The helper uses actual native Permission, Environment paths/private Map/debug/trace owners, target libuv flags, and intrinsic access-denied Error construction. It checks read before write, skips read only for exactly O_WRONLY, and requires write for every non-read-only mode or any O_APPEND, O_CREAT, O_TRUNC, or platform O_TEMPORARY side effect. It preserves the full native BufferValue span, including embedded NUL, for the error resource.

The accepted CommonJS permission Error owner gains the actual FileSystemWrite suggestion and scope string. Its public read entry remains semantically identical. Five finite raw edits factor the unchanged construction into a shared compile-time read/write body; the complete inverse restores donor 843EDF0598E3009FC2A7498230A4A019CA884AA1AB9F65F0050D73E0BDE4917D.

## Inputs and lifetime

checkOpenPermissions(s, inputs, keys, path, flags) consumes the original caller's already-created/namespaced BufferValue and validated native flags. Inputs borrow the genuine Permission and native Environment for the complete synchronous call, including inherited Error setter reentry. The helper requires the same Engine context and actual path, Map, debug and trace collaborators. It supplies no absent/default policy.

Both primitive Environment keys are rooted in the current Scope before policy/error operations. The native error message uses the same Engine's charged memory domain. Construction remains code/message/intrinsic Error/code Set, both permission/resource conversions, permission Set, resource Set. Nonthrowing false Sets are accepted; thrown permission/resource setters supersede the denial. The existing native code-Set empty-Maybe terminal policy is unchanged.

No new C ABI is introduced. Native Permission and its collaborators remain the current Main versions.

## Sixteen controls

The controls use real native Permission, paths, private Map, NativeDebugList, and Engine memory/context. Fixture-only callbacks choose primitive flags and call the actual helper; they do not impersonate a production filesystem binding.

Cases cover disabled enforcement; independent read/write grants; read-first denial; combined mode bits; write side effects; unrelated flags; live policy changes; fresh intrinsic write Errors; code-setter policy repair and key replacement/GC reentry; superseding permission/resource exceptions; nonthrowing false Sets; full/empty BufferValue resource spans; foreign native context/key rejection.

The fixture reuses only Main's charged Storage/cImport support. Its native lifecycle follows the retained CommonJS-read fixture without unrelated Module/cache/disk owners. All sixteen controls are uncompiled and unexecuted; no actual metadata or runtime/product qualification is claimed.

## Build and composition

The standalone projected build is Main build 183B59A721E0C0CBEC9604A860E75F2DB7AE8FDEA49675B2AC038F96767A7668 plus one 1,491-byte insertion. Install-only target: build-native-node-fs-open-permissions. Artifact: native-node-fs-open-permissions[.exe]. Filter: native fs open permissions.

Over combined12, compose only build-addition.zig.txt. Do not replace the newer full build with this projection. Select the permission-error successor only after the accepted CommonJS-read owner. Every old source packet and donor remains byte-exact. This new packet is excluded from current combined12.

## Production integration still required

Application bootstrap currently calls node_fs.installWithStreams. That public installer does not create the genuine native fs::BindingData/callback Environment graph. The accepted FileHandle packet completes its private template/publication owner and intentionally does not install an incomplete internal fs namespace.

Physical pi_uv_fs_open already exists in native_uv_tcp.c. The real OpenFileHandle BufferValue/path conversion and request selection, asynchronous AfterOpenFileHandle creation/resolution, and synchronous request/context route remain separate owners. This helper supplies their original permission decision without claiming those routes.

Production assembly also needs genuine Environment hook-failure, backing-allocation retry/terminal and trace owners. The bounded JS_PiGetNativeErrorConstructorName contract explicitly forbids treating unsupported classification as a negative IsStackOverflowError result. No guessed fatal policy, default trace callback, or one-attempt allocation replacement is installed here.

## Limits

Source authoring and static inspection only. No Main mutation, compiler, formatter, metadata, runtime, Node capture, bulk generator, public namespace installation, or default application switch. Root controls intake and native qualification.
