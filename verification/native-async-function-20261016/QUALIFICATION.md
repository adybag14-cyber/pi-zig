# Native AsyncFunction Windows Debug qualification

Exact tested source: `d01090424356fde9b2ab89753285f9b4ae2ea0f8`, published at [checkpoint/native-async-function-debug-qualified-20261016](https://github.com/adybag14-cyber/pi-zig/tree/checkpoint/native-async-function-debug-qualified-20261016). All20 changed checkpoint files passed SHA-addressed public raw-byte readback. This proof-only successor preserves those product bytes.

The bounded Zig0.16.0 LLVM Windows x86_64 Debug gate passed **26/26 tests**, with **156/156 build steps succeeded**. Actual binary metadata contains all25 planned tests and the anonymous `extensions.native_durable_storage.test_0` imported entry. The exact10 AsyncFunction subset is retained. Coverage includes genuine Node Source42 observations, true async brand and receiver/return semantics, GC state, native stack frames, ordinary/bound/proxy source, START/resumed raw hostOOM, host allocation sweep and genuine C allocation quotas, eight inherited async-generator tests, six inherited JSON tests, and direct borrowed ArrayBufferView span behavior.

The complete readable receipt and attempt ledger are [QUALIFICATION.json](QUALIFICATION.json). Byte-exact raw evidence, all negatives, actual binary and controls are in [native-async-function-debug-evidence.zip](native-async-function-debug-evidence.zip), with [evidence-manifest.json](evidence-manifest.json). All221 payloads plus the manifest were independently decompressed and hashed successfully before publication.

| Identity | SHA256 |
| --- | --- |
| Actual installed/cached test executable | `4E6A7B95575CC520265F6AC61553616EA27F03DAD2F7D29298644DB0CDD28ED8` |
| Evidence archive, 52,716,904 bytes | `09F829E26BF5C0B2435CAC56285EBD4A979F47A099288C740E5A3548618C62C2` |
| Archive payload manifest | `7CD6DCE7C6BF070530974F91C697CFCD824F711DB3A61F653D8097167F07CAEC` |
| QuickJS C | `33DFB18C9A930D3967A089DF0B28B65AF88B7665B7ADD725AED30FCB8F046FD2` |
| QuickJS H | `E3189DA8F918993FB567D07DF32E91CECD12C6666D9E9B1D68A6C65A15CEC37E` |
| Native AsyncFunction helper | `61C4A3302BA8CF6C13CC051D6CA2CA281B4D4BC325A4C105A072182AE8B88819` |
| Ten AsyncFunction tests | `4828E0BD9F18094EB31B5F9B8A6ED546D27D0EF8952DC0CD21ABB8FBDCE85013` |
| Shared Source42 expected JSON | `52DD975CA6C7CCE1D9BF8BB13B763122862B7849CFAACFAED8906038C3AF9653` |

## Process and source provenance

Fresh16GiB/zero-other-native admission passed before each phase under Root grant `ROOT-ASYNC26-16GiB-OOMFIX-20261016`. The original proven Body owner was pinned to `B91945EF77F91388BB8792959AB29C3A49505B5381BA0994723AC0FC6E0502AB`; neither failed revised supervisor was reused. Build used `-Doptimize=Debug -Duse-llvm=true -j1`, with 1,320 seconds externally allowed. Runtime invoked the matching cached Zig target, with an enforced120-second per-test deadline and300-second external deadline. Source42/GPA guest tests use their10-second await setting. Actual metadata was read through the30-second query/exit-only protocol before runtime.

Compile PID70296, metadata PID66364 and runtime PID66908 exited0 and their original identities were independently absent. A fresh post-run native inventory was empty. Runtime completed at `2026-10-16T10:53:46.4553244Z`; complete posthash finished at `10:53:57Z`.

Full before, between, after-metadata and post checks reported zero path/hash drift for candidate8014, vendor1316, compiler19546, complete Node directory1838, original executable/npm pins1774, controls, all21 Source42 authority files and both executable copies. Both genuine Source42 captures remain byte-identical to the expected fixture. Historical raw inputs/receipts were retained unchanged; the original mixed-line-ending input is preserved separately with its original hash.

## Preserved failures and causal correction

The archive and ledger retain all phases rather than replacing negatives with the final pass:

1. `admitted1` stopped before launch: the canonical1774 Node executable/npm rows were initially mistaken for the complete installation. Read-only inspection identified64 additional Corepack/shim files; the successor froze all1838 while retaining every original pin.
2. `admitted2` failed build configuration on inherited duplicate target names. Root's existing `f2e5a7aa` two-line Response target-name repair was adopted without merging their scopes or dropping tests.
3. `admitted3` compiled QuickJS successfully but failed the adapter's Zig `allowzero` state-pointer conversion. The trusted live C slot now uses an explicit non-null conversion.
4. `admitted4` compiled and returned actual26 metadata entries, with all25 planned names present. The strict count25 controller stopped before tests. The extra anonymous imported entry was retained in a separate actual26 list; no filter was removed.
5. `admitted5` ran actual26 and reported24 passes, one failure and one crash. Root and independent Body review established that the Engine hostOOM helper marks private identity but leaves the generated error catchable. The AsyncFunction adapter therefore previously rejected its outer Promise instead of propagating the fatal native error. START's unexpected owned result was not freed on assertion failure, causing a secondary teardown assertion.
6. `admitted6` passed26/26 after the adapter-only fatal marking and immediate START result cleanup. The exact same assertions and C quotas remain. Global Engine OOM semantics, C/H, shared promise behavior and user-thrown errors were not changed.

## Narrow Root intake

[ROOT-INTAKE.patch](ROOT-INTAKE.patch), SHA256 `292330E5C50E3DAA2B153F240B8A4FCEEA505BDAC14DE3CD193DA88AA9D73CCD`, adds only the reviewed C/H delta, final helper, ten tests, inherited-cohort root, two fixtures and12 build-target lines. Its [identity ledger](ROOT-INTAKE.json) names all resulting product hashes.

The patch was checked read-only with `git apply --check` against Root head `0da226522f4db5da2b711f9587320af7fe811849`, retaining C baseline `12A7F02A...855D` and H baseline `F3B6F51D...1062`. It omits this isolated tree's older Claude, RuntimeCredentials and URL build hunks. It contains no Engine, HTTP, Body, upstream or TypeBox replacement. Actual Root intake has not been performed by this work.

Qualification is limited to the exact Windows Debug component cohort. It does not establish ReleaseSafe, Linux, the current composed Root head, full Pi, main promotion or a release. The historical Source-only checkpoint `8f97c86e` remains published with its original `native=false` scope.
