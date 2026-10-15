# Upstream refresh authority, 2026-10-15

The fetched `earendil-works/pi` main head is `5ab7fe74c400097b386662205cd93900695b8a71`, committed at `2026-10-15T14:49:50Z`. The latest GitHub release observed in this refresh is `v1.2.0`, published at `2026-10-12T23:03:53Z`. The source packages still declare `1.2.0`; unpublished main behavior must not be described as an already published `1.2.1` release.

Authority is the detached checkout `C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015`. Its Git source archive is `pi-upstream-5ab7fe7-immutable-20261015.tar`, SHA-256 `bb1b83d360c004472059628ea7594fee16232eb3931a58a1f07e2aba67c3df72`, in the external update evidence directory. The previous source checkout remains at `b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6`.

## Behavioral delta from b06c1f2

There are eleven commits touching 42 files. Their net runtime contracts are:

- Anthropic and Bedrock Claude retain error tool-result images. The text-only error result replaces each image run with `(image attached after the tool results)`. After all tool results of that turn, the same user message receives `Images from the error result of tool call <id> (<name>):` and the images. Non-error results and non-vision image downgrades keep their existing paths.
- Anthropic generated thinking metadata permits `off` for normalized `claude-opus-5`, `claude-haiku-5-5`, and `claude-haiku-5.5` even when mid-conversation effort is supported. Normalization strips the optional OpenRouter prefix and dated snapshot suffix. Opus 5.5, Sonnet 5.5, Fable 5.1, and Mythos 5.1 continue to reject disabled thinking.
- Retry recognition includes `The service is temporarily unavailable` through `service.?(?:is.?)?(?:temporarily.?)?unavailable`.
- The final Kimi Coding generator uses Chat Completions at `https://api.kimi.com/coding/v1`, matching the b06c1f2 final contents. The intermediate revert does not survive in the net delta. Catalog publication raises `MINIMUM_PI_VERSION` from `0.80.7` to `1.2.1` because older clients ignore the model API for this provider.
- `@earendil-works/chord/output` becomes the public home of bounded output and progress helpers. It exports `OutputSkip` and `utf8ByteLength`; durable output/truncation imports move there. UTF-8 byte length counts lone surrogates as replacement characters, three bytes each. Existing buffer retention behavior is retained.
- Remote Chord references reject supplied contexts not made by Chord and contexts from another host with `invalid/foreign_ctx`. The check now uses the called reference's binding host, not the supplied context's own host. Expired and aborted checks still apply.
- SQLite durable storage accepts an optional table/index prefix. An explicitly provided prefix must match `[A-Za-z_][A-Za-z0-9_]*` and must not start with `sqlite_`, case-insensitively. Omission preserves the historical unprefixed schema; explicit empty string is invalid. Every migration and runtime query uses the selected identifiers, including schema version and metadata tables. Changing prefixes does not migrate old data. Node and Cloudflare entry points expose the option.
- The Nix wrapper appends Node to PATH. Test-only model references use available Claude Sonnet 4.5 names.

The OpenAI Completions codec, partial JSON parser, dependency pins, and coding-agent read/write/edit renderers are unchanged between these two commits.

## Qualification boundary

The previous native catalog identifies Pi 1.1.0, source `19cb534c3b6e3871458a8fa59e98f0312c50e995`, and typed catalog SHA-256 `439c53478c84ed27a58f8b54e1c3bd45810e5a969515b4e3666a3898d51ee22f`. It remains historical evidence. This refresh must obtain matching official generator output before changing the native catalog provenance. Neither a source refresh nor catalog component success qualifies the full native Pi application or authorizes removal of the compatibility host.

## Official latest generator and source preparation

The unmodified latest generator ran with `--strict --json-only` against eight captured public metadata responses, all HTTP 200. Its typed output SHA-256 is `4334227667568186df17628973e890a2582a44c4ef67f16621704387ae73c8c9`: 1,608 chat, 59 image, and 40 classifier models, totaling 1,707 models across 42 providers. The complete output bundle has 87 files. Compared with the historical native input, 122 typed identities were added and 46 removed. The raw typed catalog is retained in the verification packet without modification.

Generator post-verification found no drift among 1,924 tracked source files, 1,925 source paths, five launch controls, or 1,774 pinned Node tool files. The official hydration script then generated 43 provider data files from that fresh typed input. The resulting complete Source manifest contains 1,967 files. Hydration preserved all tracked files, all 31,064 dependency/runtime files, all 1,774 Node tool files, all controls, and the expected path inventory.

All 365 external npm lock records match the previous b06 source. Preparation checked 281 installed package metadata pins and explicitly retained 80 absent platform-optional dependencies and four unchanged stale duplicate workspace paths. Those absences are documented in the dependency audit; they are not silently classified as installed. A new dependency junction belongs only to the latest checkout. The source observer maps current official workspace exports, including `@earendil-works/chord/output`, to the latest original TypeScript source, checks each observed module against the frozen manifests, and rejects old workspace class implementations.

At this preparation checkpoint the native import, native tests, publication dry-run validator, and offline generator replay remain pending. The generator and hydration receipts establish source and catalog-input preparation only.

## Catalog component qualification

The subsequent native import used the official generated typed input, exact Git source archive, and existing native maintenance importer. The importer checked the archive commit and declared package version before writing `catalog_source.json`. The native generator produced `catalog_generated.zig`, and its generated-file checker passed. Neither generated file was edited manually. Complete 5,627-file native source inventories and all 19,546 pinned Zig tool files were checked around each phase; only the two catalog files were permitted to change during import/generation, and later test phases permitted no input changes.

The focused `test-latest-catalog-data` target passed eight tests in Debug and eight in ReleaseSafe. It checks complete typed model metadata against every native catalog row, exact provenance and counts, additions and retirements, current pricing, classifier/chat lookup separation, disabled-thinking metadata for Haiku 5.5 and Opus 5, the Kimi Chat Completions contract, provider defaults, and exact deterministic projection bytes. It compiles the catalog data closure without requiring application or C runtime compilation. The existing broader catalog/Bedrock target remains available.

The unmodified official publisher's `--dry-run` validator passed. It produced a local `publication.json` descriptor with source `5ab7fe74c400097b386662205cd93900695b8a71`, revision `sha256-4334227667568186df17628973e890a2582a44c4ef67f16621704387ae73c8c9`, and minimum client version `1.2.1`; no objects were uploaded. Offline replay of the unmodified generator consumed exactly the eight captured responses and reproduced all 87 original generator files byte for byte.

The first replay wrapper compared the full output directory after the dry-run publisher added `publication.json`, so its directory comparison failed with 88 original files versus 87 replay files. The generator process itself passed, and its frozen inputs had zero drift. The retained corrected artifact validator uses the original 87-file generator manifest, separately verifies the publication descriptor, and reports zero byte mismatches and zero replay inventory drift. The negative comparison receipt is retained; no generator output or prior receipt was rewritten.

`verification/upstream-5ab7fe7-20261015/qualification.json` records the terminal catalog component result. Full native Pi qualification, public activation, compatibility-host removal, and publication remain outside this result.
