# Changelog

All notable changes to `pi-zig` are documented in this file.

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
