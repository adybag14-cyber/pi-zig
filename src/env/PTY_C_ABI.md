# Direct C terminal ABI exception

`pty_abi.c` is the narrow POSIX terminal ABI called by the native Zig terminal
owner. It supplies openpty/fork/execve, descriptor operations, terminal resize,
process status and signal operations, and platform errno formatting. macOS
process-name lookup uses libproc. On Windows the translation unit contains only
a type declaration; native Windows terminal handling remains in Zig.

Zig owns program selection, arguments, environment, queues, protocol, allocation,
admission, deadlines, and process lifecycle. The child receives prepared inputs
and performs the POSIX setup before execve; the close-on-exec status pipe reports
startup errors to the parent. This file is covered by the terminal ABI tests and
the separate terminal contract workflow. Registering this exact source path in
the source audit records the permitted direct C exception. It does not broaden
the audit to arbitrary C implementations or establish physical terminal parity.
