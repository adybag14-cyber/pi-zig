Actual Source `packages/coding-agent/src/utils/paths.ts` at
`4954d760504c11df9b2cbdc040346107b6a8153d` uses `statSync(path, { bigint: true })`
and returns decimal `dev:ino:size:mtimeNs:ctimeNs`; any stat/path exception
returns undefined. It performs no path normalization or content read.

The new native modules implement those five fields from actual Windows handle
metadata, Linux statx, or POSIX stat. Windows ctime is ChangeTime, never creation
time. File IDs and nanoseconds remain integers throughout. No shared node_fs,
SDK, Engine, AuthStorage, or ModelsStore file is changed here.

Exports from `native_file_revision.zig`:

- `revision(engine, path) !?[]u8` and `revisionAlloc(gpa, path) !?[]u8` return an
  owned native string or null for stat failure.
- `getFileRevision(engine, value) !JSValue` preserves Source undefined semantics
  for strings, Uint8Array/Buffer paths, file URLs, and invalid runtime arguments.
- `install(engine, exports) !void` installs the one public function.

Static Zig 0.16.0 formatting and AST checks passed. Genuine Source control
capture awaits Root LIGHT admission. Focused real-filesystem test entry
`src/native_file_revision_test.zig` is prepared but has not been compiled or run;
Root has granted no native lane for this task. This is a Source-only candidate,
not native qualification or composed AuthStorage/ModelsStore delivery.

The Source input covers retained real files, append/same-size mutations,
replacement preserving the old object, cross-directory basenames, hard links,
symlinks when the host permits them, Unicode/whitespace paths, path type and URL
getter errors, and exact decimal nanosecond precision above Number's integer
range. The capture retains all owned filesystem fixtures as evidence.
