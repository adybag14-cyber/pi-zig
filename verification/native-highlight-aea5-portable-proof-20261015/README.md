# Native highlighter AEA5 portable proof

This proof qualifies the actual eager21 computational highlighter at code commit
`aea5f178efdd3105d903553c8f5ff82bfbb25ea3`, QuickJS C SHA256
`47996DFE76080EEA68B13214B3D2EC351B8B0C4BDF759CD06084ABA9920F81EF`,
against genuine Source authority `b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb`.
The proof-only commit descends directly from AEA5 and adds only this directory.
It does not qualify newer Root common/C changes, whole191 readiness, exhaustive
C malloc failure coverage or public activation.

The terminal evidence covers exact genuine Source Deep7 self/distinct depths
32/64/128 under the original 1 MiB guard, Core74/eager21, trusted host OOM and
ordinary guest lookalike controls, and Legacy32. Legacy32 has five passing tests,
all 233 host failure indices, 514 targeted VM budgets and zero owner leaks. Core
host GPA covers every one of 22,272 indices exactly once in 250 disjoint ranges.

Run offline with PowerShell 7 and its standard .NET ZIP/SHA APIs:

```powershell
pwsh -NoProfile -File ./Verify-PortableProof.ps1
```

The verifier uses only this package. It makes no network requests, runs no native
jobs and reads no original machine paths. It verifies its own digest and the ZIP
digest in `package.json`, independently reopens and hashes every distinct archived
object, and checks the final proof's anchored SHA256, full inventories and control
identities, terminal receipts, raw markers and the exact range union. It also
checks genuine Source double captures and the preserved failed controller state.

To recover every included original byte into a **new** directory:

```powershell
pwsh -NoProfile -File ./Verify-PortableProof.ps1 -ExtractTo ./recovered
```

Original absolute paths are provenance only. Recovery writes them beneath the
new directory, for example `recovered/C/Users/adyba/...`; it never writes to the
recorded original paths. The ZIP stores `index.json` plus
`objects/<SHA256>.bin`. Each index row records an original path, length and object
digest. Identical inventories and empty logs share objects without losing their
individual original paths. All 3,588 included original files (520,246,328 bytes)
are recoverable from 2,038 distinct objects in the 11,549,830-byte ZIP.

The archive includes every actual range's admission/terminal/validation/posthash
receipts, complete raw stderr BEGIN/COMPLETE data, stdout, raw frozen candidate,
vendor and Source inventories and recorded controls. The compiler's full 19,546
file inventory, Source dependency/tool manifests and final 18 controls are
included. Functional fixtures, test source, actual computational closure, exact
C/header bytes, Source capture inputs/drivers/outputs and process identities are
retained. Additional older highlighter receipts, stack failures, allocator-index
319 negative and admission failures remain historical evidence; they contribute
no coverage to the AEA5 final union. The frozen candidate inventory describes the
actual tested worktree, including preserved unrelated WIP; it is not a claim that
all files were clean at AEA5.

The R4 native ranges completed successfully, but its original controller's
`OrderedDictionary` aggregate sorting failed with "Mixed union gap or duplicate
coverage". That failed controller receipt and raw stderr remain unchanged. The
separate corrected final validator casts records to typed objects, sorts integer
start positions, independently counts all BEGIN/COMPLETE indices and rehashes all
final inventories. No partitions were rerun to repair aggregation.

The anchored final proof is
`core-gpa-full-aea5-final.validation.json`, SHA256
`F9EB88656DF93E14314EB202113A10E55386EE87E651969F52DDB13026309217`.
The historical functional proof retains its earlier "GPA active" field; the final
proof supersedes that field while leaving its original bytes intact. Normal
16 GiB admission, maximum four coordinated roots, `-j1`, 300-second runtime,
120-second test timeout and 10-second settlement bounds were retained. Packaging
and offline verification launched no native tests and retired no caches.

Publication is to the public repository's checkpoint branch
`checkpoint/native-highlight-aea5-portable-proof-20261015`. It is a proof
checkpoint, with no main merge, release or activation implied.
