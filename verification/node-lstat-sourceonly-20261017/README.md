Source-only actual Node24.14 lstatSync/native metadata seam, based on exact
Root 8b36501abcc98563e7ba78c7c417fb024d672361. No runtime job was granted/run.
Expected and observed outputs are absent. Existing published ca974 jiti body
worktree and its proofs remain unchanged.

The product delta is confined to native_file_stat.zig and node_fs_metadata.zig.
readLink uses the real final-component no-follow metadata operation: Linux
statx AT_SYMLINK_NOFOLLOW; other POSIX fstatat AT_SYMLINK_NOFOLLOW; Windows
CreateFileW FILE_FLAG_OPEN_REPARSE_POINT plus BACKUP_SEMANTICS and shared access.
The handle supplies the real device/inode/size/times/attributes. Windows link
classification/size reads the actual FSCTL_GET_REPARSE_POINT payload, follows
the pinned libuv target prefix and WTF-8 length rules, handles drive junctions,
symbolic links and AppExecLink, and retries non-link reparse points with stat
as libuv does. A volume GUID mount point is not simply branded as a symlink.
No C/H/Engine edits or missing native IO primitive are required.

node:fs/fs now export an actual ordinary lstatSync function, length1, sharing
the genuine existing Stats/BigIntStats prototype graph with statSync. Path
validation precedes options.bigint/throwIfNoEntry reads, raw getter failures
propagate, only ENOENT is suppressed by throwIfNoEntry:false (Node lstat differs
from stat on ENOTDIR here), and filesystem errors identify syscall:lstat.
The existing Node path/Buffer/URL/Stats construction behavior is reused; this
does not independently qualify every preexisting Node metadata behavior.

The old stat.read path is retained. Its existing Windows directory execute
bits differ from the inspected libuv mode calculation; this separate known
gap is reported to Root. New lstat mode uses actual libuv 0666/0444 permissions
and does not inherit those extra bits, including the non-link reparse retry.
Preexisting stat error/permission coverage and the full public filesystem API
are not silently declared complete by this small seam.

The primary packet pins official Node24.14.0 immutable commit
f657bb8ed86365ff3fdbe32e27563e778b41486a: lib/fs.js, src/node_file.cc,
deps/uv/src/win/fs.c and unix/fs.c plus inert licenses. These source files
were read/downloaded only. No recovered/deleted runtime dependency is used.

source-caller.mjs is prepared genuine Node reference tooling, not a production
host implementation. A later Root controller must establish the newly owned
root and exact Node/version/inventory/resource/permission/process fences.
Its original fixture inputs cover regular files/directories, relative file and
directory symlinks, broken links, a Unicode target, a self-link, and Windows
junction/broken junction. Link creation failures are explicit raw observation
rows, never silent success/skip. Numeric/BigInt Stats own fields/type witnesses,
method results, original errors and options/getter order are recorded. The
genuine jiti isDir consumer remains with its factory owner; no copied helper
algorithm is used as an oracle. No fixture was created or caller executed here.
Unusual cloud/volume/AppExec reparse targets and access-denied kernel fixtures
require separately admitted real fixtures; they are not synthetic OS goldens.
