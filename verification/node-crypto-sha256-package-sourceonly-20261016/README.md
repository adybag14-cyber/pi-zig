# Native SHA256 dependency for actual PackageManager storage

Source-only implementation checkpoint8c7aa654 adds native_node_crypto_hash.zig.
It uses std.crypto.hash.sha2.Sha256 directly, with a separately owned state for
every returned Hash. No subprocess, runtime bridge, synthetic digest, or JavaScript
crypto implementation is involved. No Node/compiler/native job ran for this
packet, and node-crypto-sha256-package.json is deliberately absent.

Latest4dd package-manager.ts2183-2189 has one crypto call chain:
createHash("sha256").update(interpolatedString).digest("hex").slice(0,8).
The package-storage owner confirmed this exact eight-character result. Actual
native_sdk_package_assembly.Inputs.crypto expects a namespace with createHash.
Root can construct native_node_crypto_hash.create(engine) once per module graph
and supply that same namespace. This leaf has not activated or wired a registry.
Current crypto_random/WebCrypto surfaces do not supply node:crypto.createHash.

The initial declared contract is exact lower-case sha256 with omitted options.
Other algorithms/aliases and supplied options fail explicitly with
PI_UNSUPPORTED_CRYPTO_ALGORITHM / PI_UNSUPPORTED_CRYPTO_OPTIONS. Unsupported
encoding names and non-string update encodings fail with
PI_UNSUPPORTED_CRYPTO_ENCODING. This does not claim Node's full alias/options,
unknown-encoding fallback, Transform streams, copy, symbol-state reflection,
constructor prototype replacement/subclassing or other crypto exports.

The required string path converts WTF8 from the VM through the existing native
binary_encoding codec, replacing isolated UTF16 surrogates for UTF8. Every
update consumes actual bytes and returns its exact receiver. Seven known
encoding families and attached TypedArray/DataView spans have prepared controls;
public view buffer/byteOffset/byteLength overrides do not supply native bytes.
Detached/out-of-bounds/resizable/shared edge behavior and invalid-input diagnostic
parity remain outside this first package contract and unqualified. No general
BufferSource parity is inferred from the prepared attached-view path.

Known digest encodings use native byte-to-text codecs. Falsy output encoding or
"buffer" uses existing real node_buffer.fromBytes; the caller must initialize
the native Buffer namespace before that optional raw-output path. Exact package
hex output does not need Buffer. The leaf captures any actual pending VM error
from inherited Buffer prototype installation before propagating it.

Hash state is stored in an opaque runtime class, not writable guest properties.
Each state has its allocator/engine owner, Sha256, cached32-byte digest and
finalized flag. The finalizer destroys it once; a separate module owner traces
prototype, captured error constructors and captured intrinsic DataView accessors.
Finalizer/marker tolerate an unattached owner during partial allocation failure.
No process-global JS values or Engine fields are introduced. Ordinary native
factory/constructor/update/digest functions retain their proper names, arities,
constructibility and shared module prototype roots.

Digest checks finalized before output-encoding coercion. Coercion may update or
digest the same receiver; there is no second finalized check after it. The native
digest bytes are cached, and finalized publishes only after output succeeds.
Fresh privately tagged errors crossing the leaf retain their exact reason through
rethrowRecognizedAllocation; direct OutOfMemory remains in the error union.
Ordinary guest throws propagate by identity. No forgiving catch changes them.

Exact contract sources inspected statically at the official Nodev24.14.0 tag:

- https://github.com/nodejs/node/blob/v24.14.0/lib/crypto.js (createHash binding).
- https://github.com/nodejs/node/blob/v24.14.0/lib/internal/crypto/hash.js (update,
  digest, finalized and output coercion order).
- https://github.com/nodejs/node/blob/v24.14.0/src/crypto/crypto_hash.cc (byte
  decoding, native digest cache and output encoding).
- https://github.com/nodejs/node/blob/v24.14.0/src/crypto/crypto_util.h (input spans).
- https://github.com/nodejs/node/blob/v24.14.0/lib/internal/validators.js and
  https://github.com/nodejs/node/blob/v24.14.0/src/api/encoding.cc (encoding).

The58 prepared original observations cover metadata;12 UTF8 cases including
NUL/surrogates/block boundaries; actual package short names; incremental,
independent/shared/borrowed receiver behavior;11 input encoding cases;7 text
output encodings;6 real Buffer outputs;5 attached byte-view cases; coercion,
reentry, ordinary raw reason and finalized ordering; freeze/forged/public-state
controls. source-only-controls.json contains only static IDs/counts/input hash
and provenance, with no expected answers. capture-original.mjs imports the actual
Node crypto builtin, verifies exact Windows Node24.14 executable hash and version,
and writes only an explicitly supplied raw output path inside container evidence.

The driver alone is not an accepted capture or a process owner. A future Root
grant must use canonical bounded owners, sanitized environment/no-network
controls, verified runtime receipt/authority, full before/post/final seals,
explicit absences and independent process absence. No capture grant is present.

Five native tests and build-native-node-crypto-sha256 /
test-native-node-crypto-sha256 targets are prepared, unrun. Original comparison
reads the required expected file at runtime and fails if missing; it checks
Node/input authority and all58 rows exactly. Other tests prepare retained GC
state/standard SHA256abc, explicit unsupported scope, and every Zig allocation
failure across construction, real bytes, native Buffer and encoding roots. The fifth prepares exact fresh private Engine-tag reason retention through digest coercion, with guest-catch bypass. This injector is not a C-malloc sweep.
QuickJS/C allocator failure coverage remains a separate unprepared gate. No
allocation sweep, native test, original parity or whole-package pass is claimed.
