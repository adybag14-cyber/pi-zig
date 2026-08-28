# pi-zig V8 checkpoint 140

Checkpoint 140 continues the native Zig 0.16.0 rewrite from the supplied checkpoint 138. Unlike the preceding checkpoint, this pass had all three requested inputs available locally: the original `pi-main (3).zip`, checkpoint 138, and the Zig 0.16.0 Linux x86-64 toolchain. The uploaded original's coding-agent and AI packages identify as version 0.84.1 and were used as the feature and behavioral reference.

The integrity rule remains unchanged: progress is measured through real native implementation, executable behavior, tests, source audits, and original-source comparison. No generated line-count shards or synthetic feature catalogs were introduced.

## Implemented in checkpoint 140

### Binary-safe multimodal CLI input

- Replaced text-only `@file` handling with a native binary-safe file processor.
- Detects PNG, JPEG, GIF87a/GIF89a, WebP, and BMP by magic bytes rather than filename extension.
- Rejects malformed/unsupported image forms such as JPEG-LS signatures, malformed BMP headers, and animated PNG input that the current native transport cannot safely represent.
- Rejects invalid UTF-8 and NUL-containing binary data from text concatenation.
- Supports quoted paths, paths containing spaces, Windows-style separators, escaped `@@` literals, and missing `@mentions` that should remain prompt text.
- Preserves input-source ordering across piped stdin, textual `@file` inputs, explicit user messages, and image attachments.
- Persists user image content in JSONL sessions so save/load/fork and active-branch replay retain multimodal context.
- Connects ordered image attachments through the agent boundary to image-capable provider adapters.

### Sequential CLI turns and session selection

- Positional prompt arguments now execute as distinct turns rather than being joined into one prompt.
- Exact `--session-id` lookup/creation uses portable validation and no longer aliases unrelated sessions.
- `--resume` is functional: interactive runs receive a numbered newest-first selector; noninteractive runs resume the newest session.
- Session listings use actual modification time.
- Resumed sessions restore the active branch's latest model and thinking-level changes when no explicit CLI override is supplied.
- New sessions honor scoped model startup order and optional per-model thinking suffixes.

### Original-compatible resources and CLI behavior

- Added original resource switches for explicit extensions, prompt templates, themes, and related disable flags.
- Fixed `--no-builtin-tools` so it disables only built-in tools and does not accidentally disable extension/custom tools.
- Explicit native extensions remain loadable under `--no-extensions`; explicit prompt templates remain loadable under `--no-prompt-templates`.
- Corrupt or empty optional Radius model caches now fall back to the built-in catalog instead of aborting startup.
- Model catalog filtering uses ranked case-insensitive fuzzy matching.

### Prompt templates

- Replaced the former name-only interpretation of `--prompt-template` with file/directory resource loading.
- Supports deterministic directory scanning and frontmatter fields `description` and `argument-hint`.
- Exposes loaded templates as slash commands and through RPC `get_commands`.
- Implements quoted command arguments and original-style substitutions:
  - `$1`, `$2`, ...
  - `$@` and `$ARGUMENTS`
  - `${N:-default}`
  - `${@:-default}` and `${ARGUMENTS:-default}`
  - `${@:N}` and `${@:N:L}`
- Replacement text is not recursively expanded.
- Extension commands execute before prompt-template expansion, matching the original AgentSession dispatch order.

### Native extension flags and commands

- Native out-of-process extension manifests can declare typed boolean/string CLI flags with defaults and descriptions.
- Duplicate flags, missing string values, and unknown extension options are rejected.
- Every hook, tool, and command receives only its owning extension's resolved flag object.
- Native extension manifests can now register slash commands with descriptions and argument hints.
- Duplicate command names across native extensions are rejected.
- Command protocol:

  ```text
  <entry> --pi-command <command-name> <raw-arguments> <flags-json>
  ```

- A command result can emit a visible message, return a prompt to the agent, mark an error, request termination, or combine those actions.
- Commands execute in one-shot/print mode, interactive mode, and RPC prompt dispatch.
- RPC `get_commands` reports extension name, description, argument hint, and executable source path.
- Terminal completion includes native extension commands.

This is a native process-isolated extension protocol. It does not claim drop-in execution of arbitrary upstream JavaScript/TypeScript extensions.

### Themes, fullscreen terminal mode, and completion

- Reworked theme parsing around the original nested `colors`/`vars` model.
- Supports truecolor and 256-color ANSI output, variable references, cycle detection, deterministic loading, and first-definition collision semantics.
- Removed a dangling-memory defect in parsed theme values.
- Theme discovery covers global resources, trusted project resources, explicit paths, and settings-based activation.
- `--tui-mode fullscreen` uses the terminal alternate screen when supported and restores it on exit/error unwinding.
- Added context-aware editor completion for slash commands, prompt templates, extension commands, fuzzy models, tree entry IDs, import/export paths, and quoted `@file` paths.

### Model/thinking state correctness

- Scoped model entries retain optional thinking levels and apply them during model cycling.
- Direct model switches and scoped cycling clamp thinking to the selected model's actual capabilities.
- Effective thinking changes are persisted as session entries.
- `cycle_model` reports scoped state accurately.
- `/reload` and thinking changes preserve explicit system prompts, append prompts, discovered context, package skills, and selected-skill filters.
- Direct RPC thinking changes validate and clamp requested levels.

## Validation summary

The final release gate is recorded in `VALIDATION-140.txt`. At source freeze:

```text
Zig toolchain:                 0.16.0
Full project tests:            541/541 passed
Debug executable build:        passed
Real Zig source files:         119
Real Zig source lines:         51,369
Synthetic/generated shards:    0
```

The final downloadable source archive is created without `.zig-cache` or `zig-out`, extracted into an independent directory, and rebuilt/tested there. Archive size stability, complete-file reads, ZIP integrity, SHA-256 verification, and artifact readability are checked before links are published.

## Remaining parity boundary

Checkpoint 140 is a substantial native implementation, not a claim of complete monorepo equivalence. The largest remaining areas are:

- drop-in compatibility with arbitrary JavaScript/TypeScript extensions and their rich in-process UI/session contexts;
- the original TUI's full Markdown renderer, terminal image protocols, overlays/selectors, dialogs, mouse behavior, and advanced editor interactions;
- automatic image resizing and the full set of multimodal/provider edge cases;
- exhaustive cloud credential, enterprise proxy, provider-owned login, and service-specific compatibility behavior;
- broader byte-for-byte streaming, retry, diagnostic, and error fixtures across every provider;
- fuller parity for the original client, telemetry, session-backend, eval, and auxiliary monorepo packages.

See `PARITY-140.md` and `PARITY-140.json` for the explicit subsystem status rather than inferring completion from source size.
