# Checkpoint 186 — provider lifecycle closure and Zig 0.16.0 release

Checkpoint 186 completes the provider-extension continuation from checkpoint
185 and promotes the native rewrite to version 1.0.0.

## Generation-safe provider ownership

Every JavaScript provider callback descriptor now carries a positive,
runtime-local generation. The native registry retains callback ID, path,
generation, and owning worker as one identity. A committed registration sends
the exact selected callback set back to its worker; obsolete generations remain
available until that handoff succeeds and are then retired.

Active provider streams record provider, worker, generation, callback, and
invocation identity. Replacement, unregister, reload, registry teardown, and
shutdown request cancellation and wait for bounded iterator cleanup. A blocked
iterator that cooperates with abort/`return()` leaves its worker reusable. A
hostile iterator that ignores both is detected after the cleanup deadline and
only its owning worker is force-closed; unrelated workers remain usable.

The event protocol rejects stale provider/generation pairs, retains one
acknowledgement per ordered event, clears abort listeners and pending
acknowledgements, and prevents retired generations from producing later stream
records.

## Remaining provider surfaces

- Object-form providers can execute credential-aware `filterModels(models,
  credential)` callbacks through their exact generation owner.
- Provider-owned `fetchDeferred(model, handle, options)` uses the same bounded,
  acknowledged event stream and cancellation lifecycle as `streamSimple`.
- `cancelDeferred(model, handle, options)` is exposed through the native
  `ModelClient` and retains the provider's live `AbortSignal`.
- Deferred capabilities are published only when the selected provider actually
  owns the corresponding callback.

## Final Zig 0.16.0 Windows compatibility

- Replaced POSIX-only permission construction with cross-platform permission
  helpers and skipped unsupported Windows chmod operations.
- Replaced the 86 KiB Node `-e` bridge command line with a short, temporary,
  hash-addressed `.mjs` launch file, avoiding the Windows process-command limit.
- Added an explicit `-Dsqlite-lib-dir` build option and Windows CI provisioning
  for SQLite.
- Separated package-operation locking from atomic owner metadata because
  Windows does not permit a second reader on the exclusively locked file.
- Corrected platform-native path and package-layout regressions.
- Added standard `pi-sqlite --help` and `--version` behavior.

## Release and validation

Validation uses the supplied final `zig-x86_64-windows-0.16.0` toolchain and
the official SQLite 3.53.4 Windows x64 DLL whose archive matches SQLite's
published SHA3-256.

The retained checkpoint-186 logs cover:

- JavaScript syntax validation and dedicated generation/adversarial tests;
- complete Debug build/test graph, including dedicated SQLite repository,
  CLI, live-persistence, ordinary executable, and SQLite-enabled executable
  processes;
- ReleaseSafe builds for `pi`, `pi-sqlite`, and `pi-sqlite-live`;
- version/help smoke tests and SHA-256 hashes for every Windows binary;
- Zig formatting, source audit, Git whitespace validation, and repository
  integrity regeneration.

The exact final counts and hashes are recorded in
`verification/checkpoint-186/verification-summary.json`.
