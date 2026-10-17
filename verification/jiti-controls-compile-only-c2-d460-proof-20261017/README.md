# C2 jiti body compilation and linkage evidence

This packet accepts **compilation and linkage only** for exact source
`d460a3258903fb4b4e724c4ddc7b266e394315fe`. It is a C2 component result,
not qualification of Main, runtime behavior, APIs, the default SDK/CLI or a
release. Metadata queries, test bodies, Node and the failing sentinel were
not executed.

[The raw ZIP](compile83-c2-d460-raw-proof-20261017.zip) contains all **155 audited
files**, with full inventories and the three retained failed attempts.
[public-manifest.json](public-manifest.json) lists every member's exact bytes
and SHA-256. [package-verification.json](package-verification.json) records
the packaging checks.

| Binding | Exact value |
| --- | --- |
| Archive SHA-256 | `BD844B9FBD8286E20A38A24F77EC5AE0F84037C1AC7275E52422694F36981905` |
| Archive size | 23,163,693 bytes |
| Members / uncompressed bytes | 155 / 287,106,441 |
| Source / compiler / controls | 11,101 / 19,546 / 14 |
| C2 C / H | `2FA2E26E35B7D5C45D1FFD3F6F10EE3A5DE9A984738486128399A20BD8E4D88D` / `341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB` |
| Compiler | Pinned Zig 0.16.0, SHA-256 `086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864` |
| Raw independent audit | `A4572FB40978B35823E5E7557E4F6724EF94DDE20EA7178F3AAFD7688176DF78` |

The one actual invocation built
`build-jiti-controls-compile-only-artifact`, Debug/LLVM, diagnostic-tests=false,
`-j1`, with a fresh output prefix. Zig PID 53212 exited 0 in approximately 20.612
seconds; the outer PowerShell PID 15540 exited 0 in 46.675 seconds. Exact live
identities, original grants, admissions, terminal receipts and recorded absence
are retained. Final recorded native candidates were zero. Complete pre/final
source, compiler and control inventories have zero drift and were independently
rehashed, including comparison to the original DEE compiler authority.

The source has 83 genuine typed call anchors over 27 actual modules. Those
signatures and static PDB name presence were checked. They are not 83 DLL
exports or executed behavior. The selected seven test bodies and deliberate
sentinel were compiled only; actual runtime metadata count remains unqueried.
The raw build summary reports 158/158 steps succeeded, 153 cached-labelled lines
and 5 success-labelled lines, including actual test and TypeScript parser
compilation. These line counts are retained without relabeling them as a new
dependency graph measurement.

**Cache exception:** Root explicitly authorized reuse of only the original
134316 run's two mutable, unsealed compiler caches. Their contents are excluded
and have no integrity, fresh-build or reproducibility claim. This exception
does not weaken the fresh output, exact source/compiler/control seals or owner
checks. Historical 7746/2C8, 51e2/6057 and 20e8/0DB runs remain failed compile
attempts with zero postseal drift and recorded absence; none is rewritten as a
pass.

Fresh local artifacts were exactly `bin/test.exe` and `bin/test.pdb`, with stable
pre/final/current hashes. Their payloads are excluded from the ZIP:

- EXE 49,801,728 bytes: `E2FFEE13E02E11F3CED94DC4641F7B057A684FE2512FD8335FC23385DA5DC416`.
- PDB 16,031,744 bytes: `AC21E44CE157B8C12F36A7FE8572F518F109B2D4167B65BA2506DAC5C940872F`.

The ZIP excludes executable, PDB, library/object and cache payloads. It includes
selected actual source, the C2/H and parser bindings, full inventories, raw
compile/outer streams and process-census/absence evidence. Raw `.stdout.bin`
members are observation streams, not executable binaries. The whole source and
compiler payloads are not duplicated; their exact commit and complete inventory
hashes remain available. Original `result.compile` contains an empty object
followed by a receipt; scalar `compile.json` is authoritative. Raw bytes retain
that historical quirk.

Packaging writes members in ordinal ascending order with fixed 1980-01-01 DOS
timestamps, zero external attributes and .NET Optimal Deflate. Two independent
ZIP writes were byte-identical, and every entry in both was decompressed and
rehashed. This is a deterministic packaging check for this implementation and
payload, separate from reproducible compilation. No new compiler, AST/parser,
native, Node, generator or runtime job was started to prepare this packet.
