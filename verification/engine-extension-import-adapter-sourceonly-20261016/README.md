This is an opt-in, source-only Engine extension adapter over the independently
reviewed private graph C prototype. It has not been formatted, AST checked,
compiled or executed. It does not install or select the default SDK/worker path.

The isolated base is Root170b6631cf3dce95ea88a5dc7d8f52cf341f771f. Its vendor
baseline was verified as C E2F98895...B2D1D3B / H341CF06F...7052AB before the
reviewed source chain through b09a8f65 was cherry-picked. No older vendor copy
or whole Engine/worker implementation was transferred. The adapter adds one
new native_extension_import_adapter.zig leaf and nineteen Engine lines.

Host API:

```zig
const session = try engine.createExtensionImportSession(.{
    .io = actual_io,
    .namespaces = actual_virtual_namespace_bindings,
});
const pending = try engine.startExtensionImport(session, physical_base,
    extension_path, c.pi_js_undefined());
```

The caller owns `pending` and its Await. The current Source39 subset starts one
root per session. Reusing that host session for a second root is rejected; old
factory dynamic imports keep the exact C graph and captured resolver afterward.
The root must be a physical module; virtual/builtin roots are outside this
extension-file entrypoint. Only explicit configured virtual authorities and
registered node: names select shared values directly. An absolute name in the
ordinary CJS/native module registry cannot bypass physical kind admission.

All twenty Source VIRTUAL_MODULES names are required real inputs. Every binding
must reference a registered native module and the exact cached export-authority
object. Aliases in the same Source group must name one canonical C module, so
the adapter does not manufacture another namespace wrapper. It constructs no
Models, TypeBox, SDK registry or empty namespace. These checks establish supplied
identity, not qualification of the actual module implementations; that remains
the composition owner's responsibility.

Records and copied names use the existing aggregate-memory ChargedAllocator;
the hub's own host allocation is reserved explicitly against that same owner.
The opaque public session is validated by membership before its record is read.
The handle class ID lives only in native hub storage, with no ID or record in
guest module caches. Callback function pointers, SourceLoader value, std.Io and
deep-copied binding names are captured for context lifetime. Actual namespace
objects remain mutable with their Source identity. Reconfiguring SourceLoader
is an explicit unsupported host operation for a captured session.

Graph2 normalizes through the captured session before ordinary runtime policy.
Canonical virtual names precede disk resolution; registered Node builtins reuse
their existing canonical node: module. Ordinary Engine.normalizeModule and its
external TypeBox preference are unchanged. The adapter does not call registerModule
for private TS bytes. It reads real physical files, invokes the existing native
TypeScript transform, compiles in the exact graph and initializes physical metadata
before evaluation. Shared ESM/CJS/JSON use existing shared-zero JS_LoadModule and
the actual SourceLoader/commonjs authority.

Shared kind decisions are retained across sessions, including the measured
package.type transition. Private decisions are retained per graph; a newly loaded
root gets fresh bytes and a fresh graph. A genuine resumable AsyncFunction owns
one outer Promise and one evaluation Await. Its private null-prototype state
holds the exact compiled-module locator and boundary generation. Callback errors
preserve raw JS identity; current host OOM is fatal, with exact fresh private tags
checked before classification. A just-failed js_malloc boundary marks its own
exact pending reason without name-based or historical classification.

The Engine deinit seams free owned JS roots while the context is valid, retain
opaque records through context/runtime destruction, then free charged records
and release their owner reference. None of this is graph garbage collection.
Context pinning and long-lived reload growth remain explicit production gates;
terminal allocation/teardown and anchor-only context controls are still needed.
The existing native TS parser's internal transient allocations have not been
proved against the aggregate owner. Charging retained records and source/output
buffers does not establish accounting for the entire transformation pipeline.

Explicit unsupported cases include nonempty/explicit import attributes, arbitrary
bare packages/tsconfig aliases, .mts/.cts/.tsx, TypeScript inside node_modules,
no-type JavaScript using ESM syntax, and source-loader replacement. The measured
Source39 physical .ts/.mjs/.cjs and .js package boundaries are the intended first
qualification scope. Physical resolver realpath/case/symlink/alias behavior has
not been compared with Source and cannot inherit qualification from its ordinary
resolver tests.

Further activation gaps remain: native-failure-to-transform fallback; full jiti
default/Proxy/JSON self-default interop; failed shared dependency retry/error
identity; eval/generated-function import policy; concurrent fresh roots/TLA;
actual Source48/39 filesystem replay, callback/getter/Await order and full stack
columns. The C raw graph tests do not establish those behaviors. The adapter is
not a claim that existing shared-failure behavior is the Source contract.

No native expected JSON or golden is generated. Prepared controls and native
admission must come after this implementation review. The immutable original
Source53/44/15/48/39 packets and physical fixtures are preserved elsewhere.
