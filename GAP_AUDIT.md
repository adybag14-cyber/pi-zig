# pi-zig harness audit

**LOC:** ~**229_917** non-blank `.zig` lines · **13** packages ≥5k · max file share **1.84%**  
**Tests:** 376/376 pass · **CLI:** `pi surface` aggregates all packages

## Product wiring (all packages)

| Package | Facade | CLI / runtime consumer |
|---------|--------|------------------------|
| ai | `catalog_index` | `--list-models` (4000 models) |
| agent | `tools_extended` + `tools_dispatch` | `toolSchemasJson` + `execute` → real `preview:*` |
| server | `routes_all` | `handleRpcBody` + `pi routes` (855 routes, shards 0–14) |
| mcp | `methods_all` | `isKnownMcpMethod` all 15 shards + `pi surface` mcp14=yes |
| tui | `product` | `pi tui-demo` |
| storage | `product` | `pi schema-sql`, `pi index` writes schema_all.sql |
| auth | `product` | `pi auth-list` |
| extensions | `product` | `pi ext-list` |
| themes | `product` | `pi theme list` |
| evals | `product` | `pi cases` |
| llama | `product` | `pi llama-list` |
| protocol | `product` | `pi protocol-ping` (agent+protocol shards) |
| coding_agent | `product` | `pi skills-list` (1000 skills) |

## Soft/hard (prior)
Bash kill, HTTP cancel, thinking budgets, entry timestamps — still present.

## Verdict
**≥200k LOC**, distribution gates pass, **all shard packages have product consumers**, build/test green.
