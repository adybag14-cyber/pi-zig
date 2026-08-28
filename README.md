# pi-zig

`pi-zig` is a native Zig 0.16 rewrite of the Pi coding-agent and AI runtime. It
preserves Pi's provider, model, session, extension, tool, RPC, TUI, storage,
authentication, and protocol behavior while keeping the default executable
self-contained.

The behavioral baseline was Pi 0.84.1. After the native implementation passed
the complete local and three-platform parity gates, its TypeScript/JavaScript
reference snapshot was retired in checkpoint 187. The exact 0.84.1 model data
needed at runtime remains as the language-neutral `src/ai/catalog_source.json`
input to the deterministic Zig catalog generator. `pi-zig` is an independent
rewrite and is not an official upstream release.

## Highlights

- native multi-turn agent loop, tool execution, steering, retry, compaction,
  branch summaries, and append-only JSONL sessions;
- OpenAI Chat/Responses/Codex, Anthropic, Google, Mistral, Bedrock, Pi
  Messages, Azure-compatible, and custom-provider transports;
- persistent JavaScript/TypeScript extension workers with tools, commands,
  hooks, renderers, OAuth, dynamic models, provider streams, credential-aware
  model filters, and deferred fetch/cancel callbacks;
- generation-safe provider callback ownership with bounded active-stream
  retirement and hostile-iterator worker isolation;
- retained fullscreen terminal application, Markdown/LaTeX rendering, terminal
  images, model/session/settings/auth/package selectors, mouse input, clipboard,
  completion, and configurable keybindings;
- optional SQLite repository and live-server companions, remote protocol
  clients, TLS/proxy support, MCP, telemetry, image normalization, and package
  management;
- Windows, Linux, and macOS release targets.

## Build

Use the final Zig 0.16.0 release:

```sh
zig build -Doptimize=Debug
```

The default artifact is `zig-out/bin/pi` (`pi.exe` on Windows). It does not
link SQLite.

Build the optional SQLite administration and live-server binaries with:

```sh
zig build sqlite -Doptimize=ReleaseSafe
```

On Windows, pass the directory containing `sqlite3.lib` when it is not already
in the compiler's library search path, and ensure the matching `sqlite3.dll` is
on `PATH` when running the linked binaries:

```powershell
zig build sqlite -Doptimize=ReleaseSafe -Dsqlite-lib-dir=C:\path\to\sqlite
```

## Test

```sh
zig build test --summary all
```

The Windows test command accepts the same `-Dsqlite-lib-dir` option. CI installs
a matching SQLite development package before running the complete graph.

Focused extension bridge checks can also be run directly:

```sh
node --check src/extensions/js_bridge.mjs
zig test src/extensions/js_runtime.zig
```

## Repository layout

- `src/` — native Zig implementation and JavaScript extension bridge;
- `checkpoint-tests/` — production/custom-provider integration fixtures;
- `scripts/` — source, packaging, and parity audits;
- `verification/` — retained checkpoint evidence;
- `CHECKPOINT-*.md` and `GAP_AUDIT.md` — implementation history and audit trail.

## License

The `pi-zig` rewrite is released under the [MIT License](LICENSE).
