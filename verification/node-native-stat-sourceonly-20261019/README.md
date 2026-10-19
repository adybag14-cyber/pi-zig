# Native Node stat and readlink producers — source-only unit

This unit adds the physical status/target producers needed by actual classic
`fs.realpathSync`. It does not install that public function yet. No compiler,
metadata query, Node capture, physical filesystem control, or runtime was run.

## Source payload

- `src/extensions/native_file_stat.zig`: raw SHA-256
  `19F01E58B2E75115578A95F5040307D2F8425F5AAC2B404F1642D2B091BB7893`.
  Adds followed/no-follow status unions and an owned readlink byte buffer.
  The new status route retains actual numeric OS failure before native cleanup.
  Linux follows the bundled libuv readlink allocation/EINTR and statx/fallback
  path, including direct birthtime mapping. Existing callers of the original
  status-free metadata entry keep their existing field policy.
- `src/extensions/native_node_fs_stat_windows.zig`: raw SHA-256
  `476FC6440BA0C9B37F4AAED724970989275ADD9A29C8A13F9E28F8638BCCEDFB`.
  Implements the real optional GetFileInformationByName path and NT handle /
  directory fallback, including warning status handling, reparse handling,
  and one no-follow retry after the first handle closes. Layout assertions
  retain the actual pinned Windows API buffer offsets.

The new status producers admit Windows and Linux. Native allocation/encoding
failure remains a typed failure; it is not converted into a fabricated errno.
No guest object or callback is used in these native operations. Callers must
retain the selected native path and finish through the existing Node boundary.

## Pinned authority

Node `v24.13.0` is the authority. The retained files below were independently
checked against the official versioned raw URLs; their older evidence-directory
date does not change the verified source version.

- `verification/node-lstat-sourceonly-20261017/authority/libuv-win-fs.c.txt`:
  `60C76976514F427FA0BE21C1C7986C2AB1D9E2E77B9D5BCF8C7AB99ED36B0693`,
  https://raw.githubusercontent.com/nodejs/node/v24.13.0/deps/uv/src/win/fs.c
- `verification/node-lstat-sourceonly-20261017/authority/libuv-unix-fs.c.txt`:
  `FFE2CD709C894083D4E470BCE5248EEE71C5E5594418BE3D7A6D80E44D723A61`,
  https://raw.githubusercontent.com/nodejs/node/v24.13.0/deps/uv/src/unix/fs.c
- `authority/libuv-linux-statx.c.txt` is the exact 1004-byte
  `uv__statx_to_stat` definition, beginning at source byte 29430, from
  https://raw.githubusercontent.com/nodejs/node/v24.13.0/deps/uv/src/unix/linux.c.
  Full source SHA-256:
  `D527B1B7330C474F60B363B0EC8CCEA50BC2F1B7AE7E185FC97B6943BF993D99`;
  excerpt SHA-256:
  `A52C63F69597C88974759B084A070CD37885954623D371706D904DBA581325CC`.
- Windows declarations were compared with the actual pinned Zig 0.16.0
  `std/os/windows/ntdll.zig`, `std/os/windows.zig`, and bundled NT headers,
  plus Node's `deps/uv/src/win/winapi.h` raw SHA-256
  `5E8414CC8F3EEFCB8389FD61BEA6B9BFE74C057D899A6C9C2B3CDB43F6A3EF16`.
- The retained libuv license is
  `verification/node-lstat-sourceonly-20261017/authority/libuv-LICENSE`.

## Bounded source review

VM foundation reviewed Windows stat owner/status/layout/fallback behavior and
the shared Windows readlink-length producer at raw stat `19F01E58`.
Its reviewed Windows pin `8437AAF4` was followed only by explicit
`w.BOOLEAN.TRUE` qualification for the two existing TRUE arguments, matching
the pinned BOOLEAN constant declaration.

SDK owners reviewed the Linux LinkBytes/readlink allocation and status path,
statx disable/fallback behavior, and the exact statx-to-stat field mapping at
`19F01E58`. These are finite source reviews. They do not establish compilation,
physical Windows/Linux behavior, public FS installation, or classic realpath
parity. The classic caller/control unit supplies the later genuine consumer
and installation target.

This unit changes no build target or declared test count.
