# pi-zig

A **Zig 0.16.0** rewrite of the core of [earendil-works/pi](https://github.com/earendil-works/pi) — a coding-agent harness as a **single native binary**.

This is a **full structural port** of the coding-agent surface (tools, multi-provider AI, sessions, context/skills/prompts/settings, CLI modes, packages) plus **monorepo C package surfaces** (MCP, serve, OAuth device parse, session index, TUI diff buffer, extensions host, themes, evals, images, 40+ provider catalog). Not a 200k-LOC TypeScript monorepo clone.

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

### Cross-compile

```bash
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-gnu
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-windows-gnu
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-windows-gnu
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-macos
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos
```

### GitHub Releases

CI builds and tests on Linux, Windows, and macOS. Tagged releases (`v*`) publish multi-arch binaries.

## Soft / hard cancel & thinking

| Feature | Behavior |
|---------|----------|
| Mid-bash kill | Abort flag / timeout force-kills the OS process (`SIGKILL` / `TerminateProcess`) while tool runs |
| Mid-HTTP cancel | OpenAI + Anthropic SSE writers poll abort; `stop_reason=aborted` |
| Thinking budgets | `--thinking off\|low\|medium\|high\|xhigh` → system prose **and** provider fields (`reasoning_effort` / `budget_tokens`) |
| Entry timestamps | Each session entry stores ISO timestamp; survives save/load |

RPC `abort` and `set_thinking_level` drive these live.

## Packages (source layout)

Single binary `pi`, library module `pi_zig` from `src/root.zig`:

| Package | Path | Role |
|---------|------|------|
| config | `src/config.zig` | APP_NAME, `~/.pi/agent`, env vars, session dirs |
| ai | `src/ai/` | Providers, OpenAI / Anthropic / Google / mock / images |
| agent | `src/agent/` | Tools, agent loop, JSONL sessions, compaction |
| tui | `src/tui/` | ANSI + render + **differential buffer** |
| coding_agent | `src/coding_agent/` | CLI args, context, skills, prompts, settings, slash, modes, packages |
| mcp | `src/mcp/` | MCP JSON-RPC client (stdio) |
| server | `src/server/` | TCP HTTP RPC (`pi serve`) |
| storage | `src/storage/` | Session index JSONL store |
| auth | `src/auth/` | OAuth device-code parse + token files |
| extensions | `src/extensions/` | Declarative extension host |
| themes | `src/themes/` | Theme JSON |
| evals | `src/evals/` | Mock eval harness |

### AI providers (`src/ai/`)

| Module | Notes |
|--------|--------|
| `providers.zig` | **40+** catalog entries + openai_compat gateways |
| `openai.zig` | Chat completions + tools + SSE + reasoning_effort + images |
| `anthropic.zig` | Messages API + SSE + thinking budget_tokens |
| `google.zig` | `generateContent` text path |
| `mock.zig` | Scripted responses from JSON |
| `images.zig` | File → base64 multimodal helper |

Env keys: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `PI_API_KEY`, plus `OPENAI_BASE_URL`, `PI_MODEL`, `PI_PROVIDER`, `PI_MOCK_SCRIPT`, `PI_AGENT_DIR`, `PI_SESSION_DIR`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`, `XAI_API_KEY`, `DEEPSEEK_API_KEY`, …

### CLI surfaces

```bash
pi -p --mock-script script.json "hello"
pi --mode rpc …
pi --thinking high --provider anthropic …
pi --provider ollama --base-url http://127.0.0.1:11434/v1 --model llama3.2 …
pi --list-models grok
pi install path:./local-pkg
pi list | remove <name>
pi serve --port 3141 [--token SECRET]
pi mcp npx -y @modelcontextprotocol/server-filesystem .
pi eval --script mock.json --expect "world" say hi
pi oauth parse-device device.json
pi theme theme.json
pi index [session-dir]
```

### Interactive slash commands

`/help /quit /exit /session /new /name /model /compact /export /import /fork /clone /tree /reload /hotkeys /changelog /copy /login /logout /settings /resume`

## Audit

See [GAP_AUDIT.md](./GAP_AUDIT.md) for soft/hard + monorepo C status.

## License

Same spirit as upstream pi; check repository for license file when published.
