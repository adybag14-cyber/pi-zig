# Pinned Pi model catalogue refresh

The catalogue now follows Pi commit
`19cb534c3b6e3871458a8fa59e98f0312c50e995` and its immutable
`nix/model-catalog.json` revision:

```text
sha256-439c53478c84ed27a58f8b54e1c3bd45810e5a969515b4e3666a3898d51ee22f
```

The reviewed raw input is `models-8a9-pinned-439c5347.json`, whose SHA-256
matches that revision. The Git source archive is bound to SHA-256
`5da1185d5c3bd4ba55618c38ee0524defd5cb0797c9aaa0ead7507387472f2f0`.
The existing native maintenance importer verified the archive's Git PAX commit
and `@earendil-works/pi-ai` package version `1.1.0`, verified the raw catalogue
revision against its bytes, and validated the typed data before writing
`src/ai/catalog_source.json`. The native catalogue generator then produced
`src/ai/catalog_generated.zig`; its matching `catalog --check` passed.

Compared with the prior `6fb2e781` / `d09b976f` catalogue, the refresh adds
8 identities, removes 30, and changes metadata for 199 retained identities.
The native source now holds 1,631 models from 42 providers: 1,544 chat,
61 image, and 26 classifier models. The six existing native runtime/local
entries are appended separately and are outside those upstream counts.

Examples of actual data changes include the new `opencode/fledge-alpha-free`
chat model, the new `openrouter/perplexity/pplx-decider-v1-27b` classifier,
retirement of `anthropic/claude-haiku-5-5`, and the Sonnet 5.5 cache-read price
changing from 0.1 to 0.2. The classifier stays in the operation catalogue and
is excluded from ordinary chat model lookup.

Regressions check the exact pinned schema, provenance, provider/type counts,
and lossless original metadata for all 1,631 generated models. They also
exercise public exact model-reference lookup for the seven new chat entries,
retired entries, the free model's limits and reasoning metadata, updated
pricing, and the renamed classifier's operation API.

Reproduce generation with the pinned Zig 0.16.0 toolchain:

```text
zig build maintenance -j1 -- import-catalog <models-8a9-pinned-439c5347.json> 1.1.0 19cb534c3b6e3871458a8fa59e98f0312c50e995 <pi-upstream-19cb534-immutable-20261012.tar> sha256-439c53478c84ed27a58f8b54e1c3bd45810e5a969515b4e3666a3898d51ee22f src/ai/catalog_source.json
zig build maintenance -j1 -- catalog
zig build maintenance -j1 -- catalog --check
zig build test-latest-catalog -j1 --test-timeout 120s
zig build test-maintenance -j1 --test-timeout 120s
```

This updates model data and its provenance. The certified upstream baseline
in `src/config.zig`, package/API identity, native-default setting, and Node
extension bridge retain their existing values.
