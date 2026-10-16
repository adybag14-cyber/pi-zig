# Latest official 4dd2 source-only delta

Authority: official `earendil-works/pi` main `4dd2b149d155d7369de16ea4dc77c84e9f5ffb24`, tree `8daed06c8b2ac6787789642952fb3129f00e3d8d`. Latest release remains v1.3.0. The isolated native candidate starts at Root `9df0a241973968a109d81a1848f6a460c4dc98bf`; this packet does not advance Root's upstream target.

The genuine GitHub comparison from `0fbdbd3f8ab1876ac260c0f08226a400759323b8` contains four commits, 32 changed files, 207 insertions and 245 deletions. Seven runtime files change: model-resolver.ts; ordinary compaction.ts and branch-summarization.ts; Google, OpenAI Completions and OpenAI Responses converters. The remaining 25 files are tests, documentation and changelogs. `official-compare.json` retains the complete primary response.

`source4dd-full-manifest-before.json` freezes all 1970 files: 1927 tracked files plus 43 generated provider-data files inherited byte-for-byte from the immutable 0fb source. Generated module, catalog, package and lock manifests are unchanged. The full source-manifest SHA256 is `27729534F0272264238EAA3DCDC5FAA289DD82877034CF9DB2C2D72DE7A156F6`. The inherited dependency contract is explicitly labelled: all sixteen workspace manifests and the root lock were compared against the already audited 4954 authority and are byte-identical; this is not a new dependency execution audit. The 31064-file dependency manifest is reused from the retained `ai-model-operations-4954-20261015/reference-controls` packet.

## Native summary/default changes

Ordinary history, text-wrapper, turn-prefix and branch summary requests omit the own `maxTokens` property entirely. The history public reserve parameter and arity remain, but its value is no longer coerced. Prepared compaction no longer reads `preparation.settings`. Branch summary still reads/destructures its options and uses reserve/context-window arithmetic to select input. Prompt construction, reasoning selection, raw caller values, file tracking and completion retry/routing behavior are retained.

Typed ordinary summary callers leave `max_output_tokens` at its existing zero sentinel, so the configured model's normal output limit applies. Generic explicit overrides remain supported. The process regression now expects its configured 4096 model limit rather than the removed ordinary branch limit of 2048.

The four Xiaomi defaults become `mimo-v2.6-pro` in typed and VM factory paths. The actual factory helper previously embedded the historical 4954 default fixture as runtime data. It now captures a native ordinary mutable default map with all 41 declarations in exact Source order, shared for each Engine. Its properties are own writable/configurable/enumerable data properties, matching the Source object literal. `default-map-declarations.json` records the exact static declaration comparison. The immutable 4954 fixture remains unchanged. All four new default IDs already exist in the unchanged model catalog.

The independent durable harness compaction implementation is byte-unchanged upstream and retains its own 0.8 * reserve output cap. The independent bug-report implementation retains its own 4096 cap. Their native files are unchanged. They are separate Source contracts, even though durable/provider consumers of shared tool converters inherit the whitespace fix.

## Prepared genuine controls

`sdk-summary-latest4dd.input.txt` has 30 distinct original caller cases for actual official exports. It inspects own option keys and `Object.hasOwn(options, "maxTokens")`, raw reasoning/header/env identity, unused reserve Symbols and throwing coercions, throwing model maximum getters, prompt-before-reasoning order, inherited maximum getters, split and prefix-only compaction, inherited/live preparation getters, branch option destructuring and reserve arithmetic, and all ordered default declarations plus mutation. `summary-source-capture.mjs` imports actual Source functions and actual file-operation utilities; only the public stream callback is caller-owned. Branch random session IDs are observed by type/nonempty condition rather than fabricated constants. No Source function is replaced.

`source-observe.mjs` follows actual official workspace export maps and hashes observed modules against the frozen source/runtime manifests. A strict owner must additionally freeze this driver, observer and exact input through `PI_SOURCE_ORACLE_CONTROL_MANIFEST`, validate full Node1774/compiler19546/candidate/control/84-absence manifests before and after, and keep the owner alive until terminal and independent absence. Node must run the actual Source package v1.3.0, without a `PI_PACKAGE_DIR` override. The new source root still needs its owned dependency junction prepared before any granted launch.

The historical 45-case summary fixture is retained without changes. Its captured original output has 43 cases making 48 requests; those requests observe removed maximum option fields/keys under latest Source. Its metadata and null-messages cases make no requests. Reserve/max getter and compact settings traces also change in the applicable cases. Historical expectations cannot be used as a latest-source golden or overwritten.

## Qualification state

SOURCE ONLY. No Zig (including fmt/AST), Node, Source capture or native execution has run for this packet. No new expected JSON exists. Latest genuine capture requires a separate Root grant and successful terminal/full post validation. Native compile and replay require their own serial lease. The prior Models259 negative artifact, all historical snapshots/goldens/proofs, shared C/Engine/async helpers and Root worktree are untouched.
