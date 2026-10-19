# Genuine native TCP source unit

This unit uses the unchanged Node v24.13.0 libuv and llhttp source bytes pinned by `vendor/node-v24.13.0/SOURCE-MANIFEST.json`. The source membership and selected Windows/Linux build flags were compared with the actual libuv build definition. No generator or native execution was used for this handoff.

The C owner supplies a real native event loop, uv TCP handles, native requests and counted events. It charges its own objects and byte payloads against the existing independent memory owner; unchanged libuv retains its actual allocator. A wrapper allocation failure is a distinct producer from libuv's ordinary UV_ENOMEM status. Commands are admitted on one owning host thread, and native callbacks never access Engine or guest values.

The Zig adapter consumes the existing canonical Hub, Socket, Provider and wake owners. It retains accepted/connect endpoints and original Socket callback tokens, delivers packets only on the owning host thread, and uses C435 before retiring failed or completed owners. Source peers read the actual current Main prerequisites rather than inventing replacements for the older worktree's absent copies.

Twelve declared controls target the actual C owner: ephemeral loopback connections, byte ownership, read ACK and new-demand ordering, half close, unclaimed accept, ordinary statuses, independent allocation failure, observed close tokens, reference state and native storage surviving its original runtime. The two peer slices are closed. These are authored physical controls; none has been compiled, queried or executed in this source unit.

Build target: `build-native-node-tcp-transport`. Filter: `native actual TCP`. Root: `src/native_node_tcp_transport_test.zig`. The install-only target produces `test.exe` on Windows. One `native_node_network` library is available for the TCP target and subsequent genuine file-I/O consumers. Platforms outside the admitted Windows/Linux sets omit this target.

This does not claim public net.Server/HTTP behavior, canonical Socket adapter runtime qualification, DNS support, or a complete physical OAuth callback route. Those production composition and control boundaries remain explicit in `source-status.json`. The isolated `native_node_tcp_os` syscall draft is not part of this unit.
