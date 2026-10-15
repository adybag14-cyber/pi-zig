# Private file-tool presentation qualification, 2026-10-15

This packet qualifies a narrow native component path. It does not qualify the
complete Pi rewrite, public SDK activation, every file syntax, the complete
191-language loader, or all allocator failure positions.

## Implemented path

`native_sdk_builtin_presentation.attach` now attaches real read, write and edit
callbacks to actual native builtin definitions. Listing and shell callbacks are
the clean historical implementations from
`1496d8c6f2504faa477f48a6f6af1d0cfee289c3`; their earlier qualification is separate
from the new file-tool tests. Read range and renderer helpers, the write cache,
and path-language mapping were reviewed before intake. The path-language
mapping origin is `ba4b181b2c49662ec815ad164e5309ad2eee48d6`.

Edit preview uses the actual native asynchronous filesystem access and read
functions, strips the BOM, normalizes line endings, applies genuine fuzzy
multi-edits while preserving untouched original lines, and computes the real
display diff. Its synchronous Myers line/word diff, whitespace postprocessing
and KMP overlap follow actual installed jsdiff 8.0.4. The implementation binds
only the default synchronous paths needed by these tools, rather than claiming
the full public jsdiff class/options/patch API.

Native `fs.constants` supplies the four platform access flags from `std.c` in a
null-prototype object with the actual readonly descriptors. This is not a claim
that every other Node filesystem constant has been implemented. The edit preview
function has the genuine AsyncFunction prototype, name and arity, no own
`prototype`, and is nonconstructible.

The themed frontend requires an explicitly installed actual native syntax
runtime. A truthy requested language unsupported by that runtime fails with
`NativeThemedHighlightGrammarUnavailable` before the ordinary Source catch.
Missing grammar bodies therefore cannot be represented by successful plaintext.
The ordinary Source catch is retained for supported actual grammars. Neither
this packet nor the text tests installs a fabricated syntax implementation.

## Actual Source authority and observations

Source authority is unchanged
`b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb`. The separate latest-upstream audit
reported no read/write/edit renderer or edit-diff changes through 5ab7fe7; this
packet still names the actual b45 execution authority rather than claiming it
executed the later checkout.

The Source executions used actual Node 24, unchanged Source module bodies,
actual installed dependencies and actual GC. Every run froze and rechecked the
complete Source 1,965-file, runtime 31,064-file and npm/tool 1,774-file authority
inventories. Native runs additionally froze the complete candidate inventory,
1,316 vendor files and 19,546 pinned toolchain inputs, plus controls. The pinned
compiler is Zig 0.16.0 with SHA-256
`086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864`.

| Observation | Terminal result | Scope |
| --- | --- | --- |
| EditDiff54 actual Source capture | passed, Node PID 45380 | 20 word diffs, 10 line diffs, six display diffs, six genuine-theme diff renders and 12 normalized/fuzzy multi-edit cases |
| Native EditDiff54 corrected build | passed, Zig PID 5236 | actual default word/line/apply/display/render bodies compile |
| Native EditDiff54 corrected runtime | passed, Zig PID 44836, 9/9 tests, 83 ms | all 54 captured results match, testing allocator releases the normal run |
| FileRenderer28 raw Source capture | passed, Node PID 44412 | diagnostic capture retaining the original absolute fixture URI |
| FileRenderer28 portable Source capture | passed, Node PID 44620 | 28 actual component/preview records, 21 path-language cases, actual async-function and access-flag metadata |
| Native file renderer corrected build | passed, Zig PID 45788, 33 s, maximum RSS 2 GiB | actual native definitions with attached read/write/edit callbacks compile |
| Native file renderer runtime | passed, Zig PID 36028, 10/10 tests, 427 ms, maximum RSS 19 MiB | all Source28 records and metadata match; selected five real operation allocation failures release every allocated byte |

The normal native resource policy was maintained: fresh 16 GiB free-memory
admission, at most four native roots, `-j1`, 1,320-second compile ownership,
300-second runtime ownership, 120-second test deadline and 10-second host await.
All complete pre/post inventories for the terminal passing native runs report
zero drift. The final renderer run froze 5,625 candidate files. Its full
candidate snapshot is retained in `receipts/`, along with vendor and compiler
snapshots. The shared original Source/runtime/npm inventory files remain in the
external evidence authority named by the frozen registries and their hashes.

The fixture programs and expected records are preserved without text checkout
normalization by the repository's existing `* -text` policy. EditDiff54 input
SHA-256 is
`0695e7457307012d69fe4a595d25ed31ba620cb9c4bf5410ead4ec268c4681c5`;
FileRenderer28 input SHA-256 is
`0f1dd564d9f7cf2e3eb83d2da022b5ceb46a1af5894b9192f7d3440d8b979cd1`.

The portable renderer caller projects only its own temporary file-URI prefix to
`file:///PI_TEST_FIXTURE/`, identically on Source and native executions. The
Source implementation bodies and the remaining rendered bytes are unchanged.
The first raw-URI capture is diagnostic; the second shared-caller capture is the
portable comparator authority. No expected record was edited to match native
output. Source programs run on Node only as verification authority; product
implementation remains Zig and direct C.

## Exact limits

Read/write qualification here uses text files with an unsupported `.txt`
extension. It exercises real text formatting, controls, image fallback in a
mixed result, truncation, compact resource headings, constructor choice, and
actual edit preview pending/success/error transitions. It does not qualify
highlighted read/write bodies, all image/nontext result variants, streaming
highlight-cache behavior, or adversarial component/getter/reuse combinations.

The selected ownership run measured 4,377 allocations after real setup and
injected failures at offsets 0, 1,094, 2,188, 3,282 and 4,376. Each returned
OutOfMemory and freed all allocated bytes. This operation-only measurement is
not the allocation universe of the separate full-engine exhaustive tests.

`test-native-edit-diff-ownership` and `test-native-file-renderers-ownership`
implement the complete bounded/sharded failure universe but have not been run
to complete coverage by this packet. The local qualification is Windows Debug;
there is no new Linux/macOS, ReleaseSafe, hosted CI or application activation
claim. The file renderer runtime also proves the edit-preview dependency path,
while the larger EditDiff54 corpus was tested earlier in the same isolated tree
with the same diff body bytes. The Root integration head still needs its own
combined exact-head gates.

## Preserved negatives

The immutable receipts retain the initial eight draft declaration-shadowing
compiler errors, the remaining inferred integer type error, and the test-only
duplicate Theme module setup failure. File renderer compilation also exposed an
omitted historical visual-line-preview dependency, the write constructor's
sentinel-pointer/slice conversion, and a baseline obsolete `WriteFailed` arm in
`node_directory.joinPath` after `node_path.join` became OutOfMemory-only.
Only these concrete compiler/setup failures were repaired; Source expected
records were not changed. The selected allocation failures intentionally emit
an OutOfMemory diagnostic; the final process receipt and 10/10 test summary are
the terminal authority, not a search for the word `failed` in stderr.

## Reproduction and remaining gates

Compile the named component target before its runtime target. Keep the same
normal admission, immutable controls and complete pre/post inventories; the
owner and wrapper scripts in this directory encode those constraints.

```
zig build build-native-edit-diff-source -Doptimize=Debug -j1 --test-timeout 120s
zig build test-native-edit-diff-source -Doptimize=Debug -j1 --test-timeout 120s
zig build build-native-file-renderers-source -Doptimize=Debug -j1 --test-timeout 120s
zig build test-native-file-renderers-source -Doptimize=Debug -j1 --test-timeout 120s
```

Complete ownership qualification requires the original full-engine probe's
measured universe per platform/profile, a fixed shard count, and every shard's
`EXHAUSTIVE_ALLOCATION_COMPLETE` receipt. Collect every reported interval and
prove their union is exactly `[0,total)` with no omission or overlap; do not
substitute the five selected offsets or the 4,377 operation count. Choose the
shard count from actual bounded-run timing, and preserve the unlimited baseline
and fail-index universe. All six platform/profile combinations remain separate
qualification work.

The static installed grammar index has 191 canonical factories; 21 eager bodies
leave 170 missing bodies. `missing170-grammar-inventory.json` records actual
names and authority hash without representing any missing body as implemented.
TOML is an alias of `ini.js`, while GraphQL and HCL are not in this canonical
191-language distribution despite the Source file-extension mapping. A real
complete-index import must re-register all 191 in Source order, including the
21 eager factories, on the same core. Root assigned that independent lane to
the catalog/highlighter owners. The lazy draft remains unbound until actual
factories and genuine Source settlement comparisons exist.
