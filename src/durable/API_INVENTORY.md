# Native durable environment foundations

Reference: Pi `b78e6a9085343ec0f308c3d377da72528b4cf7ee` (1.0.3).
`packages/durable/src` is unchanged from the independently captured reference
`6100fe5a8358709a26050b8da97ccd188ae93101`; the durable delta is package metadata
and changelog. The new `packages/env` remote adapter implements the same
`ExecutionEnv` interfaces. Its SSH/daemon transport is outside this foundation.

## Coverage and integration boundaries

| Upstream API | Existing native code | Foundation in this directory |
|---|---|---|
| `StreamDecoder`, `rangeDecoder`, `startsWithBom` | Host TextDecoder/Buffer support under extensions | Allocation-free UTF-8 scalar decoder, counting/text sinks, explicit leading BOM handling |
| `LineScanner` / `LineScan` | No file-range scanner | One-pass offsets and decoded sizes in constant scanner memory |
| `FileSystem.openBinaryReader` | CLI read loaded the whole file, capped at 32 MiB | Retained regular-file descriptor, bounded positional reads, opened-file metadata, scans, close |
| `FileSystem.openDirReader` | CLI ls and extension readdir enumerated complete results | Native directory cursor and metadata only for returned entries; disappearing and unsupported entries skipped |
| `openTextLineReader` | No retained line reader | Positional chunk reads, streaming UTF-8, CR preserved, termination flag, no synthetic trailing empty line |
| `absolutePath`, `fileInfo` | Multiple native path/stat call sites | Explicit local filesystem namespace, home/file-URL conveniences, owned values and expected failure results |
| Local `ExecutionEnv` mutation/temp facade | Coding tools wrote directly | Read/write/append/truncate/flush/rename/list/canonical/existence/directory/remove/temp operations; shared filesystem/shell cwd and atomic cwd replacement |
| Bounded read tool path | `src/agent/tools.zig` read loaded all text before slicing | Header, scan, selected prefix, one mutation retry; legacy CLI image handling and notices retained |
| Structured read/write/edit/bash | Existing CLI-only ToolResult | Owned content, diagnostics and details; slice-number semantics; image rejection; original-content edits, NFKC touched-line preservation, Myers display/unified patches; streamed shell output and raw-spill diagnostics |
| `Shell.exec` argv/string | Agent tools already spawned native processes; drain path stopped storing at 1 MiB | Direct argv, native Bash selection, per-stream UTF-8, caller-thread callbacks, optional safe output omission, raw spill, timeout/abort/callback errors |
| `Shell.cleanup` | Existing tool-specific process termination | Active exact process-group/job capabilities; no process-name enumeration or broad termination |
| `OutputBuffer`, skipped output | Legacy final-text truncation | Exact decoded byte/newline totals, head/tail limits, legal skips, sanitization, snapshot-independent tail margins |
| Progress policy | No durable generation/tool commit policy | Default 100 ms policy and a serialized adaptive gate at 100 KiB/s; storage/generation scheduling remains harness integration |
| `FileSystem.watch` | No durable watch abstraction | Established initial snapshot, actual polling, recursive excludes, missing paths, recent small-file hashes, budgets, joined close |
| Memory/JSONL/SQLite storage | Native Agent sessions, session index, SQLite repository | Existing implementations are not changed by this lease; durable storage/session/harness facades remain separate work |

The public entry point is `root.zig`; the local environment remains explicit
about allocator and `std.Io`. Expected filesystem failures are `types.Result(T)`
values. Allocation failure remains an error union failure. Returned metadata,
bytes, pages, snapshots, and error paths have explicit deinitializers.

## Process and callback ownership

Each command starts in a private POSIX process group. The small native C
`waitid(WNOWAIT)` probe observes termination without releasing its PID before
pipe drainage and the final wait. On Windows the process starts suspended and
is assigned to a fresh job before resuming. Abort, timeout, callback failure,
and environment cleanup target only that owned capability. Pipe reads use
bounded `std.Io.Batch` buffers; limits never stop drainage and deadlock a child.
The full Windows exit code is read before Zig's narrower `Child.Term` result.

Shell output callbacks execute on the `exec` caller's thread. The polling watch
callback executes on its owned polling thread; an extension-language adapter
must enqueue it for the language context's owner thread. Watch `close` joins
from the owner and is safe when called inside its callback. Destruction belongs
to the owner after join, and requires a thread-safe allocator while watching.

Spill artifacts contain complete raw bytes and remain owned by the returned
result's caller, as in the reference environment. Closing the environment does
not remove those artifacts. Private creation failures roll back only the exact
newly created directory under the resolved temporary root.

## Explicit bounds and remaining scope

- Watch mode is currently `polling` on every platform. Forced native-event mode
  returns `not_supported`; inotify/FSEvents implementations are not claimed.
  Polling can miss a change undone between snapshots.
- Watch limits default to 10,000 directories and 100,000 snapshot entries; budget
  overflow reports an error and stops delivery. The entry bound is an additional
  native resource limit. Snapshot identity currently uses the native inode and
  timestamps; mounted-volume identity and invalid-byte POSIX filenames need
  broader differential coverage.
- Durable storage, Session, registry/schema registration and Harness invocation
  remain separate integration work. `tools.ToolSet` and `tools.read.execute`
  expose native typed operations; the existing CLI retains its own format.
  The native mutation queue uses one bounded global lock, so independent paths
  serialize too. Per-path parallel scheduling is not claimed.
- Reader and scan integer parameters are native nonnegative integers with the
  upstream safe-integer ceiling. A language adapter must validate negative,
  fractional, and nonfinite inputs before converting them to native integers.
- File reads currently retain regular files; reading a FIFO through the whole
  file facade is not claimed. Readers reject nonregular paths without blocking.
- Diff alignment is limited to 1,048,576 retained Myers path nodes and total
  middle graph diagonals. Budget exhaustion returns `DiffBudgetExceeded` before
  an edit writes the file. Complete edits still load the file, like upstream.
- Structured APIs use owned UTF-8 values. A future extension-language adapter
  must retain JavaScript exception values and validate input shapes separately;
  native callback and prepare errors retain their original `anyerror` cause.

## Validation sources

Tracked JSON contains data, not executable host implementations:

- `fixtures/line_scan_6100.json`: 5,000 independently captured decoder/scanner cases.
- `fixtures/output_window_6100.json`: 3,000 output sequences and 240 head/tail bounds.
- `fixtures/readers_6100.json`: real opened-file rename/replacement and line-reader results.
- `fixtures/shell_6100_windows.json`: the reference Node environment running the
  same native Zig process fixture used by the native tests.
- `fixtures/watch_polling_6100.json`: actual reference polling watches over real files.
- `fixtures/facade_b78.json`: real reference mutation/temp operations and errors.
- `fixtures/read_b78.json`: 386 retained upstream whole-file reference results,
  including NaN/fractional/negative/huge selections and truncation. Raw bytes are
  base64 data, reversibly compacted from the original capture.
- `fixtures/edit_b78.json`: 17 edit cases and 240 repeated-line display/patch cases.
- `fixtures/bash_b78_windows.json`: actual reference bash tool execute function
  over the same native process fixture, including callback identity and spill.

Build targets: `zig build test-durable test-durable-tools`. Standalone tests:
`zig test src/durable_test.zig -lc src/durable/process_probe.c vendor/quickjs/libunicode.c -Ivendor/quickjs`.
Build `process_fixture.zig` as `zig-out/bin/pi-durable-fixture` (add `.exe` on
Windows), or set `PI_DURABLE_FIXTURE` to its absolute path. Production/core build
integration must link `process_probe.c`, libc and the pinned native Unicode
tables for structured normalization. CLI integration tests use
`src/durable_tools_test.zig` and the existing pinned QuickJS C library because
the existing tool schemas use its regexp implementation.

Native `tool_diff.zig` follows the Myers path selection of jsdiff 8.0.4, pinned by
the upstream lockfile to `https://registry.npmjs.org/diff/-/diff-8.0.4.tgz` with
SHA-512 `DPi0FmjiSU5EvQV0++GFDOJ9ASQUVFh5kD+OzOnYdi7n3Wpm9hWWGfB/O2blfHcMVTL5WkQXSnRiK9makhrcnw==`.
The archive was checked against that integrity before reference capture. The
native port's BSD-3-Clause notice is retained in `JSDIFF_LICENSE.txt`; the npm
JavaScript implementation is an external oracle, not a runtime dependency.
