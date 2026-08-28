//! Native Pi server transport and stateful protocol core.
//! Binary clients use length-prefixed CBOR; HTTP remains diagnostic compatibility only.
const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const protocol = @import("../protocol/root.zig");
const providers = @import("../ai/providers.zig");
const thinking = @import("../ai/thinking.zig");
const session_store = @import("session_store.zig");
const agent = @import("../agent/root.zig");
const ai = @import("../ai/root.zig");
const live_state = @import("../coding_agent/live_state.zig");
const project_environment = @import("../coding_agent/project_environment.zig");
const runtime_config = @import("../coding_agent/runtime_config.zig");
const models_file_mod = @import("../coding_agent/models_file.zig");
const file_permissions = @import("../file_permissions.zig");

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 3141,
    auth_token: []const u8 = "",
    max_frame_length: usize = protocol.framing.DEFAULT_MAX_FRAME_LENGTH,
    handshake_timeout_ms: u64 = 5000,
    model_catalog: []const providers.ModelInfo = &providers.known_models,
    models_file: ?*const models_file_mod.ModelsFile = null,
    session_dir: ?[]const u8 = null,
    /// Optional linked persistence implementation. Mutually exclusive with
    /// `session_dir`, which remains the default JSON-file backend.
    persistence: ?session_store.PersistenceBackend = null,
    unix_socket: ?[]const u8 = null,
    environ: ?*const std.process.Environ.Map = null,
    agent_dir: ?[]const u8 = null,
    trust_project: bool = false,
    mock_script: ?[]const u8 = null,
};

const Peer = struct {
    connection_id: []const u8,
    stream: *net.Stream,
    write_mutex: Io.Mutex = .init,
};

pub const Server = struct {
    gpa: std.mem.Allocator,
    io: Io,
    config: ServerConfig,
    running: std.atomic.Value(bool) = .init(false),
    sessions: session_store.SessionStore = .{},
    sessions_mutex: Io.Mutex = .init,
    peers: std.ArrayList(*Peer) = .empty,
    peers_mutex: Io.Mutex = .init,

    pub fn deinit(self: *Server) void {
        self.sessions_mutex.lockUncancelable(self.io);
        defer self.sessions_mutex.unlock(self.io);
        self.sessions.deinit(self.gpa);
        self.peers.deinit(self.gpa);
    }

    pub fn start(self: *Server) !void {
        if (self.config.persistence != null and self.config.session_dir != null) {
            return error.ConflictingSessionPersistence;
        }
        self.sessions_mutex.lockUncancelable(self.io);
        defer self.sessions_mutex.unlock(self.io);
        if (self.sessions.sessions.items.len == 0) {
            if (self.config.persistence) |backend| {
                _ = try backend.loadAll(&self.sessions, self.gpa, self.io);
            } else if (self.config.session_dir) |dir_path| {
                _ = try session_store.loadAll(&self.sessions, self.gpa, self.io, dir_path);
            }
        }
        self.running.store(true, .release);
    }

    pub fn stop(self: *Server) void {
        self.running.store(false, .release);
    }

    pub fn serveLoop(self: *Server) !void {
        try self.start();
        if (self.config.unix_socket) |path| {
            const lock_path = try std.fmt.allocPrint(self.gpa, "{s}.lock", .{path});
            defer self.gpa.free(lock_path);
            var ownership = std.Io.Dir.cwd().createFile(self.io, lock_path, .{
                .truncate = false,
                .lock = .exclusive,
                .lock_nonblocking = true,
                .permissions = file_permissions.privateFile(),
            }) catch |err| switch (err) {
                error.WouldBlock => return error.AddressInUse,
                else => return err,
            };
            defer ownership.close(self.io);
            defer std.Io.Dir.cwd().deleteFile(self.io, lock_path) catch {};
            try self.prepareUnixSocketPath(path);
            const address = try net.UnixAddress.init(path);
            var listener = try address.listen(self.io, .{});
            defer listener.deinit(self.io);
            std.Io.Dir.cwd().setFilePermissions(self.io, path, file_permissions.privateFile(), .{}) catch {};
            defer std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
            return self.serveListener(&listener);
        }
        const addr = try parseBindAddress(self.config.host, self.config.port);
        var listener = try addr.listen(self.io, .{ .reuse_address = true });
        defer listener.deinit(self.io);
        return self.serveListener(&listener);
    }

    fn serveListener(self: *Server, listener: *net.Server) !void {
        var group: Io.Group = .init;
        defer group.cancel(self.io);
        while (self.running.load(.acquire)) {
            var stream = listener.accept(self.io) catch |err| switch (err) {
                error.SocketNotListening => break,
                else => continue,
            };
            group.concurrent(self.io, connectionTask, .{ self, stream }) catch {
                stream.close(self.io);
                continue;
            };
        }
    }

    fn prepareUnixSocketPath(self: *Server, path: []const u8) !void {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        if (stat.kind != .unix_domain_socket) return error.UnsafeUnixSocketPath;
        // Ownership of the adjacent lock file is held for the server lifetime.
        // Therefore any socket node present here belongs to a dead previous server
        // and is safe to reclaim; a live peer could not have yielded the lock.
        try std.Io.Dir.cwd().deleteFile(self.io, path);
    }

    fn connectionTask(self: *Server, stream_value: net.Stream) void {
        var stream = stream_value;
        defer stream.close(self.io);
        self.handleConnection(&stream) catch {};
    }

    fn handleConnection(self: *Server, stream: *net.Stream) !void {
        const connection_id = try makeConnectionId(self.gpa, self.io);
        defer self.gpa.free(connection_id);
        var cleanup_done = false;
        defer if (!cleanup_done) self.cleanupConnection(connection_id);
        var peer: ?*Peer = null;
        defer if (peer) |p| self.unregisterPeer(p);

        var prefix: [4]u8 = undefined;
        self.readInitialPrefix(stream, &prefix) catch |err| {
            if (err == error.Timeout) {
                const timeout_json = "{\"type\":\"hello_error\",\"error\":{\"code\":\"invalid_request\",\"message\":\"Handshake timeout\"}}";
                self.writeBinaryJson(stream, timeout_json) catch {};
            }
            return err;
        };
        var rbuf: [8192]u8 = undefined;
        var reader = stream.reader(self.io, &rbuf);
        const is_http = std.mem.eql(u8, &prefix, "GET ") or std.mem.eql(u8, &prefix, "POST");
        const is_raw_json = prefix[0] == '{';

        if (!is_http and !is_raw_json) {
            var ready = false;
            var request_group: Io.Group = .init;
            // Hello is processed synchronously. Requests after hello are dispatched
            // concurrently so the same connection remains able to steer/abort a turn.
            try self.handleBinaryFrame(stream, &reader.interface, connection_id, &ready, &peer, &request_group, prefix);
            while (true) {
                reader.interface.readSliceAll(&prefix) catch break;
                self.handleBinaryFrame(stream, &reader.interface, connection_id, &ready, &peer, &request_group, prefix) catch break;
            }
            // Disconnect attachment state immediately, but keep Peer/stream storage alive
            // until already-dispatched requests have unwound.
            self.cleanupConnection(connection_id);
            cleanup_done = true;
            request_group.await(self.io) catch {};
            return;
        }

        var req: std.ArrayList(u8) = .empty;
        defer req.deinit(self.gpa);
        try req.appendSlice(self.gpa, &prefix);
        var http_head: ?HttpHead = null;
        if (is_raw_json) {
            // Raw JSON is a diagnostic compatibility path. Preserve its
            // one-frame behavior while allowing a complete ordinary read.
            var tmp: [8192]u8 = undefined;
            const n = readAvailable(&reader.interface, tmp[0..]) catch 0;
            if (n > 0) try req.appendSlice(self.gpa, tmp[0..n]);
        } else {
            const max_header_bytes: usize = 64 * 1024;
            while (httpHeaderBoundary(req.items) == null and req.items.len < max_header_bytes) {
                var tmp: [2048]u8 = undefined;
                const remaining = max_header_bytes - req.items.len;
                const n = readAvailable(&reader.interface, tmp[0..@min(tmp.len, remaining)]) catch 0;
                if (n == 0) break;
                try req.appendSlice(self.gpa, tmp[0..n]);
            }
            const parsed_head = parseHttpHead(req.items) catch {
                try writeHttp(self.io, stream, 400, "{\"error\":\"invalid HTTP request\"}\n");
                return;
            };
            if (parsed_head.content_length > self.config.max_frame_length) {
                try writeHttp(self.io, stream, 413, "{\"error\":\"request body too large\"}\n");
                return;
            }
            const total_length = std.math.add(usize, parsed_head.body_offset, parsed_head.content_length) catch {
                try writeHttp(self.io, stream, 413, "{\"error\":\"request body too large\"}\n");
                return;
            };
            if (req.items.len > total_length) {
                try writeHttp(self.io, stream, 400, "{\"error\":\"unexpected bytes after request body\"}\n");
                return;
            }
            while (req.items.len < total_length) {
                var tmp: [8192]u8 = undefined;
                const remaining = total_length - req.items.len;
                const n = readAvailable(&reader.interface, tmp[0..@min(tmp.len, remaining)]) catch 0;
                if (n == 0) break;
                try req.appendSlice(self.gpa, tmp[0..n]);
            }
            if (req.items.len != total_length) {
                try writeHttp(self.io, stream, 400, "{\"error\":\"truncated request body\"}\n");
                return;
            }
            http_head = parsed_head;
        }

        if (!httpAuthorized(req.items, self.config.auth_token)) {
            try writeHttp(self.io, stream, 401, "{\"error\":\"unauthorized\"}\n");
            return;
        }

        const first_line = firstLine(req.items);
        if (!is_raw_json and std.mem.startsWith(u8, first_line, "GET /health ")) {
            try writeHttp(self.io, stream, 200, "{\"ok\":true,\"protocolVersion\":1}\n");
            return;
        }
        if (!is_raw_json and std.mem.startsWith(u8, first_line, "GET /routes ")) {
            try writeHttp(self.io, stream, 200, "{\"routes\":[\"GET /health\",\"POST /rpc\"]}\n");
            return;
        }
        if (!is_raw_json and !std.mem.startsWith(u8, first_line, "POST /rpc ")) {
            try writeHttp(self.io, stream, 404, "{\"error\":\"route not found\"}\n");
            return;
        }

        const body = if (http_head) |head|
            req.items[head.body_offset .. head.body_offset + head.content_length]
        else
            req.items;
        const response = try self.handleRpcBodyForConnection(connection_id, if (body.len > 0) body else req.items);
        defer self.gpa.free(response);
        try writeHttp(self.io, stream, 200, response);
    }

    fn readInitialPrefix(self: *Server, stream: *net.Stream, prefix: *[4]u8) !void {
        const timeout_ms: i64 = @intCast(@min(self.config.handshake_timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
        const deadline: Io.Timeout = .{ .deadline = .fromNow(self.io, .{ .raw = Io.Duration.fromMilliseconds(timeout_ms), .clock = .awake }) };
        var offset: usize = 0;
        while (offset < prefix.len) {
            const message = try stream.socket.receiveTimeout(self.io, prefix[offset..], deadline);
            if (message.data.len == 0) return error.EndOfStream;
            offset += message.data.len;
        }
    }

    fn handleBinaryFrame(
        self: *Server,
        stream: *net.Stream,
        reader: *Io.Reader,
        connection_id: []const u8,
        ready: *bool,
        peer: *?*Peer,
        request_group: *Io.Group,
        prefix: [4]u8,
    ) !void {
        const payload_len = decodeLength(&prefix);
        if (payload_len > self.config.max_frame_length) return error.FrameTooLarge;
        const frame = try self.gpa.alloc(u8, payload_len + 4);
        defer self.gpa.free(frame);
        @memcpy(frame[0..4], &prefix);
        try reader.readSliceAll(frame[4..]);
        const json_in = try protocol.codec.decodeFrameToJson(self.gpa, frame);
        defer self.gpa.free(json_in);

        var parsed = protocol.json.parseClientMessage(self.gpa, json_in) catch {
            const err_json = "{\"type\":\"hello_error\",\"error\":{\"code\":\"invalid_request\",\"message\":\"Invalid client protocol message\"}}";
            try self.writeBinaryJson(stream, err_json);
            return error.InvalidProtocolMessage;
        };
        defer protocol.json.deinitClientMessage(self.gpa, &parsed);

        if (!ready.*) {
            if (parsed != .hello) {
                const err_json = "{\"type\":\"hello_error\",\"error\":{\"code\":\"invalid_request\",\"message\":\"hello must be the first client message\"}}";
                try self.writeBinaryJson(stream, err_json);
                return error.HelloRequired;
            }
            if (!protocol.messages.isSupportedProtocolVersion(parsed.hello.version)) {
                const msg = try std.fmt.allocPrint(self.gpa, "{{\"type\":\"hello_error\",\"error\":{{\"code\":\"version\",\"message\":\"Unsupported protocol version {d}; expected {d}\"}}}}", .{ parsed.hello.version, protocol.PROTOCOL_VERSION });
                defer self.gpa.free(msg);
                try self.writeBinaryJson(stream, msg);
                return error.UnsupportedVersion;
            }
            const hello = try self.makeHelloJson(connection_id);
            defer self.gpa.free(hello);
            try self.writeBinaryJson(stream, hello);
            ready.* = true;
            peer.* = try self.registerPeer(connection_id, stream);
            return;
        }

        if (parsed == .hello) {
            const err_json = "{\"type\":\"hello_error\",\"error\":{\"code\":\"invalid_request\",\"message\":\"hello may only be sent once\"}}";
            try self.writeBinaryJson(stream, err_json);
            return error.DuplicateHello;
        }
        const owned_json = try self.gpa.dupe(u8, json_in);
        errdefer self.gpa.free(owned_json);
        try request_group.concurrent(self.io, requestTask, .{ self, peer.*.?, connection_id, owned_json });
    }

    fn requestTask(self: *Server, peer: *Peer, connection_id: []const u8, json_owned: []u8) Io.Cancelable!void {
        defer self.gpa.free(json_owned);
        var parsed = protocol.json.parseClientMessage(self.gpa, json_owned) catch return;
        defer protocol.json.deinitClientMessage(self.gpa, &parsed);
        if (parsed != .request) return;

        const response = self.executeRequestJson(connection_id, parsed.request) catch return;
        defer self.gpa.free(response);
        const sid = self.eventSessionId(parsed.request.request, response) catch null;
        defer if (sid) |id| self.gpa.free(id);
        if (sid) |id| self.broadcastSessionSnapshot(id) catch {};
        self.writePeerJson(peer, response) catch {};
        if (requestChangesServerSnapshot(parsed.request.request)) self.broadcastServerSnapshots() catch {};
    }

    fn writeBinaryJson(self: *Server, stream: *net.Stream, json: []const u8) !void {
        const frame = try protocol.codec.encodeJsonFrame(self.gpa, json);
        defer self.gpa.free(frame);
        if (frame.len < 4 or frame.len - 4 > self.config.max_frame_length) return error.FrameTooLarge;
        var wbuf: [4096]u8 = undefined;
        var writer = stream.writer(self.io, &wbuf);
        try writer.interface.writeAll(frame);
        try writer.interface.flush();
    }

    fn registerPeer(self: *Server, connection_id: []const u8, stream: *net.Stream) !*Peer {
        const peer = try self.gpa.create(Peer);
        errdefer self.gpa.destroy(peer);
        peer.* = .{ .connection_id = connection_id, .stream = stream };
        self.peers_mutex.lockUncancelable(self.io);
        defer self.peers_mutex.unlock(self.io);
        try self.peers.append(self.gpa, peer);
        return peer;
    }

    fn unregisterPeer(self: *Server, peer: *Peer) void {
        self.peers_mutex.lockUncancelable(self.io);
        defer self.peers_mutex.unlock(self.io);
        for (self.peers.items, 0..) |candidate, i| {
            if (candidate == peer) {
                _ = self.peers.orderedRemove(i);
                self.gpa.destroy(peer);
                return;
            }
        }
    }

    fn writePeerJson(self: *Server, peer: *Peer, json: []const u8) !void {
        peer.write_mutex.lockUncancelable(self.io);
        defer peer.write_mutex.unlock(self.io);
        try self.writeBinaryJson(peer.stream, json);
    }

    fn eventSessionId(self: *Server, request: protocol.messages.Command, response: []const u8) !?[]u8 {
        return switch (request) {
            .list => null,
            .create => blk: {
                var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, response, .{}) catch break :blk null;
                defer parsed.deinit();
                if (parsed.value != .object) break :blk null;
                const result = parsed.value.object.get("result") orelse break :blk null;
                if (result != .object) break :blk null;
                const session = result.object.get("session") orelse break :blk null;
                if (session != .object) break :blk null;
                const id = session.object.get("id") orelse break :blk null;
                if (id != .string) break :blk null;
                break :blk try self.gpa.dupe(u8, id.string);
            },
            .attach => |cmd| try self.gpa.dupe(u8, cmd.session_id),
            .detach => |cmd| try self.gpa.dupe(u8, cmd.session_id),
            .prompt => null,
            .set_model => |cmd| try self.gpa.dupe(u8, cmd.session_id),
            .set_thinking => |cmd| try self.gpa.dupe(u8, cmd.session_id),
            .steer => |cmd| try self.gpa.dupe(u8, cmd.session_id),
            .abort => |cmd| try self.gpa.dupe(u8, cmd.session_id),
        };
    }

    fn broadcastSessionSnapshot(self: *Server, session_id: []const u8) !void {
        self.peers_mutex.lockUncancelable(self.io);
        defer self.peers_mutex.unlock(self.io);
        for (self.peers.items) |peer| {
            self.sessions_mutex.lockUncancelable(self.io);
            var out: Io.Writer.Allocating = .init(self.gpa);
            const session = self.sessions.find(session_id);
            if (session == null or !session.?.isAttachedTo(peer.connection_id)) {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                continue;
            }
            out.writer.writeAll("{\"type\":\"event\",\"event\":{\"type\":\"session_snapshot\",\"snapshot\":") catch |err| {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                return err;
            };
            writeSessionSnapshot(&out.writer, session.?, peer.connection_id) catch |err| {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                return err;
            };
            out.writer.writeAll("}}") catch |err| {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                return err;
            };
            const json = out.toOwnedSlice() catch |err| {
                self.sessions_mutex.unlock(self.io);
                return err;
            };
            self.sessions_mutex.unlock(self.io);
            defer self.gpa.free(json);
            try self.writePeerJson(peer, json);
        }
    }

    fn broadcastServerSnapshots(self: *Server) !void {
        self.sessions_mutex.lockUncancelable(self.io);
        self.sessions.server_revision += 1;
        self.sessions_mutex.unlock(self.io);

        self.peers_mutex.lockUncancelable(self.io);
        defer self.peers_mutex.unlock(self.io);
        for (self.peers.items) |peer| {
            self.sessions_mutex.lockUncancelable(self.io);
            var out: Io.Writer.Allocating = .init(self.gpa);
            out.writer.writeAll("{\"type\":\"event\",\"event\":{\"type\":\"server_snapshot\",\"snapshot\":") catch |err| {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                return err;
            };
            self.writeServerSnapshotLocked(&out.writer) catch |err| {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                return err;
            };
            out.writer.writeAll("}}") catch |err| {
                self.sessions_mutex.unlock(self.io);
                out.deinit();
                return err;
            };
            const json = out.toOwnedSlice() catch |err| {
                self.sessions_mutex.unlock(self.io);
                return err;
            };
            self.sessions_mutex.unlock(self.io);
            defer self.gpa.free(json);
            try self.writePeerJson(peer, json);
        }
    }

    fn cleanupConnection(self: *Server, connection_id: []const u8) void {
        self.sessions_mutex.lockUncancelable(self.io);
        const removed = self.sessions.disconnect(self.gpa, connection_id);
        if (self.config.persistence) |backend| {
            for (self.sessions.sessions.items) |session| {
                if (!session.locked()) backend.releaseSession(session.id);
            }
        }
        self.sessions_mutex.unlock(self.io);
        if (removed > 0) self.broadcastServerSnapshots() catch {};
    }

    /// JSON diagnostic/compatibility adapter. Unlike binary transport, this does
    /// not require a persistent hello handshake.
    pub fn handleRpcBody(self: *Server, body: []const u8) ![]u8 {
        const cid = "pi-zig-http";
        defer self.cleanupConnection(cid);
        return self.handleRpcBodyForConnection(cid, body);
    }

    fn handleRpcBodyForConnection(self: *Server, connection_id: []const u8, body: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        var it = std.mem.splitScalar(u8, body, '\n');
        while (it.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r");
            if (t.len == 0 or std.mem.startsWith(u8, t, "POST ") or std.mem.startsWith(u8, t, "GET ") or
                std.mem.startsWith(u8, t, "HTTP/") or (std.mem.indexOf(u8, t, ": ") != null and t[0] != '{')) continue;
            var message = protocol.json.parseClientMessage(self.gpa, t) catch {
                try out.appendSlice(self.gpa, "{\"type\":\"response\",\"id\":\"invalid\",\"ok\":false,\"error\":{\"code\":\"invalid_request\",\"message\":\"Invalid client protocol message\"}}\n");
                continue;
            };
            defer protocol.json.deinitClientMessage(self.gpa, &message);
            const json = switch (message) {
                .hello => |hello| blk: {
                    if (!protocol.messages.isSupportedProtocolVersion(hello.version)) {
                        break :blk try std.fmt.allocPrint(self.gpa, "{{\"type\":\"hello_error\",\"error\":{{\"code\":\"version\",\"message\":\"Unsupported protocol version {d}; expected {d}\"}}}}", .{ hello.version, protocol.PROTOCOL_VERSION });
                    }
                    break :blk try self.makeHelloJson(connection_id);
                },
                .request => |request| try self.executeRequestJson(connection_id, request),
            };
            defer self.gpa.free(json);
            try out.appendSlice(self.gpa, json);
            try out.append(self.gpa, '\n');
        }
        if (out.items.len == 0) try out.appendSlice(self.gpa, "{\"error\":\"empty request\"}\n");
        return try out.toOwnedSlice(self.gpa);
    }

    fn executeRequestJson(self: *Server, connection_id: []const u8, request: protocol.messages.RequestEnvelope) ![]u8 {
        switch (request.request) {
            .prompt => |cmd| return self.executePrompt(connection_id, request.id, cmd.session_id, cmd.text),
            else => {},
        }
        self.sessions_mutex.lockUncancelable(self.io);
        defer self.sessions_mutex.unlock(self.io);
        return self.executeRequestLocked(connection_id, request);
    }

    fn executePrompt(self: *Server, connection_id: []const u8, request_id: []const u8, session_id: []const u8, text: []const u8) ![]u8 {
        self.sessions_mutex.lockUncancelable(self.io);
        _ = self.sessions.requireAttached(connection_id, session_id) catch |err| {
            self.sessions_mutex.unlock(self.io);
            return self.storeErrorJson(request_id, err);
        };
        if (self.config.persistence) |backend| {
            backend.claimSession(session_id) catch {
                self.sessions_mutex.unlock(self.io);
                return self.errorJson(request_id, "session_locked", "Session is owned by another server");
            };
        }
        const session = self.sessions.beginOperation(connection_id, session_id, .turn) catch |err| {
            self.sessions_mutex.unlock(self.io);
            return self.storeErrorJson(request_id, err);
        };
        @atomicStore(bool, &session.abort_flag, false, .release);
        const cwd = try self.gpa.dupe(u8, session.cwd);
        const provider_id = try self.gpa.dupe(u8, session.model_provider);
        const model_id = try self.gpa.dupe(u8, session.model_id);
        const thinking_level = session.thinking_level;
        self.sessions_mutex.unlock(self.io);
        defer self.gpa.free(cwd);
        defer self.gpa.free(provider_id);
        defer self.gpa.free(model_id);

        try self.broadcastSessionSnapshot(session_id);

        var mock_storage: ?ai.mock.MockModel = null;
        defer if (mock_storage) |*m| m.deinit(self.gpa);
        var resolved_runtime: ?runtime_config.ResolvedRuntime = null;
        defer if (resolved_runtime) |*runtime| runtime.deinit();
        var pool: live_state.ClientPool = .{ .gpa = self.gpa, .io = self.io };
        defer if (mock_storage == null) pool.deinit();
        var client: ai.ModelClient = undefined;

        const model_info = session_store.findModel(self.config.model_catalog, provider_id, model_id) orelse {
            self.finishPromptOperation(session_id) catch {};
            return self.errorJson(request_id, "invalid_request", "Unknown model");
        };
        if (model_info.provider == .mock) {
            if (self.config.mock_script) |path| {
                const raw = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(8 * 1024 * 1024));
                defer self.gpa.free(raw);
                mock_storage = try ai.mock.MockModel.loadFromJson(self.gpa, raw);
            } else {
                mock_storage = .{ .responses = try self.gpa.alloc(ai.mock.MockResponse, 0) };
            }
            client = mock_storage.?.client();
        } else {
            const environ = self.config.environ orelse {
                self.finishPromptOperation(session_id) catch {};
                return self.errorJson(request_id, "internal_error", "Server environment is unavailable");
            };
            resolved_runtime = runtime_config.resolveForModel(self.gpa, self.io, environ, self.config.models_file, model_info, .{
                .agent_dir = self.config.agent_dir,
            }) catch {
                self.finishPromptOperation(session_id) catch {};
                return self.errorJson(request_id, "internal_error", "Unable to resolve model runtime");
            };
            const runtime = &resolved_runtime.?;
            pool.setKeys(null, null, null, providers.defaultBaseUrl(.openai));
            pool.setRuntimeConfig(environ, runtime.transport, runtime.provider_id, runtime.api_key, runtime.base_url);
            pool.setAuthAgentDir(self.config.agent_dir);
            pool.setPrimaryOAuthMetadata(runtime.oauth_refresh, runtime.oauth_expires_ms, runtime.oauth_enterprise_url);
            pool.setPrimaryRequestMetadata(runtime.headers, runtime.sampling_params, runtime.compat, runtime.max_tokens, runtime.context_window, runtime.input_image);
            pool.setPrimaryModelRuntime(runtime.api, runtime.model_cost);
            const retention = if (environ.get("PI_CACHE_RETENTION")) |value|
                (ai.request_metadata.CacheRetention.parse(value) orelse .short)
            else
                .short;
            pool.setSessionContext(session_id, retention);
            pool.setThinking(session_store.fromProtocolThinking(thinking_level));
            pool.setAbortFlag(&session.abort_flag);
            pool.switchToIdentity(runtime.provider_id, runtime.transport, runtime.model_id) catch {
                self.finishPromptOperation(session_id) catch {};
                return self.errorJson(request_id, "internal_error", "Unable to initialize model runtime");
            };
            client = pool.client;
        }

        const assistant_id = try std.fmt.allocPrint(self.gpa, "assistant-{d}", .{session.revision + 1});
        defer self.gpa.free(assistant_id);
        var event_ctx = PromptEventContext{
            .server = self,
            .session_id = session_id,
            .assistant_id = assistant_id,
            .provider_id = provider_id,
            .model_id = model_id,
            .timestamp = session.updated_at + 1,
        };
        var steer_ctx = SteerDrainContext{ .server = self, .session_id = session_id };
        var project_env = project_environment.load(self.gpa, self.io, cwd, .{
            .agent_dir = self.config.agent_dir,
            .trust_project = self.config.trust_project,
            .thinking_level = @tagName(thinking_level),
        }) catch {
            self.finishPromptOperation(session_id) catch {};
            return self.errorJson(request_id, "internal_error", "Unable to load project environment");
        };
        defer project_env.deinit();
        var session_file: ?[]u8 = null;
        defer if (session_file) |path| self.gpa.free(path);
        if (self.config.session_dir) |dir_path| {
            const file_name = try std.fmt.allocPrint(self.gpa, "{s}.json", .{session_id});
            defer self.gpa.free(file_name);
            session_file = try std.fs.path.join(self.gpa, &.{ dir_path, file_name });
        }
        var cfg = project_env.agentConfig();
        cfg.process_environ = self.config.environ;
        cfg.session_id = session_id;
        cfg.session_file = session_file;
        cfg.provider_name = provider_id;
        cfg.model_id = model_id;
        cfg.compaction_context_window = model_info.context_window;
        cfg.reasoning_level = @tagName(thinking_level);
        cfg.abort_flag = &session.abort_flag;
        cfg.take_steer_fn = SteerDrainContext.take;
        cfg.take_steer_ctx = &steer_ctx;
        var result = agent.run(self.gpa, self.io, cwd, client, &session.native, text, cfg, PromptEventContext.onEvent, &event_ctx) catch {
            self.finishPromptOperation(session_id) catch {};
            return self.errorJson(request_id, "internal_error", "Agent prompt failed");
        };
        result.deinit(self.gpa);

        self.sessions_mutex.lockUncancelable(self.io);
        const finished = self.sessions.endOperation(self.io, session_id) catch |err| {
            self.sessions_mutex.unlock(self.io);
            return self.storeErrorJson(request_id, err);
        };
        self.persistSessionLocked(finished) catch {
            self.sessions_mutex.unlock(self.io);
            return self.errorJson(request_id, "internal_error", "Unable to persist session");
        };
        const response = try self.sessionResultJson(request_id, "prompt", finished, connection_id);
        self.sessions_mutex.unlock(self.io);
        try self.broadcastSessionSnapshot(session_id);
        return response;
    }

    fn finishPromptOperation(self: *Server, session_id: []const u8) !void {
        self.sessions_mutex.lockUncancelable(self.io);
        const session = self.sessions.endOperation(self.io, session_id) catch |err| {
            self.sessions_mutex.unlock(self.io);
            return err;
        };
        self.persistSessionLocked(session) catch {};
        if (!session.locked()) {
            if (self.config.persistence) |backend| backend.releaseSession(session.id);
        }
        self.sessions_mutex.unlock(self.io);
        self.broadcastSessionSnapshot(session_id) catch {};
    }

    const SteerDrainContext = struct {
        server: *Server,
        session_id: []const u8,

        fn take(ptr: ?*anyopaque, gpa: std.mem.Allocator) anyerror!?[]u8 {
            _ = gpa; // Server and agent use the same allocator; ownership transfers.
            const self: *SteerDrainContext = @ptrCast(@alignCast(ptr.?));
            self.server.sessions_mutex.lockUncancelable(self.server.io);
            const msg = self.server.sessions.takeSteer(self.server.gpa, self.server.io, self.session_id) catch |err| {
                self.server.sessions_mutex.unlock(self.server.io);
                return err;
            };
            self.server.sessions_mutex.unlock(self.server.io);
            return msg;
        }
    };

    const PromptEventContext = struct {
        server: *Server,
        session_id: []const u8,
        assistant_id: []const u8,
        provider_id: []const u8,
        model_id: []const u8,
        timestamp: u64,

        fn onEvent(ptr: ?*anyopaque, event: agent.AgentEvent) void {
            const self: *PromptEventContext = @ptrCast(@alignCast(ptr.?));
            // Renew a linked backend's writer fence during long-running model
            // and tool streams. In-memory/JSON backends make this a no-op.
            if (self.server.config.persistence) |backend| backend.claimSession(self.session_id) catch return;
            var out: Io.Writer.Allocating = .init(self.server.gpa);
            defer out.deinit();
            switch (event.kind) {
                .message_start => if (std.mem.eql(u8, event.name, "assistant")) {
                    out.writer.writeAll("{\"type\":\"item_started\",\"item\":{\"id\":") catch return;
                    std.json.Stringify.value(self.assistant_id, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"role\":\"assistant\",\"content\":[],\"model\":{\"provider\":") catch return;
                    std.json.Stringify.value(self.provider_id, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"id\":") catch return;
                    std.json.Stringify.value(self.model_id, .{}, &out.writer) catch return;
                    out.writer.writeAll("},\"timestamp\":") catch return;
                    out.writer.print("{d}", .{self.timestamp}) catch return;
                    out.writer.writeAll(",\"status\":\"streaming\"}}") catch return;
                } else return,
                .message_update => if (std.mem.eql(u8, event.name, "assistant") and event.text.len > 0) {
                    out.writer.writeAll("{\"type\":\"assistant_delta\",\"messageId\":") catch return;
                    std.json.Stringify.value(self.assistant_id, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"contentIndex\":0,\"kind\":\"text\",\"delta\":") catch return;
                    std.json.Stringify.value(event.text, .{}, &out.writer) catch return;
                    out.writer.writeByte('}') catch return;
                } else return,
                .message_end => if (std.mem.eql(u8, event.name, "assistant")) {
                    out.writer.writeAll("{\"type\":\"item_finished\",\"item\":{\"id\":") catch return;
                    std.json.Stringify.value(self.assistant_id, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":") catch return;
                    std.json.Stringify.value(event.text, .{}, &out.writer) catch return;
                    out.writer.writeAll("}],\"model\":{\"provider\":") catch return;
                    std.json.Stringify.value(self.provider_id, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"id\":") catch return;
                    std.json.Stringify.value(self.model_id, .{}, &out.writer) catch return;
                    out.writer.writeAll("},\"timestamp\":") catch return;
                    out.writer.print("{d}", .{self.timestamp}) catch return;
                    out.writer.writeAll(",\"status\":\"complete\",\"stopReason\":\"stop\"}}") catch return;
                } else return,
                .tool_execution_start => {
                    out.writer.writeAll("{\"type\":\"item_started\",\"item\":{\"id\":") catch return;
                    const tid = std.fmt.allocPrint(self.server.gpa, "tool-{s}", .{event.id}) catch return;
                    defer self.server.gpa.free(tid);
                    std.json.Stringify.value(tid, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"role\":\"tool\",\"toolCallId\":") catch return;
                    std.json.Stringify.value(event.id, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"toolName\":") catch return;
                    std.json.Stringify.value(event.name, .{}, &out.writer) catch return;
                    out.writer.writeAll(",\"input\":") catch return;
                    if (event.args_json.len > 0) out.writer.writeAll(event.args_json) catch return else out.writer.writeAll("{}") catch return;
                    out.writer.writeAll(",\"content\":[],\"timestamp\":") catch return;
                    out.writer.print("{d}", .{self.timestamp}) catch return;
                    out.writer.writeAll(",\"status\":\"running\",\"isError\":false}}") catch return;
                },
                .user => {
                    self.server.broadcastSessionSnapshot(self.session_id) catch {};
                    return;
                },
                .tool_execution_update => writeToolProgress(
                    self.server.gpa,
                    &out.writer,
                    "item_updated",
                    event,
                    self.timestamp,
                    "running",
                    false,
                ) catch return,
                .tool_execution_end => writeToolProgress(
                    self.server.gpa,
                    &out.writer,
                    "item_finished",
                    event,
                    self.timestamp,
                    if (event.is_error) "error" else "complete",
                    event.is_error,
                ) catch return,
                else => return,
            }
            self.server.broadcastSessionProgress(self.session_id, out.written()) catch {};
        }
    };

    fn broadcastSessionProgress(self: *Server, session_id: []const u8, progress_json: []const u8) !void {
        self.peers_mutex.lockUncancelable(self.io);
        defer self.peers_mutex.unlock(self.io);
        for (self.peers.items) |peer| {
            self.sessions_mutex.lockUncancelable(self.io);
            const session = self.sessions.find(session_id);
            const attached = session != null and session.?.isAttachedTo(peer.connection_id);
            self.sessions_mutex.unlock(self.io);
            if (!attached) continue;
            var out: Io.Writer.Allocating = .init(self.gpa);
            defer out.deinit();
            try out.writer.writeAll("{\"type\":\"event\",\"event\":{\"type\":\"session_progress\",\"sessionId\":");
            try std.json.Stringify.value(session_id, .{}, &out.writer);
            try out.writer.writeAll(",\"progress\":");
            try out.writer.writeAll(progress_json);
            try out.writer.writeAll("}}");
            try self.writePeerJson(peer, out.written());
        }
    }

    fn persistSessionLocked(self: *Server, session: *const session_store.Session) !void {
        if (self.config.persistence) |backend| {
            try backend.saveSession(self.gpa, self.io, session);
        } else if (self.config.session_dir) |dir_path| {
            try session_store.saveSession(self.gpa, self.io, dir_path, session);
        }
    }

    fn executeRequestLocked(self: *Server, connection_id: []const u8, request: protocol.messages.RequestEnvelope) ![]u8 {
        switch (request.request) {
            .list => {
                var out: Io.Writer.Allocating = .init(self.gpa);
                errdefer out.deinit();
                try out.writer.print("{{\"type\":\"response\",\"id\":", .{});
                try std.json.Stringify.value(request.id, .{}, &out.writer);
                try out.writer.writeAll(",\"ok\":true,\"result\":{\"command\":\"list\",\"sessions\":[");
                for (self.sessions.sessions.items, 0..) |session, i| {
                    if (i > 0) try out.writer.writeByte(',');
                    try writeSessionMetadata(&out.writer, session);
                }
                try out.writer.writeAll("]}}");
                return try out.toOwnedSlice();
            },
            .create => |cmd| {
                const model = if (cmd.model) |ref|
                    session_store.findModel(self.config.model_catalog, ref.provider, ref.id) orelse return self.errorJson(request.id, "invalid_request", "Unknown model")
                else
                    self.config.model_catalog[0];
                const requested = if (cmd.thinking_level) |level| session_store.fromProtocolThinking(level) else thinking.ThinkingLevel.off;
                const session = self.sessions.create(self.gpa, self.io, connection_id, cmd.cwd orelse ".", cmd.name, model, requested) catch return self.errorJson(request.id, "internal_error", "Unable to create session");
                self.persistSessionLocked(session) catch return self.errorJson(request.id, "internal_error", "Unable to persist session");
                return self.sessionResultJson(request.id, "create", session, connection_id);
            },
            .attach => |cmd| {
                if (self.sessions.find(cmd.session_id) == null) return self.storeErrorJson(request.id, error.SessionNotFound);
                if (self.config.persistence) |backend| {
                    backend.claimSession(cmd.session_id) catch return self.errorJson(request.id, "session_locked", "Session is owned by another server");
                }
                const session = self.sessions.attach(self.gpa, connection_id, cmd.session_id) catch |err| return self.storeErrorJson(request.id, err);
                return self.sessionResultJson(request.id, "attach", session, connection_id);
            },
            .detach => |cmd| {
                self.sessions.detach(self.gpa, connection_id, cmd.session_id);
                if (self.sessions.find(cmd.session_id)) |session| {
                    if (!session.locked()) {
                        if (self.config.persistence) |backend| backend.releaseSession(session.id);
                    }
                }
                var out: Io.Writer.Allocating = .init(self.gpa);
                errdefer out.deinit();
                try out.writer.writeAll("{\"type\":\"response\",\"id\":");
                try std.json.Stringify.value(request.id, .{}, &out.writer);
                try out.writer.writeAll(",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":");
                try std.json.Stringify.value(cmd.session_id, .{}, &out.writer);
                try out.writer.writeAll("}}");
                return try out.toOwnedSlice();
            },
            .prompt => return self.errorJson(request.id, "internal_error", "Prompt dispatch invariant violated"),
            .set_model => |cmd| {
                const session = self.sessions.setModel(self.gpa, self.io, connection_id, cmd.session_id, cmd.model.provider, cmd.model.id, self.config.model_catalog) catch |err| return self.storeErrorJson(request.id, err);
                self.persistSessionLocked(session) catch return self.errorJson(request.id, "internal_error", "Unable to persist session");
                return self.sessionResultJson(request.id, "set_model", session, connection_id);
            },
            .set_thinking => |cmd| {
                const session = self.sessions.setThinking(self.io, connection_id, cmd.session_id, session_store.fromProtocolThinking(cmd.thinking_level), self.config.model_catalog) catch |err| return self.storeErrorJson(request.id, err);
                self.persistSessionLocked(session) catch return self.errorJson(request.id, "internal_error", "Unable to persist session");
                return self.sessionResultJson(request.id, "set_thinking", session, connection_id);
            },
            .steer => |cmd| {
                const session = self.sessions.steer(self.gpa, self.io, connection_id, cmd.session_id, cmd.text) catch |err| return self.storeErrorJson(request.id, err);
                return self.sessionResultJson(request.id, "steer", session, connection_id);
            },
            .abort => |cmd| {
                const session = self.sessions.abort(connection_id, cmd.session_id) catch |err| return self.storeErrorJson(request.id, err);
                return self.sessionResultJson(request.id, "abort", session, connection_id);
            },
        }
    }

    fn makeHelloJson(self: *Server, connection_id: []const u8) ![]u8 {
        self.sessions_mutex.lockUncancelable(self.io);
        defer self.sessions_mutex.unlock(self.io);
        var out: Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeAll("{\"type\":\"hello\",\"version\":1,\"connectionId\":");
        try std.json.Stringify.value(connection_id, .{}, &out.writer);
        try out.writer.writeAll(",\"snapshot\":");
        try self.writeServerSnapshotLocked(&out.writer);
        try out.writer.writeByte('}');
        return try out.toOwnedSlice();
    }

    fn writeServerSnapshotLocked(self: *Server, writer: *Io.Writer) !void {
        try writer.print("{{\"serverId\":\"pi-zig\",\"protocolVersion\":1,\"revision\":{d},\"sessions\":[", .{self.sessions.server_revision});
        for (self.sessions.sessions.items, 0..) |session, i| {
            if (i > 0) try writer.writeByte(',');
            try writeSessionMetadata(writer, session);
        }
        try writer.writeAll("],\"models\":[");
        var emitted_models: usize = 0;
        for (self.config.model_catalog) |model| {
            // Protocol ModelMetadata requires concrete limits. Do not fabricate
            // values for legacy curated entries that have not yet been imported
            // from the authoritative upstream catalog.
            if (model.context_window == 0 or model.max_tokens == 0) continue;
            if (emitted_models > 0) try writer.writeByte(',');
            emitted_models += 1;
            try self.writeModelMetadata(writer, model);
        }
        try writer.writeAll("]}");
    }

    fn writeModelMetadata(self: *Server, writer: *Io.Writer, model: providers.ModelInfo) !void {
        try writer.writeAll("{\"provider\":");
        try std.json.Stringify.value(model.providerName(), .{}, writer);
        try writer.writeAll(",\"id\":");
        try std.json.Stringify.value(model.id, .{}, writer);
        try writer.writeAll(",\"name\":");
        try std.json.Stringify.value(model.display, .{}, writer);
        try writer.writeAll(",\"api\":");
        try std.json.Stringify.value(modelApiName(model), .{}, writer);
        try writer.print(",\"reasoning\":{s},\"input\":[", .{if (model.reasoning) "true" else "false"});
        var input_count: usize = 0;
        if (model.input_text) {
            try writer.writeAll("\"text\"");
            input_count += 1;
        }
        if (model.input_image) {
            if (input_count > 0) try writer.writeByte(',');
            try writer.writeAll("\"image\"");
        }
        try writer.print("],\"contextWindow\":{d},\"maxTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}}},\"supportedThinkingLevels\":[", .{
            model.context_window,
            model.max_tokens,
            model.cost.input,
            model.cost.output,
            model.cost.cache_read,
            model.cost.cache_write,
        });
        var levels_buf: [7]thinking.ThinkingLevel = undefined;
        const levels = model.supportedThinkingLevels(&levels_buf);
        for (levels, 0..) |level, i| {
            if (i > 0) try writer.writeByte(',');
            try std.json.Stringify.value(@tagName(level), .{}, writer);
        }
        try writer.print("],\"authenticated\":{s}}}", .{if (self.modelAuthenticated(model)) "true" else "false"});
    }

    fn modelAuthenticated(self: *const Server, model: providers.ModelInfo) bool {
        switch (model.provider) {
            .mock, .ollama, .lmstudio, .vllm => return true,
            else => {},
        }
        if (self.config.models_file) |models_file| {
            if (models_file.findProvider(model.providerName())) |configured_provider| {
                if (configured_provider.api_key != null) return true;
            }
        }
        const environ = self.config.environ orelse return false;
        return providers.hasUsableCredential(model.provider, null, environ);
    }

    fn sessionResultJson(self: *Server, request_id: []const u8, command: []const u8, session: *session_store.Session, connection_id: []const u8) ![]u8 {
        var out: Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeAll("{\"type\":\"response\",\"id\":");
        try std.json.Stringify.value(request_id, .{}, &out.writer);
        try out.writer.writeAll(",\"ok\":true,\"result\":{\"command\":");
        try std.json.Stringify.value(command, .{}, &out.writer);
        try out.writer.writeAll(",\"session\":");
        try writeSessionSnapshot(&out.writer, session, connection_id);
        try out.writer.writeAll("}}");
        return try out.toOwnedSlice();
    }

    fn storeErrorJson(self: *Server, request_id: []const u8, err: anyerror) ![]u8 {
        return switch (err) {
            session_store.Error.SessionNotFound => self.errorJson(request_id, "not_found", "Session not found"),
            session_store.Error.NotAttached => self.errorJson(request_id, "invalid_request", "Connection is not attached to the session"),
            session_store.Error.UnknownModel => self.errorJson(request_id, "invalid_request", "Unknown model"),
            session_store.Error.Busy => self.errorJson(request_id, "busy", "Session is busy"),
            else => self.errorJson(request_id, "internal_error", "Session operation failed"),
        };
    }

    fn errorJson(self: *Server, request_id: []const u8, code: []const u8, message: []const u8) ![]u8 {
        var out: Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeAll("{\"type\":\"response\",\"id\":");
        try std.json.Stringify.value(request_id, .{}, &out.writer);
        try out.writer.writeAll(",\"ok\":false,\"error\":{\"code\":");
        try std.json.Stringify.value(code, .{}, &out.writer);
        try out.writer.writeAll(",\"message\":");
        try std.json.Stringify.value(message, .{}, &out.writer);
        try out.writer.writeAll("}}");
        return try out.toOwnedSlice();
    }
};

/// Server bind addresses are deliberately numeric: accepting DNS names here
/// could bind an arbitrary first answer and vary by resolver ordering. Both
/// ordinary and bracketed IPv6 spellings are accepted for CLI ergonomics.
pub fn parseBindAddress(host_raw: []const u8, port: u16) !net.IpAddress {
    if (host_raw.len == 0 or port == 0) return error.InvalidBindAddress;
    const host = if (host_raw.len >= 2 and host_raw[0] == '[' and host_raw[host_raw.len - 1] == ']')
        host_raw[1 .. host_raw.len - 1]
    else
        host_raw;
    return net.IpAddress.parse(host, port) catch error.InvalidBindAddress;
}

fn modelApiName(model: providers.ModelInfo) []const u8 {
    if (model.provider == .mock) return "mock";
    return model.apiKind().name();
}

fn requestChangesServerSnapshot(request: protocol.messages.Command) bool {
    return switch (request) {
        .create, .attach, .detach => true,
        else => false,
    };
}

fn writeSessionMetadata(writer: *Io.Writer, session: *const session_store.Session) !void {
    try writer.writeAll("{\"id\":");
    try std.json.Stringify.value(session.id, .{}, writer);
    try writer.print(",\"createdAt\":{d},\"updatedAt\":{d}", .{ session.created_at, session.updated_at });
    if (session.name) |name| {
        try writer.writeAll(",\"sessionName\":");
        try std.json.Stringify.value(name, .{}, writer);
    }
    try writer.writeAll(",\"cwd\":");
    try std.json.Stringify.value(session.cwd, .{}, writer);
    try writer.writeAll("}");
}

fn writeSessionSnapshot(writer: *Io.Writer, session: *const session_store.Session, connection_id: []const u8) !void {
    try writer.writeAll("{\"id\":");
    try std.json.Stringify.value(session.id, .{}, writer);
    if (session.name) |name| {
        try writer.writeAll(",\"name\":");
        try std.json.Stringify.value(name, .{}, writer);
    }
    try writer.writeAll(",\"cwd\":");
    try std.json.Stringify.value(session.cwd, .{}, writer);
    try writer.print(",\"createdAt\":{d},\"updatedAt\":{d},\"phase\":", .{ session.created_at, session.updated_at });
    try std.json.Stringify.value(@tagName(session.phase), .{}, writer);
    try writer.writeAll(",\"model\":{\"provider\":");
    try std.json.Stringify.value(session.model_provider, .{}, writer);
    try writer.writeAll(",\"id\":");
    try std.json.Stringify.value(session.model_id, .{}, writer);
    try writer.writeAll("},\"thinkingLevel\":");
    try std.json.Stringify.value(@tagName(session.thinking_level), .{}, writer);
    try writer.print(",\"attached\":{s},\"locked\":{s},\"revision\":{d},\"transcript\":[", .{
        if (session.isAttachedTo(connection_id)) "true" else "false",
        if (session.locked()) "true" else "false",
        session.revision,
    });

    const branch = try session.native.branchEntries(std.heap.page_allocator);
    defer std.heap.page_allocator.free(branch);
    var emitted: usize = 0;
    for (branch, 0..) |entry, index| {
        if (!isProtocolTranscriptRole(entry.role)) continue;
        if (emitted > 0) try writer.writeByte(',');
        emitted += 1;
        const timestamp = session.created_at + @as(u64, @intCast(index + 1));
        try writeNativeTranscriptItem(writer, session, entry, timestamp);
    }

    // Backward compatibility for durable sessions created by the earlier
    // user-only server implementation before native JSONL history existed.
    if (emitted == 0) {
        for (session.transcript.items, 0..) |entry, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"id\":");
            try std.json.Stringify.value(entry.id, .{}, writer);
            try writer.writeAll(",\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(entry.text, .{}, writer);
            try writer.print("}}],\"timestamp\":{d}}}", .{entry.timestamp});
        }
    }
    try writer.writeAll("],\"queuedSteer\":[");
    for (session.queued_steer.items, 0..) |entry, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll("{\"id\":");
        try std.json.Stringify.value(entry.id, .{}, writer);
        try writer.writeAll(",\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(entry.text, .{}, writer);
        try writer.print("}}],\"timestamp\":{d}}}", .{entry.timestamp});
    }
    try writer.print("],\"queuedSteerCount\":{d}}}", .{session.queued_steer.items.len});
}

fn isProtocolTranscriptRole(role: []const u8) bool {
    return std.mem.eql(u8, role, "user") or std.mem.eql(u8, role, "assistant") or std.mem.eql(u8, role, "tool");
}

fn writeNativeTranscriptItem(writer: *Io.Writer, session: *const session_store.Session, entry: *const agent.session.SessionEntry, timestamp: u64) !void {
    if (std.mem.eql(u8, entry.role, "user")) {
        try writer.writeAll("{\"id\":");
        try std.json.Stringify.value(entry.id, .{}, writer);
        try writer.writeAll(",\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(entry.content, .{}, writer);
        try writer.print("}}],\"timestamp\":{d}}}", .{timestamp});
        return;
    }

    if (std.mem.eql(u8, entry.role, "assistant")) {
        try writer.writeAll("{\"id\":");
        try std.json.Stringify.value(entry.id, .{}, writer);
        try writer.writeAll(",\"role\":\"assistant\",\"content\":[");
        var first = true;
        if (entry.meta.thinking.len > 0) {
            try writer.writeAll("{\"type\":\"thinking\",\"thinking\":");
            try std.json.Stringify.value(entry.meta.thinking, .{}, writer);
            try writer.writeAll("}");
            first = false;
        }
        if (entry.content.len > 0) {
            try writer.writeAll("{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(entry.content, .{}, writer);
            try writer.writeAll("}");
            first = false;
        }
        if (entry.tool_calls_json) |tool_calls| {
            var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, tool_calls, .{}) catch null;
            defer if (parsed) |*v| v.deinit();
            if (parsed) |v| {
                if (v.value == .array) {
                    for (v.value.array.items) |call| {
                        if (call != .object) continue;
                        const id_v = call.object.get("id") orelse continue;
                        const fn_v = call.object.get("function") orelse continue;
                        if (id_v != .string or fn_v != .object) continue;
                        const name_v = fn_v.object.get("name") orelse continue;
                        if (name_v != .string) continue;
                        if (!first) try writer.writeByte(',');
                        first = false;
                        try writer.writeAll("{\"type\":\"toolCall\",\"toolCallId\":");
                        try std.json.Stringify.value(id_v.string, .{}, writer);
                        try writer.writeAll(",\"toolName\":");
                        try std.json.Stringify.value(name_v.string, .{}, writer);
                        try writer.writeAll(",\"input\":");
                        try writeToolArguments(writer, fn_v.object.get("arguments"));
                        try writer.writeAll("}");
                    }
                }
            }
        }
        try writer.writeAll("],\"model\":{\"provider\":");
        // The protocol exposes the selected public provider identity, not the
        // transport implementation used underneath (e.g. a corporate proxy).
        try std.json.Stringify.value(session.model_provider, .{}, writer);
        try writer.writeAll(",\"id\":");
        try std.json.Stringify.value(session.model_id, .{}, writer);
        try writer.writeAll("}");
        if (entry.meta.response_model.len > 0) {
            try writer.writeAll(",\"responseModel\":");
            try std.json.Stringify.value(entry.meta.response_model, .{}, writer);
        } else if (entry.meta.model.len > 0 and !std.mem.eql(u8, entry.meta.model, session.model_id)) {
            try writer.writeAll(",\"responseModel\":");
            try std.json.Stringify.value(entry.meta.model, .{}, writer);
        }
        if (entry.meta.response_id.len > 0) {
            try writer.writeAll(",\"responseId\":");
            try std.json.Stringify.value(entry.meta.response_id, .{}, writer);
        }
        if (entry.meta.diagnostics_json.len > 0) {
            try writer.writeAll(",\"diagnostics\":");
            try writer.writeAll(entry.meta.diagnostics_json);
        }
        if (entry.meta.error_message.len > 0) {
            try writer.writeAll(",\"errorMessage\":");
            try std.json.Stringify.value(entry.meta.error_message, .{}, writer);
        }
        if (entry.meta.raw_stop_reason.len > 0) {
            try writer.writeAll(",\"rawStopReason\":");
            try std.json.Stringify.value(entry.meta.raw_stop_reason, .{}, writer);
        }
        if (entry.meta.usage_input > 0 or entry.meta.usage_output > 0 or entry.meta.usage_cache_read > 0 or entry.meta.usage_cache_write > 0 or entry.meta.usage_total > 0) {
            try writer.print(",\"usage\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}", .{
                entry.meta.usage_input,
                entry.meta.usage_output,
                entry.meta.usage_cache_read,
                entry.meta.usage_cache_write,
            });
            if (entry.meta.usage_cache_write_1h) |v| try writer.print(",\"cacheWrite1h\":{d}", .{v});
            if (entry.meta.usage_reasoning) |v| try writer.print(",\"reasoning\":{d}", .{v});
            try writer.print(",\"totalTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}}}}", .{
                entry.meta.usage_total,
                entry.meta.cost_input,
                entry.meta.cost_output,
                entry.meta.cost_cache_read,
                entry.meta.cost_cache_write,
                entry.meta.cost_total,
            });
        }
        try writer.print(",\"timestamp\":{d},\"status\":", .{timestamp});
        const stop = if (entry.meta.stop_reason.len > 0) entry.meta.stop_reason else if (entry.tool_calls_json != null) "toolUse" else "stop";
        if (std.mem.eql(u8, stop, "error")) {
            try writer.writeAll("\"error\",\"stopReason\":\"error\"");
        } else if (std.mem.eql(u8, stop, "aborted")) {
            try writer.writeAll("\"aborted\",\"stopReason\":\"aborted\"");
        } else {
            try writer.writeAll("\"complete\",\"stopReason\":");
            if (std.mem.eql(u8, stop, "toolUse") or entry.tool_calls_json != null) {
                try writer.writeAll("\"toolUse\"");
            } else if (std.mem.eql(u8, stop, "length")) {
                try writer.writeAll("\"length\"");
            } else {
                try writer.writeAll("\"stop\"");
            }
        }
        try writer.writeAll("}");
        return;
    }

    // Tool result.
    try writer.writeAll("{\"id\":");
    try std.json.Stringify.value(entry.id, .{}, writer);
    try writer.writeAll(",\"role\":\"tool\",\"toolCallId\":");
    try std.json.Stringify.value(entry.tool_call_id orelse "", .{}, writer);
    try writer.writeAll(",\"toolName\":");
    try std.json.Stringify.value(entry.tool_name orelse "tool", .{}, writer);
    try writer.writeAll(",\"input\":");
    try writeToolInputForCall(writer, &session.native, entry.tool_call_id orelse "");
    try writer.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
    try std.json.Stringify.value(entry.content, .{}, writer);
    try writer.print("}}],\"timestamp\":{d},\"status\":", .{timestamp});
    try writer.writeAll(if (entry.tool_is_error) "\"error\"" else "\"complete\"");
    try writer.writeAll(",\"isError\":");
    try writer.writeAll(if (entry.tool_is_error) "true" else "false");
    try writer.writeAll("}");
}

fn writeToolArguments(writer: *Io.Writer, args: ?std.json.Value) !void {
    const value = args orelse {
        try writer.writeAll("{}");
        return;
    };
    if (value == .string) {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, value.string, .{}) catch {
            try writer.writeAll("{}");
            return;
        };
        defer parsed.deinit();
        try std.json.Stringify.value(parsed.value, .{}, writer);
    } else {
        try std.json.Stringify.value(value, .{}, writer);
    }
}

fn writeToolInputForCall(writer: *Io.Writer, native: *const agent.session.Session, call_id: []const u8) !void {
    for (native.entries.items) |entry| {
        const raw = entry.tool_calls_json orelse continue;
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, raw, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .array) continue;
        for (parsed.value.array.items) |call| {
            if (call != .object) continue;
            const id_v = call.object.get("id") orelse continue;
            if (id_v != .string or !std.mem.eql(u8, id_v.string, call_id)) continue;
            const fn_v = call.object.get("function") orelse continue;
            if (fn_v != .object) continue;
            return writeToolArguments(writer, fn_v.object.get("arguments"));
        }
    }
    try writer.writeAll("{}");
}

fn decodeLength(h: []const u8) usize {
    return (@as(usize, h[0]) << 24) | (@as(usize, h[1]) << 16) | (@as(usize, h[2]) << 8) | @as(usize, h[3]);
}

fn makeConnectionId(gpa: std.mem.Allocator, io: Io) ![]u8 {
    var raw: [8]u8 = undefined;
    try std.Io.randomSecure(io, &raw);
    return try std.fmt.allocPrint(gpa, "conn-{x}", .{std.mem.readInt(u64, &raw, .big)});
}

fn firstLine(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, '\n') orelse raw.len;
    return std.mem.trimEnd(u8, raw[0..end], "\r");
}

const HttpHeaderBoundary = struct {
    head_end: usize,
    body_offset: usize,
};

const HttpHead = struct {
    body_offset: usize,
    content_length: usize,
};

fn httpHeaderBoundary(raw: []const u8) ?HttpHeaderBoundary {
    if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |index| {
        return .{ .head_end = index, .body_offset = index + 4 };
    }
    if (std.mem.indexOf(u8, raw, "\n\n")) |index| {
        return .{ .head_end = index, .body_offset = index + 2 };
    }
    return null;
}

/// Parse only the HTTP request head. Ambiguous framing is rejected: duplicate
/// Content-Length, transfer codings, obsolete line folding, and malformed
/// numeric lengths cannot reach the RPC parser.
fn parseHttpHead(raw: []const u8) !HttpHead {
    const boundary = httpHeaderBoundary(raw) orelse return error.IncompleteHeaders;
    const head = raw[0..boundary.head_end];
    var lines = std.mem.splitScalar(u8, head, '\n');
    const request_line = std.mem.trimEnd(u8, lines.next() orelse return error.MissingRequestLine, "\r");
    var request_parts = std.mem.tokenizeScalar(u8, request_line, ' ');
    const method = request_parts.next() orelse return error.InvalidRequestLine;
    const target = request_parts.next() orelse return error.InvalidRequestLine;
    const version = request_parts.next() orelse return error.InvalidRequestLine;
    if (request_parts.next() != null or method.len == 0 or target.len == 0 or
        !std.mem.startsWith(u8, version, "HTTP/1.")) return error.InvalidRequestLine;

    var content_length: ?usize = null;
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) continue;
        if (line[0] == ' ' or line[0] == '\t') return error.ObsoleteLineFolding;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidHeader;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (name.len == 0) return error.InvalidHeader;
        if (std.ascii.eqlIgnoreCase(name, "Transfer-Encoding")) return error.UnsupportedTransferEncoding;
        if (!std.ascii.eqlIgnoreCase(name, "Content-Length")) continue;
        if (content_length != null or value.len == 0) return error.AmbiguousContentLength;
        for (value) |c| if (!std.ascii.isDigit(c)) return error.InvalidContentLength;
        content_length = std.fmt.parseInt(usize, value, 10) catch return error.InvalidContentLength;
    }
    return .{ .body_offset = boundary.body_offset, .content_length = content_length orelse 0 };
}

/// Validate one unambiguous HTTP Authorization header. Tokens found in the
/// request target, unrelated headers, or body are never accepted. Duplicate
/// Authorization fields are rejected to avoid intermediary disagreement.
fn httpAuthorized(raw: []const u8, expected_token: []const u8) bool {
    if (expected_token.len == 0) return true;
    const header_end = if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |i|
        i
    else if (std.mem.indexOf(u8, raw, "\n\n")) |i|
        i
    else
        raw.len;
    const headers = raw[0..header_end];
    var lines = std.mem.splitScalar(u8, headers, '\n');
    _ = lines.next(); // request line
    var found = false;
    var valid = false;
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) break;
        if (line[0] == ' ' or line[0] == '\t') return false;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        if (!std.ascii.eqlIgnoreCase(name, "Authorization")) continue;
        if (found) return false;
        found = true;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        var scheme_end: usize = 0;
        while (scheme_end < value.len and value[scheme_end] != ' ' and value[scheme_end] != '\t') : (scheme_end += 1) {}
        if (!std.ascii.eqlIgnoreCase(value[0..scheme_end], "Bearer")) return false;
        var token_start = scheme_end;
        while (token_start < value.len and (value[token_start] == ' ' or value[token_start] == '\t')) : (token_start += 1) {}
        if (token_start == scheme_end or token_start == value.len) return false;
        const supplied = std.mem.trimEnd(u8, value[token_start..], " \t");
        valid = secureTokenEql(supplied, expected_token);
    }
    return found and valid;
}

fn secureTokenEql(supplied: []const u8, expected: []const u8) bool {
    var supplied_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var expected_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(supplied, &supplied_digest, .{});
    std.crypto.hash.sha2.Sha256.hash(expected, &expected_digest, .{});
    return std.crypto.timing_safe.eql([std.crypto.hash.sha2.Sha256.digest_length]u8, supplied_digest, expected_digest);
}

fn writeToolProgress(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    progress_type: []const u8,
    event: agent.AgentEvent,
    timestamp: u64,
    status: []const u8,
    is_error: bool,
) !void {
    try writer.writeAll("{\"type\":");
    try std.json.Stringify.value(progress_type, .{}, writer);
    try writer.writeAll(",\"item\":{\"id\":");
    const tool_id = try std.fmt.allocPrint(gpa, "tool-{s}", .{event.id});
    defer gpa.free(tool_id);
    try std.json.Stringify.value(tool_id, .{}, writer);
    try writer.writeAll(",\"role\":\"tool\",\"toolCallId\":");
    try std.json.Stringify.value(event.id, .{}, writer);
    try writer.writeAll(",\"toolName\":");
    try std.json.Stringify.value(event.name, .{}, writer);
    try writer.writeAll(",\"input\":");
    if (event.args_json.len > 0)
        try writer.writeAll(event.args_json)
    else
        try writer.writeAll("{}");
    try writer.writeAll(",\"content\":[");
    var wrote = false;
    if (event.text.len > 0 or (event.image_b64 == null and event.images.len == 0)) {
        try writer.writeAll("{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(event.text, .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    if (event.image_b64) |image| {
        if (wrote) try writer.writeByte(',');
        try writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(event.image_mime orelse "image/png", .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    for (event.images) |image| {
        if (wrote) try writer.writeByte(',');
        try writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(image.mime_type, .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    try writer.writeByte(']');
    if (event.details_json) |details| {
        try writer.writeAll(",\"details\":");
        try writer.writeAll(details);
    }
    if (event.usage) |usage| {
        try writer.writeAll(",\"usage\":");
        try writeProtocolUsage(writer, usage);
    }
    try writer.writeAll(",\"timestamp\":");
    try writer.print("{d}", .{timestamp});
    try writer.writeAll(",\"status\":");
    try std.json.Stringify.value(status, .{}, writer);
    try writer.writeAll(",\"isError\":");
    try writer.writeAll(if (is_error) "true" else "false");
    try writer.writeAll("}}");
}

fn writeProtocolUsage(writer: *std.Io.Writer, usage: anytype) !void {
    try writer.print("{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}", .{
        usage.input,
        usage.output,
        usage.cache_read,
        usage.cache_write,
    });
    if (usage.reasoning) |tokens| try writer.print(",\"reasoning\":{d}", .{tokens});
    try writer.print(",\"totalTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}}}}", .{
        usage.total(),
        usage.cost.input,
        usage.cost.output,
        usage.cost.cache_read,
        usage.cost.cache_write,
        usage.cost.total,
    });
}

/// Return currently available stream bytes without waiting to fill the
/// destination. `Reader.readSliceShort` has fill-or-EOF semantics in Zig 0.16
/// and therefore deadlocks ordinary keep-alive HTTP clients when used here.
fn readAvailable(reader: *Io.Reader, buffer: []u8) !usize {
    if (buffer.len == 0) return 0;
    const available = reader.peekGreedy(1) catch |err| switch (err) {
        error.EndOfStream => return 0,
        else => return err,
    };
    const count = @min(buffer.len, available.len);
    @memcpy(buffer[0..count], available[0..count]);
    reader.toss(count);
    return count;
}

fn writeHttp(io: Io, stream: *net.Stream, status: u16, body: []const u8) !void {
    var wbuf: [1024]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Content Too Large",
        else => "Error",
    };
    try writer.interface.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n",
        .{ status, status_text, body.len },
    );
    if (status == 401) try writer.interface.writeAll("WWW-Authenticate: Bearer\r\n");
    try writer.interface.writeAll("Connection: close\r\n\r\n");
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}

test "HTTP bearer authentication is header scoped and unambiguous" {
    const token = "secret-token-42";
    try std.testing.expect(httpAuthorized(
        "POST /rpc HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer secret-token-42\r\nContent-Length: 2\r\n\r\n{}",
        token,
    ));
    try std.testing.expect(httpAuthorized(
        "GET /health HTTP/1.1\nAUTHORIZATION:\tbeArEr   secret-token-42  \n\n",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc?token=secret-token-42 HTTP/1.1\r\nHost: localhost\r\n\r\n{}",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc HTTP/1.1\r\nHost: secret-token-42\r\n\r\n{\"token\":\"secret-token-42\"}",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc HTTP/1.1\r\nAuthorization: Basic secret-token-42\r\n\r\n",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc HTTP/1.1\r\nAuthorization: Bearer wrong\r\nAuthorization: Bearer secret-token-42\r\n\r\n",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc HTTP/1.1\r\nAuthorization: Bearer secret-token-42\r\nAuthorization: Bearer secret-token-42\r\n\r\n",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc HTTP/1.1\r\nAuthorization: Bearer secret-token-42\r\n injected-continuation\r\n\r\n",
        token,
    ));
    try std.testing.expect(!httpAuthorized(
        "POST /rpc HTTP/1.1\r\nAuthorization: Bearer secret-token-42 extra\r\n\r\n",
        token,
    ));
    try std.testing.expect(httpAuthorized("raw bytes without headers", ""));
}

test "server bind parser accepts IPv4 and IPv6 literals only" {
    const ip4 = try parseBindAddress("127.0.0.1", 3141);
    try std.testing.expect(ip4 == .ip4);
    try std.testing.expectEqual(@as(u16, 3141), ip4.getPort());
    const ip6 = try parseBindAddress("::1", 3142);
    try std.testing.expect(ip6 == .ip6);
    try std.testing.expectEqual(@as(u16, 3142), ip6.getPort());
    const bracketed = try parseBindAddress("[::1]", 3143);
    try std.testing.expect(bracketed == .ip6);
    try std.testing.expectError(error.InvalidBindAddress, parseBindAddress("localhost", 3141));
    try std.testing.expectError(error.InvalidBindAddress, parseBindAddress("127.0.0.1", 0));
}

test "HTTP head parser enforces complete unambiguous body framing" {
    const head = try parseHttpHead("POST /rpc HTTP/1.1\r\nHost: localhost\r\nContent-Length: 12\r\n\r\nhello world!");
    try std.testing.expectEqual(@as(usize, 12), head.content_length);
    try std.testing.expectEqualStrings("hello world!", "POST /rpc HTTP/1.1\r\nHost: localhost\r\nContent-Length: 12\r\n\r\nhello world!"[head.body_offset..]);
    try std.testing.expectError(error.IncompleteHeaders, parseHttpHead("POST /rpc HTTP/1.1\r\nHost: localhost\r\n"));
    try std.testing.expectError(error.AmbiguousContentLength, parseHttpHead(
        "POST /rpc HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\nx",
    ));
    try std.testing.expectError(error.UnsupportedTransferEncoding, parseHttpHead(
        "POST /rpc HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
    ));
    try std.testing.expectError(error.ObsoleteLineFolding, parseHttpHead(
        "POST /rpc HTTP/1.1\r\nX-Test: one\r\n two\r\n\r\n",
    ));
}

test "secure token comparison checks content" {
    try std.testing.expect(secureTokenEql("same", "same"));
    try std.testing.expect(!secureTokenEql("same", "different"));
    try std.testing.expect(!secureTokenEql("same", "same "));
}

test "server protocol hello" {
    const gpa = std.testing.allocator;
    var s = Server{ .gpa = gpa, .io = std.testing.io, .config = .{} };
    defer s.deinit();
    const out = try s.handleRpcBody("{\"type\":\"hello\",\"version\":1}\n");
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"type\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "protocolVersion") != null);
}

test "server create list detach attachment state" {
    const gpa = std.testing.allocator;
    var s = Server{ .gpa = gpa, .io = std.testing.io, .config = .{} };
    defer s.deinit();
    const created = try s.handleRpcBodyForConnection("c1", "{\"type\":\"request\",\"id\":\"1\",\"request\":{\"command\":\"create\",\"cwd\":\"/tmp\"}}\n");
    defer gpa.free(created);
    try std.testing.expect(std.mem.indexOf(u8, created, "\"command\":\"create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, created, "\"attached\":true") != null);
    const listed = try s.handleRpcBodyForConnection("c2", "{\"type\":\"request\",\"id\":\"2\",\"request\":{\"command\":\"list\"}}\n");
    defer gpa.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "\"createdAt\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed, "\"cwd\":\"/tmp\"") != null);
    // Protocol-v1 list results are durable SessionMetadata, not connection-
    // relative live SessionSnapshot state.
    try std.testing.expect(std.mem.indexOf(u8, listed, "\"attached\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed, "\"locked\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed, "\"phase\":") == null);
    _ = s.sessions.disconnect(gpa, "c1");
    const listed2 = try s.handleRpcBodyForConnection("c2", "{\"type\":\"request\",\"id\":\"3\",\"request\":{\"command\":\"list\"}}\n");
    defer gpa.free(listed2);
    try std.testing.expect(std.mem.indexOf(u8, listed2, "\"attached\":") == null);
}

const TestPersistenceBackend = struct {
    load_calls: usize = 0,
    save_calls: usize = 0,
    claim_calls: usize = 0,
    release_calls: usize = 0,
    fail_claim: bool = false,
    saved_revision: u64 = 0,

    fn backend(self: *TestPersistenceBackend) session_store.PersistenceBackend {
        return .{
            .context = self,
            .load_all_fn = loadAll,
            .save_session_fn = saveSession,
            .claim_session_fn = claimSession,
            .release_session_fn = releaseSession,
        };
    }

    fn loadAll(context: *anyopaque, store: *session_store.SessionStore, gpa: std.mem.Allocator, io: Io) !usize {
        const self: *TestPersistenceBackend = @ptrCast(@alignCast(context));
        _ = store;
        _ = gpa;
        _ = io;
        self.load_calls += 1;
        return 0;
    }

    fn saveSession(context: *anyopaque, gpa: std.mem.Allocator, io: Io, session: *const session_store.Session) !void {
        const self: *TestPersistenceBackend = @ptrCast(@alignCast(context));
        _ = gpa;
        _ = io;
        self.save_calls += 1;
        self.saved_revision = session.revision;
    }

    fn claimSession(context: *anyopaque, session_id: []const u8) !void {
        const self: *TestPersistenceBackend = @ptrCast(@alignCast(context));
        _ = session_id;
        self.claim_calls += 1;
        if (self.fail_claim) return error.TestLeaseHeld;
    }

    fn releaseSession(context: *anyopaque, session_id: []const u8) void {
        const self: *TestPersistenceBackend = @ptrCast(@alignCast(context));
        _ = session_id;
        self.release_calls += 1;
    }
};

test "server production persistence loads saves fences and releases" {
    const gpa = std.testing.allocator;
    var persistence = TestPersistenceBackend{};
    var server = Server{
        .gpa = gpa,
        .io = std.testing.io,
        .config = .{ .persistence = persistence.backend() },
    };
    defer server.deinit();
    try server.start();
    try std.testing.expectEqual(@as(usize, 1), persistence.load_calls);

    const created = try server.handleRpcBodyForConnection("owner", "{\"type\":\"request\",\"id\":\"create\",\"request\":{\"command\":\"create\",\"cwd\":\"/durable\"}}\n");
    defer gpa.free(created);
    try std.testing.expectEqual(@as(usize, 1), persistence.save_calls);
    const session = server.sessions.sessions.items[0];
    const session_id = try gpa.dupe(u8, session.id);
    defer gpa.free(session_id);

    const detached_request = try std.fmt.allocPrint(gpa, "{{\"type\":\"request\",\"id\":\"detach\",\"request\":{{\"command\":\"detach\",\"sessionId\":\"{s}\"}}}}\n", .{session_id});
    defer gpa.free(detached_request);
    const detached = try server.handleRpcBodyForConnection("owner", detached_request);
    defer gpa.free(detached);
    try std.testing.expectEqual(@as(usize, 1), persistence.release_calls);
    try std.testing.expect(!session.locked());

    persistence.fail_claim = true;
    const attach_request = try std.fmt.allocPrint(gpa, "{{\"type\":\"request\",\"id\":\"attach\",\"request\":{{\"command\":\"attach\",\"sessionId\":\"{s}\"}}}}\n", .{session_id});
    defer gpa.free(attach_request);
    const rejected = try server.handleRpcBodyForConnection("contender", attach_request);
    defer gpa.free(rejected);
    try std.testing.expect(std.mem.indexOf(u8, rejected, "session_locked") != null);
    try std.testing.expect(!session.isAttachedTo("contender"));
    try std.testing.expectEqual(@as(usize, 1), persistence.claim_calls);
}

test "server rejects simultaneous JSON and custom persistence backends" {
    var persistence = TestPersistenceBackend{};
    var server = Server{
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .config = .{ .session_dir = "/tmp/json", .persistence = persistence.backend() },
    };
    defer server.deinit();
    try std.testing.expectError(error.ConflictingSessionPersistence, server.start());
}

test "server tool progress preserves partial details and images" {
    const gpa = std.testing.allocator;
    var progress: Io.Writer.Allocating = .init(gpa);
    defer progress.deinit();
    try writeToolProgress(gpa, &progress.writer, "item_updated", .{
        .kind = .tool_execution_update,
        .id = "call-rich",
        .name = "vision_tool",
        .args_json = "{\"value\":1}",
        .text = "partial",
        .details_json = "{\"phase\":2}",
        .image_b64 = "AQID",
        .image_mime = "image/png",
        .images = &.{.{ .data_b64 = @constCast("BAUG"), .mime_type = @constCast("image/jpeg") }},
        .usage = .{
            .input = 7,
            .output = 5,
            .cache_read = 3,
            .cache_write = 2,
            .reasoning = 1,
            .total_tokens = 17,
            .cost = .{ .input = 0.01, .output = 0.02, .cache_read = 0.03, .cache_write = 0.04, .total = 0.1 },
        },
        .is_partial = true,
    }, 42, "running", false);

    var envelope: Io.Writer.Allocating = .init(gpa);
    defer envelope.deinit();
    try envelope.writer.writeAll("{\"type\":\"event\",\"event\":{\"type\":\"session_progress\",\"sessionId\":\"session-rich\",\"progress\":");
    try envelope.writer.writeAll(progress.written());
    try envelope.writer.writeAll("}}");
    var parsed = try protocol.server_json.parseServerMessage(gpa, envelope.written());
    defer parsed.deinit();
    const item = parsed.message.event.session_progress.progress.item_updated.tool;
    try std.testing.expectEqualStrings("call-rich", item.tool_call_id);
    try std.testing.expectEqualStrings("vision_tool", item.tool_name);
    try std.testing.expectEqual(protocol.messages.ToolStatus.running, item.status);
    try std.testing.expect(!item.is_error);
    try std.testing.expectEqual(@as(usize, 3), item.content.len);
    try std.testing.expectEqualStrings("partial", item.content[0].text.text);
    try std.testing.expectEqualStrings("AQID", item.content[1].image.data);
    try std.testing.expectEqualStrings("image/png", item.content[1].image.mime_type);
    try std.testing.expectEqualStrings("BAUG", item.content[2].image.data);
    try std.testing.expectEqualStrings("image/jpeg", item.content[2].image.mime_type);
    try std.testing.expectEqual(@as(i64, 2), item.details.?.object.get("phase").?.integer);
    try std.testing.expectEqual(@as(u64, 7), item.usage.?.input);
    try std.testing.expectEqual(@as(u64, 17), item.usage.?.total_tokens);
    try std.testing.expectEqual(@as(?u64, 1), item.usage.?.reasoning);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), item.usage.?.cost.total, 1e-12);
}
