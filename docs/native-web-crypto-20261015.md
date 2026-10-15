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

The exact native candidate `6894882c29cd21011b414e7fc23571329c528e99` passed
the Root-admitted Debug pair:155/155 compile steps and156/156 runtime steps,
3/3 tests passed. Compile PID73508 exited0 at20:44:51Z; runtime PID912 exited0
at20:45:13Z. The final full audit at20:45:27Z recorded zero drift for6573
candidate files,19546 compiler files,1774 scoped Node files, nine controls, and
all corresponding file inventories. All four compiled EXE/PDB hashes remained
unchanged, and both owned root PIDs were independently verified absent.

The test executable SHA256 is
`E03D00A1BF1D6BC78D371AC3EFA23DD82861A29F16783381C213397F865B7BEF`.
The strict pair owner SHA256 is
`3F34E4BAFCEF7DB6DD8E54BDADCB09B7A92046833AAA70F42BE77708283B9487`.
The Node inventory explicitly covers `node.exe` plus the complete npm directory;
unrelated launchers/corepack are excluded. The oracle executes Node builtins,
not Pi Source, and the fixture's full builtin source comparison remains368
entries plus the separately reported non-source `configs` entry.

`verification/web-crypto-node24-source52-20261015/webcrypto-native-debug-qualified-20261015.zip`
retains30 raw proof payloads and a manifest. Its SHA256 is
`7DB3EDE2288559F84AC5F7184553C86BD76CB608DDBA151805AC9F44B720B223`.
The adjacent `Verify-NativeProof.ps1` independently reopens every entry, checks
its raw bytes and the31-entry inventory, and validates Source52 and native
terminal summaries. Later commits add proof/documentation only; qualified code
remains identical to the tested candidate.

`build-native-web-crypto` and `test-native-web-crypto` are dedicated targets.
ReleaseSafe, full Pi, exhaustive allocator coverage, hosted profiles and public
activation remain false.
