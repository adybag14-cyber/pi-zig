# Checkpoint 187 — complete Zig rewrite and reference retirement

Checkpoint 187 closes the Pi 0.84.1 rewrite, publishes the complete generated
provider catalog, and removes the reference TypeScript/JavaScript source only
after the native replacement passes its retirement gates.

## Final parity closure

- `src/ai/catalog_source.json` contains the exact published Pi AI 0.84.1 model
  data: 1,258 models across 39 providers.
- `scripts/generate_builtin_catalog.mjs` deterministically produces
  `src/ai/catalog_generated.zig` and rejects unknown or unprojected model,
  pricing, thinking, compatibility, header, and sampling fields.
- The runtime retains generated provider identity, mixed API protocols, model
  endpoints, static headers, credentials, sampling defaults, pricing tiers,
  thinking maps, and compatibility controls through initial selection, hot
  switching, and reload.
- The remaining OpenAI Responses `additional_tools`, vLLM
  `thinking_token_budget`, and custom models compatibility controls are wired
  into real request construction.
- Exhausted OpenRouter daily free-model quotas are terminal and do not consume
  the retry budget.

## Reference authority audit

The embedded source was tested in an isolated Node 24.14.0 environment before
retirement. Its own published data and source have five known inconsistencies
in each constrained package set: Cloudflare source/tests name catalog entries or
APIs absent from the published data, Fireworks tests name an absent turbo row,
the Baseten fixture expects text-only input while the published row accepts
images, and two coding-agent failures are environment/race assumptions. The
server suite passed 50/50 and all remaining root package suites passed. These
are reference source/data drift, not unimplemented Zig surfaces; their native
counterparts pass the generated catalog, auth-lock, clipboard/platform, and
provider tests.

## Native retirement gates

Before deletion, uncached GitHub Actions run `33201106025` passed on all three
hosted targets:

- Ubuntu: complete in 19m15s;
- Windows: complete in 21m26s, including provisioned SQLite FTS5;
- ARM64 macOS: complete in 4m22s, including the live-persistence process.

Each job passed generated-catalog verification, Zig formatting, the real-source
audit, ReleaseSafe build, the complete test graph, and the executable version
smoke test. Disabling restored Zig caches also proved that the earlier macOS
`InvalidExe` result was a stale cached executable, not a source or persistence
failure.

After deletion, the supplied Windows Zig 0.16.0 toolchain and the official
SQLite 3.53.4 x64 DLL (published SHA3-256
`deddee963c810d1eeac3ce5e15c7c41da21a1c54d7a39cf54fbf577d2f50de3a`)
passed the full graph again:

- module process: 990 passed, 27 intentional platform/isolation skips, zero
  failures;
- SQLite repository: 11/11;
- SQLite CLI process: 11 passed, six intentional repository isolates;
- SQLite live persistence: 5/5;
- ordinary and SQLite-enabled executable roots: 10/10 each;
- aggregate build graph: 13/13 steps.

All three ReleaseSafe Windows executables then built and reported version
1.0.0. Their hashes are retained in
`verification/checkpoint-187/verification-summary.json`.

## OpenRouter live gate

The user-authorized OpenRouter credential is stored through Pi's credential
storage; it is not committed. A ReleaseSafe free-model completion and tool loop
completed successfully earlier in this final lineage. The account subsequently
reached OpenRouter's 50-request daily free quota. The final runtime still
reached OpenRouter, received the real 429 response, emitted no retry-start or
retry-end events, and terminated the agent once. No paid traffic or credits
were used.

## Reference retirement

Only after those gates passed, the following were removed:

- 1,366 tracked files under `upstream/pi-main`;
- `upstream/source-archive/pi-main-20260823-194058.zip`;
- the three reference-only completeness and SHA-256 manifests;
- ignored dependency and emitted-build leftovers below the same reference
  directory (moved to the Windows Recycle Bin).

The original archive SHA-256 remains in `INPUT-PROVENANCE.json`, and Git history
retains the old files if forensic recovery is ever required. The final tree is
the independent MIT-licensed Zig rewrite plus the small JavaScript bridge used
to execute user-supplied extensions.
