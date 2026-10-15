# Native Pi WebCrypto prerequisite

`native_web_crypto.install(engine)` installs the native `Crypto` and
`SubtleCrypto` constructors and the genuine identity-branded global `crypto`
instance. `create(engine)` returns an owned standalone instance. Installation
must occur once before guest code; callers subsequently read guest globals and
properties normally, preserving OAuth PKCE's guest mutations.

The supported operations are secure `getRandomValues`, secure RFC4122 version4
`randomUUID`, and async `subtle.digest` for SHA-1, SHA-256, SHA-384 and SHA-512.
The secure bytes come from admitted `std.Io.randomSecure`, without deterministic
production substitutes. Digests use native Zig crypto primitives and return
genuine VM Promises of genuine ArrayBuffers. Successful digest settlement is a
VM job; native hashing copies/consumes the input before the call returns. Node's
worker-thread scheduling relative to unrelated I/O is not qualified here.
Other crypto methods and SHA3/cSHAKE are absent/unqualified.

Source52 is the actual pinned Node24.14.0 builtin implementation, executable
SHA256 `63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088`.
The retained builtin source packet SHA256 is
`0CD86676BB2A46A4E772D1FD8BB3D00FCA658383BC388846DCC796547DC79263`.
The live process has369 natives entries; the packet contains368 source entries
and excludes only the non-source `configs` entry. All368 sources are compared
byte for byte inside the actual Source child. The oracle imports only Node
builtins, with no Pi, SDK or external dependency execution claimed.

The actual Source52 child PID25764 exited0, created
`2026-10-15T20:20:08.8284209Z`. Full posthash passed for1774 Node files,
4217 candidate inputs, six controls and the candidate file inventory. Expected
JSON was published only afterward, SHA256
`888E237C0AA9A1C9E6E40A8BEFA5CEFE83BCA0864A0407B6C5E24630E342B136`.
Failed attempts1-3 are retained: they first exposed the packet's source count
and its intentionally omitted `configs` entry; all three posthashes passed
and none published a golden. The owner hash is
`877B86D7A8F442BAA3EC0A6AEBDC9E651E635139F1EB66252AED8D4147D77E1C`.

Controls include four native digest families and lowercase normalization,
ArrayBuffer, typed-array and DataView windows, classes/brands/descriptors,
quotas, secure RNG and UUID shape/difference, async error returns, algorithm and
byteLength getter order and exception identity, copied inputs, detached inputs,
and rejected shared buffers. Native tests also exercise retained methods through
GC and mutation of the public Promise constructor.

Native compilation/runtime are pending Root admission. `build-native-web-crypto`
and `test-native-web-crypto` are dedicated targets. Full Pi, exhaustive allocator
coverage, hosted profiles and public activation remain false.
