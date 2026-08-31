# Changelog

All notable changes to `pi-zig` are documented in this file.

## [Unreleased]

## [1.1.0] - 2026-08-31

### Added

- Exact reproducible Pi 0.84.4 catalog projection: 1,290 models across 39
  providers, pinned to upstream main commit
  `853a80d26c90a14c1886f0ebb8ffaae133ca2185` and the verified release archive.
- Provider-neutral tool choice, compaction routing sessions, three compatible
  thinking-budget fields, Pi user-agent headers, Anthropic server-side
  fallbacks, OpenAI reasoning-detail replay, Bedrock redacted reasoning,
  Codex `end_turn`, Google thinking maps, and fragmented Mistral tool calls.
- Optional native PowerShell tool, terminal capability overrides, RPC queue
  clearing, extension UI prompt events, `/thinking`, `/share`, Ctrl+S model and
  thinking defaults, recursive `@file` completion, and public image MIME
  detection by file magic.
- Current Copilot account-catalog policy discovery with bounded 429 retries and
  sequential enablement of known tool-capable models only.
- Searchable session-only model/thinking selectors, persistent
  `enabledModels`, organization-visible Radius JSONL sharing, and private-gist
  fallback links.

### Fixed

- Final turns no longer invoke prepare-next-turn hooks, and extension messages
  emitted during tools are appended only after their corresponding results.
- Malformed JSONL lines are skipped, valid unterminated sessions are repaired,
  and failed compactions emit the complete `session_compact_failed` event.
- Failed extension factories leave no tool/provider/flag state and early worker
  exits no longer write into closing Windows pipes.
- Npm updates install only a strictly newer semantic version, preventing stale
  registries from downgrading locally newer packages.
- Fullscreen selection treats `/` and `-` as word joiners, generic SGR releases
  complete selections, and VS Code no longer receives duplicate Windows
  right-click paste.
- Settings, models, prompt templates, and skills accept UTF-8 BOMs; invalid
  settings identify their exact path while valid scopes remain active.
- OpenRouter reasoning-mandatory free routing, Google tool-call stop reasons,
  Kimi cached tokens, and model-specific fallback pricing match Pi 0.84.4.

## [1.0.0] - 2026-08-28

### Added

- Complete native Zig 0.16 coding-agent, provider, session, tool, TUI, RPC,
  storage, authentication, package, image, telemetry, and extension runtime.
- Generation-safe JavaScript provider callbacks with acknowledged retirement,
  active-stream cancellation, bounded drain, and hostile-worker isolation.
- Credential-aware object-form model filtering and deferred provider
  fetch/cancel callbacks through the native model-client interface.
- Optional SQLite administration and live-server companions.
- Windows, Linux, and macOS CI/release targets.
- MIT license.

### Changed

- Replaced the former generated/synthetic repository surface with real native
  implementation and executable regression coverage.
- Updated the build and test workflow for the final Zig 0.16.0 release.

### Fixed

- Windows file-permission, Node command-line, SQLite library discovery,
  package-lock metadata visibility, path normalization, and companion CLI
  compatibility issues.
