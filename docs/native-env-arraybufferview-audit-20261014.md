This candidate adds only the `JS_PiGetArrayBufferViewBuffer` embedding accessor
and its private intrinsic test root. It does not activate a FileHandle class,
change the five existing file-I/O callers, or install a public DataView path.
The private intrinsic passed its Windows Debug target, all four compiled tests,
including the complete fifteen-field reference packet, real VM garbage collection
and every host allocation failure. Compile and runtime used the same frozen
5,491-file candidate. Both complete post-hashes had zero drift across original
source, candidate, references, compiler, linked vendor and Node binary. Runtime
receipt `env-filehandle-group-debug-arraybufferview4-runtime-first-e6220e1-20261014.json`
records owned PID46780, terminal and independently checked absent. ReleaseSafe,
POSIX native, kernel integration and public frontend qualification remain pending.
The earlier Debug8/stream4 receipt refers to
its frozen 5,482-file input, before this C accessor was authored.

The pinned QuickJS-NG base is v0.17.0, commit
`6d46d07d04041b40f4f49eaa7fdebe44c314c699`, with existing repository embedding
changes at integration head `31e5c660ad404639ed09824bcae76685a40c70b1`.
`vendor/quickjs/PI-ARRAYBUFFERVIEW-PROVENANCE.json` records original and candidate
file hashes, original Git blobs and the unchanged typed-array accessor hash.
The existing upstream license and safety predicates remain intact.

The wrapper borrows its input and returns an owned `js_dup` reference to the
backing ArrayBuffer on success. It runs on the VM owner thread and executes no
JavaScript property reads. Non-DataView inputs go through the existing
`JS_GetTypedArrayBuffer` brand, detached/OOB and backing checks. The original
accessor body is unchanged. After that successful check, the new wrapper uses
the interpreter's live element count for a length-tracking typed array. This
corrects the inherited initial-length result after resizing, inside the new
wrapper only. Offset, backing and element-size handling are unchanged.

Genuine DataViews use `get_dataview` and the interpreter's unchanged
`dataview_is_oob` predicate. Fixed views report their declared byte length;
length-tracking views report backing length minus offset, as the interpreter's
DataView byteLength getter does. The byte element size is one for this embedding
interface. All output pointers are optional, and exception paths return before
writing them. The old typed-array path's exception behavior is preserved.

Actual Node24.14.0 was captured in three separate complete packets under a
256 MiB heap and a fresh 2 GiB admission. Receipt
`env-node-view-source-capture-24-e6220e1-20261014-first.json` records owned PID37028,
which completed successfully and was independently checked absent. The full
1,902-file original source, 5,483-file candidate, four reference bodies, Node
binary and byte-identical materialized oracle had zero post drift. This is
reference evidence, not native qualification.

The intrinsic-span packet has fifteen fields, including genuine brand checks,
shadowed properties, typed and DataView resizable buffers, detach/OOB failures
and a retained backing reference after real GC. It includes the typed tracking
case that grows from six to ten bytes. The native intrinsic root compares this
whole packet, then repeats all its paths at every host allocation failure and
runs VM GC. Its C callback preserves caught exceptions without diagnostic
ToString calls or allocations; uncaught errors retain the ordinary outer
diagnostic boundary. No private OOM is identified by its name or message.

The normalized internal-FS binding packet has four fields. It uses actual Node
`internalBinding('fs')` operations with a genuinely owned descriptor and valid
DataView bounds. Scalar and vectored operations invoke none of the shadowed
buffer, byteOffset or byteLength getters. This packet is retained for subsequent
kernel-I/O qualification; the current file-I/O caller has not been changed.

The public FileHandle packet has seven fields and remains a separate frontend
authority. With explicit normalized scalar lengths, read and write each invoke
the byteLength getter twice. They do not invoke buffer or byteOffset getters.
The tested readv/writev cases and closed read invoke none. It also preserves
buffer identity and genuine pending-read/close behavior. These observable
frontend phases must be implemented before public installation; using the
intrinsic accessor does not substitute for them. No public-frontend comparison
or full FileHandle/Env qualification is claimed by the intrinsic test.

The subsequent frozen 5,492-file candidate passed a separate Windows Debug
integration batch: private byte-view I/O six tests, intrinsic four tests, existing
FileHandle eight tests and filesystem twenty tests, all with zero failures or
skips. `env-arraybufferview-io6-debug-batch-audit-20261014.json` retains the four
complete inventories and source/tool post-hashes. Every runtime input matched
the compile input, and all owned process identities were independently absent.
The I/O target includes both complete host allocation failure sweeps and real
VM GC. Explicit private `createArrayBufferViewFile` and
`createArrayBufferViewDescriptor` select the new accessor through the same
libuv worker, byte storage, pending references and descriptor close machinery.
Existing `create` and `createDescriptor` retain their legacy accessor selection.

The seven-field integration comparison uses a verification-only adapter for
already normalized explicit scalar views. Its empty-view/range checks preserve
the live byteLength getter phases. It does not implement the full public
overloads, argument-error surface, async fsCall semantics or class graph. That
complete implementation is still required before any public caller changes.

The private hosted workflow runs only the four intrinsic tests in Windows Debug
and ReleaseSafe, after genuine Node24 captures of all three complete packets on
Windows, Linux and macOS. Reference JavaScript remains fixture input, materialized
byte-for-byte outside the candidate checkout. Each runner freezes all candidate
and original-source files, all observer inputs, tool identity and relevant
environment controls. The native jobs additionally compare all 19,546 compiler
inputs to the existing pinned compiler proof and all 416 libuv sources to pinned
provenance. Hosted native admission is explicitly authorized at fresh eight GiB
for this sole-runner intrinsic target, after complete prehash; local admission
stays sixteen GiB. Each compile and runtime has its own unchanged deadline.
The workflow does not qualify POSIX native code, the I/O integration target, the
public frontend or the complete FileHandle graph.
