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

Static Zig 0.16.0 formatting and AST checks passed. Genuine latest Source
capture passed at frozen candidate
`1f0008ef475b5325ce15192f6a9a20a1b2e64616`: 30 observations and 9 raw five-field
rows, with 6 exact physical file paths retained for native comparison. Source
symlink creation returned EPERM on this host; no symlink success is claimed.
The generated Source packet SHA-256 is
`4F8E890DBB214A3F55493E9AB9FD0090F6776DC60CD8B6F9C72182C41BD96F8A`.

Full fresh pre/post checks found zero drift across candidate 7,682 files,
compiler 19,546, Source 1,970, external dependencies 31,064, Node/tools 1,774,
extra controls and all 84 recorded absent dependencies. Candidate/compiler/
Source path inventories also matched. The accepted observer verified actual
latest Source imports; no old workspace class or authored expected was used.

The initial genuine Source run is retained as a negative control: an assertion
incorrectly assumed that Number-based utimesSync would store an mtime requiring
more Number precision. The corrected control records both actual observations:
mtime `1712345678123456000` is Number-representable, while genuine ctime
`1792106181783826900` loses digits through Number. All first-run full posthash and
inventory checks were also zero drift; its physical fixtures are retained.

Focused real-filesystem test entry `src/native_file_revision_test.zig` now has
six prepared tests, including a direct comparison against the six retained
original Source file revisions and content hashes. It has not been compiled or
run; Root has granted no native lane. The physical comparison explicitly skips
on other hosts where all six original objects are absent. This remains a
Source-only checkpoint, not native qualification or composed AuthStorage/
ModelsStore delivery. Private native allocator failures remain host errors;
ordinary Source stat/path errors and user errors named OutOfMemory are caught.

The Source input covers retained real files, append/same-size mutations,
replacement preserving the old object, cross-directory basenames, hard links,
symlinks when the host permits them, Unicode/whitespace paths, path type and URL
getter errors, and exact decimal nanosecond precision above Number's integer
range. The capture retains all owned filesystem fixtures as evidence.

Executed scripts and raw logs retain their original whitespace. `RAW-PROOF.zip`
preserves their exact bytes, the Source input and the accepted generated packet
independently of Git text line-ending conversion. `RAW-PROOF.sha256` identifies
that archive. Static whitespace checks cover the authored native code and prose;
raw historical records are preserved without normalization.
