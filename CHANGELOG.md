# Changelog

All notable changes to `pi-zig` are documented in this file.

## [Unreleased]

### Added

- Current zero-cost `openrouter/free` capability-router catalog entry with
  reasoning, image-input, context-window, and no-spend metadata.
- Exact generated Pi AI 0.84.1 catalog coverage: 1,258 models across 39
  providers, including per-model APIs, endpoints, headers, pricing tiers,
  reasoning maps, and compatibility metadata.
- Deterministic catalog source/generator checks that reject unknown or dropped
  model fields and run on every CI platform.

### Fixed

- Windows OAuth browser callbacks now read accepted TCP streams correctly,
  consume complete HTTP headers, and avoid nested timeout-concurrency failures
  across OpenRouter, Anthropic, OpenAI Codex, and Radius providers.
- Piped stdin now starts in streaming mode on Windows, preventing spurious
  `INVALID_INFO_CLASS` diagnostics in one-shot and JSON output.
- OpenRouter free-router requests no longer send a forbidden explicit
  `reasoning.effort: "none"` value when thinking is left at its default.
- Native hot switching now retains generated per-model endpoints, headers,
  credentials, API protocols, pricing, and compatibility metadata for mixed
  providers such as GitHub Copilot, Cloudflare, Fireworks, and OpenCode.
- Added OpenAI Responses `additional_tools` replay and vLLM
  `thinking_token_budget` behavior, including models.json compatibility flags.
- Daily free-tier quota responses fail fast instead of consuming the retry
  budget on deterministic OpenRouter 429 errors.

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
