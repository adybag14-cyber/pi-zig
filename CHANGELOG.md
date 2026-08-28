# Changelog

All notable changes to `pi-zig` are documented in this file.

## [Unreleased]

### Added

- Current zero-cost `openrouter/free` capability-router catalog entry with
  reasoning, image-input, context-window, and no-spend metadata.

### Fixed

- Windows OAuth browser callbacks now read accepted TCP streams correctly,
  consume complete HTTP headers, and avoid nested timeout-concurrency failures
  across OpenRouter, Anthropic, OpenAI Codex, and Radius providers.
- Piped stdin now starts in streaming mode on Windows, preventing spurious
  `INVALID_INFO_CLASS` diagnostics in one-shot and JSON output.
- OpenRouter free-router requests no longer send a forbidden explicit
  `reasoning.effort: "none"` value when thinking is left at its default.

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
