# pi-zig

A **Zig 0.16.0** rewrite of the core of [earendil-works/pi](https://github.com/earendil-works/pi) — a coding-agent harness as a **single native binary**.

This is a **full structural port** of the recognizable coding-agent surface (tools, multi-provider AI, sessions, context/skills/prompts/settings, CLI modes, packages), not a minimal subset. TypeScript extension hosts, OAuth browser flows, and the differential TUI renderer are intentionally simplified to native equivalents.

## Requirements

- **Zig 0.16.0** (required — uses 0.16 process/Io/HTTP APIs)

```text
zig version   # must report 0.16.0
```

## Build / test

```bash
zig build
zig build test
```

Binary: `zig-out/bin/pi` (or `pi.exe` on Windows).

## Packages (source layout)

Single binary `pi`, library module `pi_zig` from `src/root.zig`:

| Package | Path | Role |
|---------|------|------|
| config | `src/config.zig` | APP_NAME, `~/.pi/agent`, env vars, session dirs |
| ai | `src/ai/` | Providers, OpenAI / Anthropic / Google / mock clients |
| agent | `src/agent/` | Tools, agent loop, JSONL sessions, compaction |
| tui | `src/tui/` | ANSI colors + simple terminal render helpers |
| coding_agent | `src/coding_agent/` | CLI args, context, skills, prompts, settings, slash, modes, export, packages |

### AI providers (`src/ai/`)

| Module | Notes |
|--------|--------|
| `providers.zig` | Catalog + env key resolution |
| `openai.zig` | OpenAI-compatible chat completions + tools |
| `anthropic.zig` | Messages API (`x-api-key`, `anthropic-version`, tool_use) |
| `google.zig` | `generateContent` text path |
| `mock.zig` | Scripted responses from JSON |

Env keys: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `PI_API_KEY`, plus `OPENAI_BASE_URL`, `PI_MODEL`, `PI_PROVIDER`, `PI_MOCK_SCRIPT`, `PI_AGENT_DIR`, `PI_SESSION_DIR`.

### Tools (all 7)

| Tool | Purpose |
|------|---------|
| `read` | Read file |
| `write` | Write file (creates parents) |
| `edit` | Exact string replace (unique match) |
| `bash` | Shell command (`cmd.exe /C` on Windows, `sh -c` elsewhere) |
| `grep` | Walk + substring search (`pattern`, `path`, `glob`, `ignoreCase`, `limit`) |
| `find` | Glob-like `*` / `**` matcher (`pattern`, `path`, `limit`) |
| `ls` | List directory (`path`, `limit`) |

Allowlist / exclude via `--tools` / `--exclude-tools` / `--no-tools`. Schemas are generated only for enabled tools.

### Session

- JSONL: header + messages (`id`, `parentId`, `role`, `content`, `toolCalls`, `toolCallId`)
- Auto-save under `~/.pi/agent/sessions/<cwd-hash>/` (or `--session-dir`)
- `--continue` most recent, `--session` path/id, `--fork`
- Branch tip + `/tree`, `/compact` (keep last N, summarize rest)
- `/export` or `--export` → simple HTML transcript

### Context / skills / prompts / settings

- Walk `AGENTS.md` / `CLAUDE.md` from cwd + global `~/.pi/agent`
- `SYSTEM.md` replaces default system prompt; `APPEND_SYSTEM.md` appends
- Skills: `SKILL.md` under `~/.pi/agent/skills`, `.pi/skills`, `.agents/skills`, and package `skills/`
- Prompt templates: `~/.pi/agent/prompts/*.md` and `.pi/prompts/*.md` with `{{var}}` expansion
- `settings.json` merge (global + project): model, provider, tools, max_turns

### Modes

| Mode | Behavior |
|------|----------|
| text (default) | Interactive REPL or `-p` final text |
| json (`--mode json`) | JSON lines: `user`, `assistant`, `tool_call`, `tool_result`, `done` |
| rpc (`--mode rpc`) | JSONL stdin `{id,method,params}` → `prompt` / `ping` / `quit` |

### Packages

```bash
pi install path:./local-pkg
pi list
pi remove <name>
```

Records paths under `~/.pi/agent/packages.json`. Packages may contain conventional `skills/` (and `prompts/`) directories.

### Slash commands (interactive)

`/help` `/quit` `/exit` `/session` `/new` `/name` `/model` `/compact` `/export` `/import` `/fork` `/clone` `/tree` `/reload` `/hotkeys` `/changelog` `/copy` `/login` `/logout` `/settings` `/resume`

### CLI flags (upstream surface)

```
-h/--help -v/--version -p/--print --mode text|json|rpc
-c/--continue -r/--resume --provider --model --api-key
--system-prompt --append-system-prompt --name/-n
--no-session --session --session-dir --fork
--tools/-t --exclude-tools/-xt --no-tools/-nt --no-builtin-tools
--thinking --export --skill --no-skills
--prompt-template --no-prompt-templates --no-context-files/-nc
--list-models --verbose --offline --approve/-a --no-approve
--mock-script @file messages...
```

## Examples

### Offline print mode (mock)

```json
[
  {
    "content": "Writing a file.",
    "tool_calls": [
      {
        "id": "c1",
        "name": "write",
        "arguments": "{\"path\":\"out.txt\",\"content\":\"hello from pi\"}"
      }
    ]
  },
  { "content": "Done.", "tool_calls": [] }
]
```

```bash
./zig-out/bin/pi -p --mock-script mock.json "write a file"
```

### Live API

```bash
export OPENAI_API_KEY=sk-...
./zig-out/bin/pi -p "List files using tools"
./zig-out/bin/pi --provider anthropic -p "hello"
./zig-out/bin/pi --provider google -p "hello"
```

### Sessions

```bash
./zig-out/bin/pi -p --session ./my.jsonl --mock-script mock.json "hello"
./zig-out/bin/pi -c -p "continue that thought"
```

## Comparison to upstream pi

| Upstream pi | pi-zig |
|-------------|--------|
| TypeScript monorepo (pi-ai, pi-tui, extensions, packages) | Single Zig binary, stdlib only |
| Full TUI + differential renderer | ANSI helpers + line-oriented REPL |
| Multi-provider catalog, OAuth, subscriptions | OpenAI / Anthropic / Google HTTP + mock (API keys / credentials file) |
| TS extensions + MCP | Not supported — use packages for skills/prompts |
| Tree session UI, share, rich HTML export | JSONL tree + tip + simple HTML |
| Permission popups, plan mode, sub-agents | Omitted (upstream core also omits MCP/sub-agents/plan mode) |
| Project trust UI | `--approve` / `--no-approve` load or skip project `.pi` resources |

### Honest remaining deltas (not advertised as shipped)

- No browser OAuth / subscription login flows (use `/login provider key` or env API keys).
- No TypeScript extension host, themes marketplace, or npm/git package lifecycle.
- No pixel-perfect differential TUI; REPL is line-oriented.
- Google path is text-oriented; OpenAI + Anthropic carry full tool calling.
- Every **advertised** help flag, package subcommand, and slash command has a real handler (no stub no-ops).

## License

MIT (aligned with upstream pi).
