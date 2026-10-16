# Component compilation and metadata proof, prepared for publication

This package preserves original local proof bytes for compilation and metadata
queries only. It is prepared staging for Root's separate Main intake and commit;
this preparation does not publish it or change Main/product source.

There are **29 observed metadata entries and zero runtime test executions**.
The entries comprise 25 named declarations and four overlapping anonymous
storage entries. Actual raw stdout streams contain Zig 0.16.0 version and
metadata frames only. The sealed driver/helper path sends query_test_metadata
and exit, with no run_test command. Metadata discovery is not a test pass.

| Original packet | Exact source head | Retained result |
| --- | --- | --- |
| root-components-compile-20261016 | 2a36a0d847aa8b2455f30c838f288fdd06317f1f | Failed: three Zig shadowing errors; no successful metadata group |
| root-components-compile-v2-20261016 | a17e2bcafde50029a01152118f2406dccda0274c | Crypto compiled/metadata 6; packet failed at subsequent classic compilation |
| root-components-compile-v3-20261016 | 67965e9f0ba1f6f10e71f5d51ec03bec010eb55c | Classic compiled/metadata 6 and iterator 8; packet failed at subsequent writer compilation |
| root-components-compile-v4-20261016 | 156e89d14bb2671840d0337cdfbf995c5a8dcdc6 | Writer compiled/metadata 9; compilation-and-metadata packet passed |

Successful executable SHA-256 values recorded by the original receipts:

| Component | Local executable SHA-256 |
| --- | --- |
| Crypto | E934BA32F19E29953FD08768887705A3258B94CA8A7F2F4EC3C5E4E274F9AA44 |
| Classic | 41561711406A70B5DB04244745FC84E202EA1263AE23818F771E18ABF444CFFC |
| Iterator | 9C6FFA4D38562E2D6AD285B9B88B0D9155D27F987F502292ECE9C8AD80EAB78B |
| Writer | AE771402FDC7407CFB9998540C380AD40034568B4CDA174D2823C5D992B97C24 |

The source repairs correspond exactly to the retained errors: Root c614f674
renames shadowing stream locals/parameter; caf73bf2 fixes the throwing !Input
payload path and enum array-index type; 38a8e606 converts accessor-name sentinel
pointers to slices. The independent supplement verified before/after Git blobs
against those Main commits and found no additional qualification source deltas.
C2FA/H341 remain unchanged. The evidence does not establish one rebuild of all
components at the final head, whole Main, stream semantic parity, Node/Source160,
or runtime/application qualification. The C3 Graph0 native queue is still pending.

raw-proof.zip contains every regular top-level file from the four named original
packets, under a packet-name prefix, and byte-exact independent review receipts
and audit scripts under independent-review/. Selection never traverses output
subdirectories. Drivers, grants, before/between/final seals, results, metadata,
raw stdout and stderr remain intact, including every failed attempt. Raw stdout
.bin files are protocol observations, not executable binaries.

No out/, bin/, executable, PDB, DLL, object file or cache content is included.
**The compiled binaries remain LOCAL, are not saved in this public package, and
may be recyclable only after Root determines no live dependency needs them.**
This task does not move, recycle or delete them. Their recorded hashes do not
mean public binary availability.

member-manifest.json records each exact archive member, original provenance
path, byte length and SHA-256, plus the zip SHA-256. package-verification.json
records independent decompression/hash comparison for every member, a full
post-package original-source recheck, and hashes for the manifest, this README,
packaging script and copied independent files. No original observation or
receipt was rewritten. Historical absolute paths inside those original bytes
retain their original meaning; archive prefixes locate the packaged copies.

The copied primary independent receipt has SHA-256
3A6445E64181D7CCAD022472DADA0436CC33DEB2CF4FC0BE6D2E12B1099386CC.
The copied supplemental receipt has SHA-256
1E000C7A0F9109C727351D79AD2A205F06B5562239D672ECEAF16023BD6DCBAE.
The audit accepted 8 successful and 3 failed owner receipts, with zero remaining
owner incarnations, complete source/compiler seal checks without drift, and
retained fresh-16-GiB admission probes. Failed packet statuses stay failed.

Only local byte-preserving packaging and verification were performed here.
No compiler, native test, Node reference, Source capture, generator, product
edit, Main edit or qualification execution occurred during this preparation.
