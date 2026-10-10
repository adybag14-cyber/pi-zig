# pi-zig

The Pi 1.x update is in progress on this branch, targeting upstream commit
`42a3497d03ad17e308a2299fa824727894f2c0ec` (package version 1.1.0), newer than
[the v1.1.0 release](https://github.com/earendil-works/pi/releases/tag/v1.1.0).
Zig **0.16.0** remains pinned. Repository implementation work uses Zig and narrow
linked C dependencies; user-authored JavaScript/TypeScript extension compatibility
is part of the native runtime migration.

The checked-in catalog contains 1,653 models across 42 providers. The CLI and
extension API package version are 1.1.0. Full Pi 1.x parity and release
certification remain incomplete, and production extension discovery retains its
legacy Node bridge while native parity and lifecycle work continues.

Checkpoint 237 preserves the validated native generation, public submission,
compaction, transaction query, scheduler environment, SDK capability and runtime
changes. The latest scoped qualification runs nine affected test targets in
Windows and native Linux Debug and ReleaseSafe: Windows passes 403 tests with
5 platform skips per mode, and Linux passes 404 with 2 skips per mode. All
1,520 compiled source hashes were rechecked on both platforms. All 26 cached Windows
test executables import no SQLite DLL. These are affected-area checks; the
complete hosted suite and the unfinished native migration have separate gates.

A follow-up fixes the macOS futex build failure without narrowing thread IDs.
The serialized line now uses a separate 32-bit wake epoch. Its wraparound and
reentrant ownership regression passes with the backend, scheduler and native VM:
225 tests on Windows and 226 on Linux in both build modes, with 5 and 2 platform
skips respectively. The backend also cross-compiles for macOS ARM64. See the
[follow-up receipt](verification/checkpoint-237/macos-futex-fix/local-scoped-qualified.json);
native hosted macOS execution must qualify the repaired head.

See [the active update record](UPSTREAM-UPDATE-20261003.md) and
[checkpoint 237 evidence](verification/checkpoint-237/local-scoped-qualified.json)
for scope, remaining work and source-bound validation. Historical full and
scoped checkpoint records remain available under `verification/`.

`pi-zig` is a native Zig 0.16 rewrite of the Pi coding-agent and AI runtime. It
implements provider, model, session, extension, tool, RPC, TUI, storage,
authentication, and protocol surfaces while keeping the default executable
self-contained. The active update record distinguishes implemented contracts
from the remaining Pi 1.x migration work.

The previously certified behavioral baseline is Pi 0.84.4 at authoritative upstream main
commit `853a80d26c90a14c1886f0ebb8ffaae133ca2185`. The earlier embedded
TypeScript/JavaScript reference was retired in checkpoint 187 after the native
0.84.1 implementation passed its local and three-platform parity gates. Newer
work is audited in an isolated upstream checkout and projected into reviewed
native code and language-neutral data; the reference source is not restored to
this repository. `pi-zig` is an independent rewrite and is not an official Pi
release.

The current immutable typed catalog contains 1,653 models across 42 providers.
Its native Zig generator records
the upstream package version/commit, source-archive digest and separate catalog
revision/digest. Imported Git tar metadata and package version must match the
supplied provenance. Unknown or unprojected fields fail explicitly.

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
- session-scoped searchable model/thinking selectors with explicit Ctrl+S
  defaults, recursive file completion, terminal capability overrides, native
  PowerShell, Radius/private-gist session sharing, and RPC queue clearing;
- optional SQLite repository and live-server companions, remote protocol
  clients, TLS/proxy support, MCP, telemetry, image normalization, and package
  management;
- Windows, Linux, and macOS release targets.

## Build

Use the final Zig 0.16.0 release:

```sh
zig build -Doptimize=Debug
```

The default artifact is `zig-out/bin/pi` (`pi.exe` on Windows). Default builds
link the pinned SQLite C source statically, so the executable and tests do not
require `sqlite3.dll`.

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

Tests use the pinned SQLite C source by default. `-Dsqlite-lib-dir` selects an
external SQLite library; when that library is dynamic, its matching runtime
library must be available to the executables.

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
