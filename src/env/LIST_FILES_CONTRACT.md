# Pi 1.2.0 file listing

Authority is Pi `e6220e1316f86af818a0ccbfe1c09d7e918b41cf`, particularly
`packages/env/src/list-files.ts`, `packages/env/daemon/src/list.rs`, the daemon's
locked `ignore 0.4.33` / `globset 0.4.20` sources, and Durable's filesystem
conformance cases. The implementation is native Zig 0.16.0; the separately built
unmodified Rust daemon and Node TypeScript exports are reference oracles only.

`durable/list_files.zig` produces a depth-first listing, with parents first and
sibling names in byte order. It lists regular files, directories and links;
child links are not followed. The root itself may be a link. Entries named
`.git` and entries whose names occur in `exclude` are pruned. Native directory
entry kinds preserve Windows names that Win32 path normalization would change.

The limits default to 50,000 entries, 4 MiB of wire records, and 10,000 ms. Every
record counts one kind byte, the UTF-8 relative path, and a NUL byte. The byte
limit is clamped to the protocol's 16 MiB frame limit less 64 KiB. A limit marks
the result truncated only when an additional eligible entry is encountered;
exactly filling a limit does not itself mark truncation. Cancellation returns
`aborted`, and the concurrent file worker receives the actual request's abort
flag. A failed or canceled listing does not close the connection or its readers.

`durable/list_ignore.zig` keeps an owned stack of ancestor and nested rules.
Rules apply within the nearest worktree boundary, and separate matcher classes
preserve the source order: `.gitignore`, `.git/info/exclude`, then global rules.
The source's `.jj` worktree recognition and `.git`/`commondir` marker behavior
are retained. `.ignore` and `.fdignore` are deliberately outside this API's
contract. Explicit whitelists precede hidden-name/Windows-hidden filtering.
Global excludes use the listed directory as their matching base, and discover
the global/home/XDG/system config paths in the same order as `ignore 0.4.33`.

`files.Server` exposes the framed `listFiles` operation and `{count,truncated}`
result. `hello.features` advertises `listFiles`. `RemoteExecutionEnv` and
`LocalExecutionEnv` negotiate that feature before issuing a request, returning
`not_supported` with older daemons so callers can use their own walks. The local
adapter borrows the connection and delegates its remaining operations to the
existing native local environment. Durable's type-erased filesystem capability
exposes the optional operation and reports `not_supported` for providers that
do not implement it. Existing `openDirReader` pagination remains independent.

`env.nodePlatform` maps `windows` to `win32`, `macos` to `darwin`, `x86_64` to
`x64`, `aarch64` to `arm64`, and `x86` to `ia32`, preserving other names.

The scoped gate is `zig build test-env-list-files -Duse-llvm=true -j1`. It replays
the captured unmodified reference daemon bytes/errors, including 89 additional
ignore-pattern walks, and exercises real native local/remote transports,
old-daemon fallback, retained directory paging, cancellation, links, and
allocation-failure ownership. This component gate does not establish complete
Pi parity, activate a native default, or qualify a release.
