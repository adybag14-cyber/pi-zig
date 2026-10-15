Native virtual-models production source checkpoint
================================================

Authority is unchanged upstream `4954d760504c11df9b2cbdc040346107b6a8153d`,
`packages/coding-agent/src/core/virtual-models.ts`. The native namespace lives in
`src/extensions/native_sdk_virtual_models_production.zig`.

Call `create(engine, actualImports)` once for the module instance. It returns an
owned namespace with both constants and all six runtime exports. `actualImports`
must contain callable `isModelType` and `lazyStream` from actual pi-ai. Both are
snapshotted as import bindings. Missing imports throw; there is no synthetic
SDK.State/catalog/authentication fallback. The caller owns the returned value.
Direct public Zig bodies are also available for the five pure exports.
`withVirtualModels` is exposed through the namespace so its private unrouted
stream function has the same identity across provider wrappers.

Provider spread preserves enumerable string and symbol properties. Filters are
destructured before spread and invoked with an undefined receiver. Physical
stream and catalog methods retain the original provider receiver. Physical
chat models with colliding ids are hidden while non-chat models remain. Optional
catalog/filter functions retain the source's nullish and truthiness rules.
Arrays returned by a provider filter are spread through their actual iterators,
with abrupt-completion close behavior provided by native_js_values.Iterator.

The module delegates streaming to the actual imported lazyStream. Its native
async callback throws the original unrouted error only when entered; no host
awaitValue, sleeping or scheduler ticking occurs. Scope owns temporary values,
native_node_function supplies ordinary/arrow function metadata and GC-visible
captures, and native_agent_async supplies promise capability/settlement.

Routing, retry cancellation and branch-state persistence belong to upstream
ModelRuntime and AgentSession, outside this source namespace. That integration
must use the actual ModelRuntime production implementation; the old
native_sdk_virtual module is not reused.

Validation status
-----------------

Pinned Zig 0.16.0 SHA256
`086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864`
formatted the new module, and git diff whitespace checks passed. Formatting is
an AST check only; no native semantic compilation or runtime execution has been
authorized or completed at this checkpoint.

The 36-case verification caller imports the actual unchanged Source namespace,
which loads genuine pi-ai dependencies. It covers constants, defaults, state
identity, successful-response lookup, branch selection, provider catalogs,
filters, receivers, getters, symbols, iterable spreads, shared function identity,
metadata, raw errors and actual lazy error stream events.

First observation `sdk-virtual-models-source36-first-20261015` passed with Node
PID 56988 and exit zero. The strict owner verified complete source 1970 files,
dependencies 31064, Node 1774, compiler 19546, candidate 7523, controls 9, all 84
declared package absences, complete Source inventory and caller identity before
and after execution; every drift count was zero. PID 56988 was independently
absent afterward. The genuine captured expected has SHA256
`47E8DA4A56FFF3491D7D2317AA93BD9B0779AA118ABE0BE0E6D816B43498EA46`.

That first observation ran at base commit 463bb453 with four explicitly hashed
new files before the source candidate was sealed in a clean commit. Its raw
output and all records are preserved as a dirty-candidate Source observation,
not a clean-candidate qualification. The matched owner now requires a clean
candidate before executing and compares any recapture byte-for-byte with the
preserved genuine expected. A clean sealed recapture must pass terminal and
full-posthash checks before promotion.

Native namespace qualification and whole-Pi qualification remain false. Actual
Models namespace and Codecs lazyStream integration dependencies must be present
before native controls can run. Source pass is not a native pass, factory pass,
release or live activation.

Clean sealed recapture `sdk-virtual-models-source36-sealed-e216a3c9-20261015`
completed at candidate e216a3c9 with actual Node PID 68520, exit zero and every
posthash/inventory/absence/caller drift count zero. Candidate files 7534, Source
1970, dependencies 31064, Node 1774, compiler 19546 and controls 9 were frozen.
The output matched the preserved genuine expected byte-for-byte. Its child was
independently checked absent after completion.

Subsequent source inspection corrected physical/virtual filter callback lifetime:
the source creates a fresh predicate on every filter call, so native closures now
do the same. A comparison helper in
`src/native_sdk_virtual_models_production_test.zig` takes actual imports from the
real assembler and genuine reference bytes. It adds no substitute namespace.
Neither this latest native source adjustment nor the test helper has undergone
native semantic compilation/runtime qualification. The genuine Source36 fixture
and capture caller remain unchanged; their accepted observation is the sealed
e216a3c9 run, not a claim that later native source was executed.
