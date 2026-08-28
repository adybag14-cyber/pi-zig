//! Persistent compatibility runtime for upstream JavaScript and TypeScript
//! extensions. The Zig host owns discovery, lifecycle, validation, limits and
//! agent integration; Node is used only to execute the extension language that
//! upstream Pi exposes as a public plugin ABI.
const std = @import("std");
const Io = std.Io;

const bridge_source = @embedFile("js_bridge.mjs");
const record_prefix: u8 = 0x1e;
var bridge_temp_counter: std.atomic.Value(u64) = .init(1);

fn privateFilePermissions() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) return std.Io.File.Permissions.fromMode(0o600);
    return .default_file;
}

fn materializeBridge(gpa: std.mem.Allocator, io: Io, source_path: []const u8) ![]u8 {
    const parent = std.fs.path.dirname(source_path) orelse ".";
    const source_hash = std.hash.Wyhash.hash(0, source_path);
    var attempts: usize = 0;
    while (attempts < 32) : (attempts += 1) {
        const sequence = bridge_temp_counter.fetchAdd(1, .monotonic);
        const name = try std.fmt.allocPrint(gpa, ".pi-zig-js-bridge-{x}-{x}.mjs", .{ source_hash, sequence });
        defer gpa.free(name);
        const path = try std.fs.path.join(gpa, &.{ parent, name });
        errdefer gpa.free(path);
        const file = std.Io.Dir.cwd().createFile(io, path, .{
            .exclusive = true,
            .permissions = privateFilePermissions(),
        }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                gpa.free(path);
                continue;
            },
            else => return err,
        };
        errdefer std.Io.Dir.cwd().deleteFile(io, path) catch {};
        defer file.close(io);
        try file.writePositionalAll(io, bridge_source, 0);
        return path;
    }
    return error.TemporaryBridgeNameExhausted;
}

/// Host-owned bridge for interactive extension UI. Request callbacks return an
/// owned JSON value (for example `"choice"`, `true`, or `null`). Action
/// callbacks apply persistent UI mutations and do not produce a response.
pub const UiBridge = struct {
    context: ?*anyopaque = null,
    request_fn: *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8) anyerror![]u8,
    action_fn: *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8) anyerror!void,
};

/// Synchronous callback for a normalized extension-tool partial result. The
/// JSON object is owned by the runtime and remains valid only for the callback.
pub const ToolUpdateFn = *const fn (?*anyopaque, []const u8) anyerror!void;

/// Synchronous consumer for one acknowledged extension-provider stream event.
/// `event_json` is owned by the runtime and remains valid only for the callback.
/// Returning an error produces a negative acknowledgement; the JavaScript
/// iterator then settles through its normal failure path so the worker remains
/// protocol-synchronized and reusable.
pub const ProviderStreamEventFn = *const fn (?*anyopaque, u64, []const u8) anyerror!void;

pub const Runtime = struct {
    gpa: std.mem.Allocator,
    io: Io,
    child: std.process.Child,
    source_path: []u8,
    node_program: []u8,
    bridge_path: []u8,
    mutex: Io.Mutex = .init,
    /// Serializes worker stdin independently so the abort watcher can write while
    /// the invocation thread is blocked waiting for worker stdout.
    write_mutex: Io.Mutex = .init,
    read_buffer: [8192]u8 = undefined,
    read_start: usize = 0,
    read_end: usize = 0,
    max_line_bytes: usize = 4 * 1024 * 1024,
    max_discard_bytes: usize = 1024 * 1024,
    timeout_ms: u64 = 15_000,
    /// OAuth login includes human browser/device interaction and must not inherit
    /// the short ordinary extension callback deadline. Zero disables this bound.
    oauth_login_timeout_ms: u64 = 15 * 60 * 1000,
    /// Dynamic catalog refresh is caller-bounded through its AbortSignal. Zero
    /// preserves upstream's unbounded default when the public caller supplies no deadline.
    models_refresh_timeout_ms: u64 = 0,
    /// Provider streams are normally bounded by the model/provider and the live
    /// AbortSignal rather than an arbitrary wall-clock timeout. Callers may set
    /// this non-zero for a deployment-specific upper bound.
    provider_stream_timeout_ms: u64 = 0,
    closed: bool = false,
    last_error: ?[]u8 = null,
    ui_bridge: ?UiBridge = null,
    context_json: ?[]u8 = null,
    next_invocation_id: u64 = 1,
    /// Lock-free identity of the one provider stream currently owned by this
    /// persistent worker. Registry replacement can request retirement without
    /// waiting on `mutex`, which is held by the streaming invocation itself.
    active_provider_stream: bool align(@alignOf(u64)) = false,
    active_provider_hash: u64 = 0,
    active_provider_generation: u64 = 0,
    active_provider_invocation_id: u64 = 0,
    retired_provider_generation: u64 = 0,

    pub const Started = struct {
        runtime: *Runtime,
        manifest_json: []u8,
    };

    pub fn start(
        gpa: std.mem.Allocator,
        io: Io,
        source_path: []const u8,
        node_program: []const u8,
    ) !Started {
        const runtime = try spawnRuntime(gpa, io, source_path, node_program);
        errdefer runtime.deinit();

        const ready_line = try runtime.readRecordUnlocked();
        defer gpa.free(ready_line);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, ready_line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidJavaScriptExtensionHandshake;
        const type_value = parsed.value.object.get("type") orelse return error.InvalidJavaScriptExtensionHandshake;
        const manifest = parsed.value.object.get("manifest") orelse return error.InvalidJavaScriptExtensionHandshake;
        if (type_value != .string or !std.mem.eql(u8, type_value.string, "ready") or manifest != .object) {
            return error.InvalidJavaScriptExtensionHandshake;
        }
        const manifest_json = try stringifyValue(gpa, manifest);
        return .{ .runtime = runtime, .manifest_json = manifest_json };
    }

    fn spawnRuntime(
        gpa: std.mem.Allocator,
        io: Io,
        source_path: []const u8,
        node_program: []const u8,
    ) !*Runtime {
        const owned_source = try gpa.dupe(u8, source_path);
        errdefer gpa.free(owned_source);
        const owned_node = try gpa.dupe(u8, node_program);
        errdefer gpa.free(owned_node);
        const owned_bridge = try materializeBridge(gpa, io, source_path);
        errdefer {
            std.Io.Dir.cwd().deleteFile(io, owned_bridge) catch {};
            gpa.free(owned_bridge);
        }

        const argv = [_][]const u8{
            owned_node,
            "--no-warnings",
            "--experimental-strip-types",
            "--experimental-transform-types",
            owned_bridge,
            owned_source,
        };
        var child = std.process.spawn(io, .{
            .argv = &argv,
            .stdin = .pipe,
            .stdout = .pipe,
            // Extension diagnostics remain visible and cannot fill an unread
            // pipe. Protocol records stay isolated on stdout by a record byte.
            .stderr = .inherit,
        }) catch |err| switch (err) {
            error.FileNotFound => return error.JavaScriptRuntimeNotFound,
            else => return err,
        };
        errdefer child.kill(io);

        const runtime = try gpa.create(Runtime);
        errdefer gpa.destroy(runtime);
        runtime.* = .{
            .gpa = gpa,
            .io = io,
            .child = child,
            .source_path = owned_source,
            .node_program = owned_node,
            .bridge_path = owned_bridge,
        };
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        self.mutex.lockUncancelable(self.io);
        if (!self.closed) {
            self.writeLine("{\"kind\":\"shutdown\"}") catch {};
            terminateChild(&self.child, self.io);
            self.closed = true;
        }
        self.mutex.unlock(self.io);
        if (self.last_error) |message| self.gpa.free(message);
        if (self.context_json) |context| self.gpa.free(context);
        self.gpa.free(self.source_path);
        self.gpa.free(self.node_program);
        std.Io.Dir.cwd().deleteFile(self.io, self.bridge_path) catch {};
        self.gpa.free(self.bridge_path);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    pub fn lastError(self: *const Runtime) ?[]const u8 {
        return self.last_error;
    }

    pub fn setUiBridge(self: *Runtime, bridge: ?UiBridge) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.ui_bridge = bridge;
    }

    /// Update the context exposed through ExtensionContext for later calls.
    /// The worker receives an owned snapshot on every invocation, so callers
    /// can safely update editor/model/mode state between requests.
    pub fn setContextJson(self: *Runtime, raw: []const u8) !void {
        try validateObjectJson(self.gpa, raw);
        const owned = try self.gpa.dupe(u8, raw);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.context_json) |old| self.gpa.free(old);
        self.context_json = owned;
    }

    fn writeContext(self: *const Runtime, writer: *std.Io.Writer) !void {
        try writer.writeAll(self.context_json orelse "{\"mode\":\"print\",\"hasUI\":false}");
    }

    pub fn invokeHook(self: *Runtime, name: []const u8, payload_json: []const u8, flags_json: []const u8) ![]u8 {
        return self.invokeHookWithAbort(name, payload_json, flags_json, null);
    }

    /// Invoke an extension lifecycle hook with the live agent cancellation
    /// signal. The same invocation-scoped controller is exposed as ctx.signal.
    pub fn invokeHookWithAbort(
        self: *Runtime,
        name: []const u8,
        payload_json: []const u8,
        flags_json: []const u8,
        abort_flag: ?*bool,
    ) ![]u8 {
        return self.invoke(.hook, name, payload_json, flags_json, null, abort_flag, false, null, null);
    }

    pub fn invokeTool(self: *Runtime, name: []const u8, arguments_json: []const u8, flags_json: []const u8) ![]u8 {
        return self.invokeToolCall("pi-zig-runtime", name, arguments_json, flags_json, null);
    }

    /// Execute a tool with the exact agent tool-call identity and a live native
    /// cooperative-abort flag, exposed to the extension as one AbortSignal.
    pub fn invokeToolCall(
        self: *Runtime,
        tool_call_id: []const u8,
        name: []const u8,
        arguments_json: []const u8,
        flags_json: []const u8,
        abort_flag: ?*bool,
    ) ![]u8 {
        return self.invoke(.tool, name, arguments_json, flags_json, tool_call_id, abort_flag, false, null, null);
    }

    /// Execute a tool while forwarding each `onUpdate()` record as soon as the
    /// persistent JavaScript worker emits it. The final response intentionally
    /// omits those already-delivered updates, preventing duplicate events.
    pub fn invokeToolStreaming(
        self: *Runtime,
        name: []const u8,
        arguments_json: []const u8,
        flags_json: []const u8,
        update_fn: ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) ![]u8 {
        return self.invokeToolCallStreaming("pi-zig-runtime", name, arguments_json, flags_json, null, update_fn, update_ctx);
    }

    /// Streaming counterpart to invokeToolCall. The call identity and abort flag
    /// remain tied to this invocation while partial updates are forwarded live.
    pub fn invokeToolCallStreaming(
        self: *Runtime,
        tool_call_id: []const u8,
        name: []const u8,
        arguments_json: []const u8,
        flags_json: []const u8,
        abort_flag: ?*bool,
        update_fn: ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) ![]u8 {
        return self.invoke(.tool, name, arguments_json, flags_json, tool_call_id, abort_flag, true, update_fn, update_ctx);
    }

    pub fn invokeCommand(self: *Runtime, name: []const u8, raw_arguments: []const u8, flags_json: []const u8) ![]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        try validateObjectJson(self.gpa, flags_json);

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"command\",\"name\":");
        try std.json.Stringify.value(name, .{}, &request.writer);
        try request.writer.writeAll(",\"rawArguments\":");
        try std.json.Stringify.value(raw_arguments, .{}, &request.writer);
        try request.writer.writeAll(",\"flags\":");
        try request.writer.writeAll(flags_json);
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeUnlocked(request.written());
    }

    pub fn invokeShortcut(self: *Runtime, key: []const u8, flags_json: []const u8) ![]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        try validateObjectJson(self.gpa, flags_json);

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"shortcut\",\"name\":");
        try std.json.Stringify.value(key, .{}, &request.writer);
        try request.writer.writeAll(",\"flags\":");
        try request.writer.writeAll(flags_json);
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeUnlocked(request.written());
    }

    /// Invoke one function retained from an extension-owned provider config.
    /// `args_json` must be a JSON array and the returned owned object has the
    /// shape `{"value": <callback result>}`. When `append_signal` is true the
    /// worker appends an invocation-scoped AbortSignal after the supplied args.
    pub fn invokeProviderMethod(
        self: *Runtime,
        callback_id: []const u8,
        args_json: []const u8,
        append_signal: bool,
        abort_flag: ?*bool,
    ) ![]u8 {
        if (callback_id.len == 0 or callback_id.len > 4096) return error.InvalidProviderCallbackId;
        try validateArrayJson(self.gpa, args_json);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_method\",\"callbackId\":");
        try std.json.Stringify.value(callback_id, .{}, &request.writer);
        try request.writer.writeAll(",\"args\":");
        try request.writer.writeAll(args_json);
        if (append_signal) try request.writer.writeAll(",\"appendSignal\":true");

        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\"", .{invocation_id});
        if (append_signal or abort_flag != null) try request.writer.writeAll(",\"abortable\":true");
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire))
            try request.writer.writeAll(",\"aborted\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeWithUpdatesUnlocked(request.written(), invocation_id, abort_flag, null, null);
    }

    /// Invoke an extension-defined `oauth.login(callbacks)` method. The
    /// dedicated bridge remains installed only for this invocation, so auth UI
    /// requests cannot leak into later extension calls or survive cancellation.
    pub fn invokeProviderOAuthLogin(
        self: *Runtime,
        callback_id: []const u8,
        abort_flag: ?*bool,
        bridge: ?UiBridge,
    ) ![]u8 {
        if (callback_id.len == 0 or callback_id.len > 4096) return error.InvalidProviderCallbackId;

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        const previous_bridge = self.ui_bridge;
        self.ui_bridge = bridge;
        defer self.ui_bridge = previous_bridge;
        const previous_timeout = self.timeout_ms;
        self.timeout_ms = self.oauth_login_timeout_ms;
        defer self.timeout_ms = previous_timeout;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_oauth_login\",\"callbackId\":");
        try std.json.Stringify.value(callback_id, .{}, &request.writer);

        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\",\"abortable\":true", .{invocation_id});
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire))
            try request.writer.writeAll(",\"aborted\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeWithUpdatesUnlocked(request.written(), invocation_id, abort_flag, null, null);
    }

    /// Invoke an extension-defined `refreshModels(context)` callback with a
    /// dedicated host bridge for generation-checked `context.publish()` calls.
    /// The worker returns `{"models":[...]}` after validating JSON safety and
    /// preserving the callback's live AbortSignal.
    pub fn invokeProviderRefreshModels(
        self: *Runtime,
        callback_id: []const u8,
        provider_name: []const u8,
        refresh_context_json: []const u8,
        abort_flag: ?*bool,
        bridge: UiBridge,
    ) ![]u8 {
        if (callback_id.len == 0 or callback_id.len > 4096) return error.InvalidProviderCallbackId;
        if (provider_name.len == 0 or provider_name.len > 4096) return error.InvalidExtensionProviderName;
        try validateObjectJson(self.gpa, refresh_context_json);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        const previous_bridge = self.ui_bridge;
        self.ui_bridge = bridge;
        defer self.ui_bridge = previous_bridge;
        const previous_timeout = self.timeout_ms;
        self.timeout_ms = self.models_refresh_timeout_ms;
        defer self.timeout_ms = previous_timeout;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_refresh_models\",\"callbackId\":");
        try std.json.Stringify.value(callback_id, .{}, &request.writer);
        try request.writer.writeAll(",\"providerName\":");
        try std.json.Stringify.value(provider_name, .{}, &request.writer);
        try request.writer.writeAll(",\"refreshContext\":");
        try request.writer.writeAll(refresh_context_json);

        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\",\"abortable\":true", .{invocation_id});
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire))
            try request.writer.writeAll(",\"aborted\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeWithUpdatesUnlocked(request.written(), invocation_id, abort_flag, null, null);
    }

    /// Invoke extension-defined `streamSimple(model, context, options)` on its
    /// persistent owning worker. Every event is delivered exactly once to
    /// `event_fn`; the worker waits for the native acknowledgement before asking
    /// the async iterator for another event, providing cross-process backpressure.
    pub fn invokeProviderStreamSimple(
        self: *Runtime,
        provider_name: []const u8,
        callback_id: []const u8,
        callback_generation: u64,
        model_json: []const u8,
        stream_context_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
        event_fn: ProviderStreamEventFn,
        event_ctx: ?*anyopaque,
    ) ![]u8 {
        if (provider_name.len == 0 or provider_name.len > 4096) return error.InvalidExtensionProviderName;
        if (callback_id.len == 0 or callback_id.len > 4096 or callback_generation == 0) return error.InvalidProviderCallbackId;
        try validateObjectJson(self.gpa, model_json);
        try validateObjectJson(self.gpa, stream_context_json);
        try validateObjectJson(self.gpa, options_json);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        const previous_timeout = self.timeout_ms;
        self.timeout_ms = self.provider_stream_timeout_ms;
        defer self.timeout_ms = previous_timeout;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_stream_simple\",\"callbackId\":");
        try std.json.Stringify.value(callback_id, .{}, &request.writer);
        try request.writer.writeAll(",\"providerName\":");
        try std.json.Stringify.value(provider_name, .{}, &request.writer);
        try request.writer.print(",\"callbackGeneration\":{d}", .{callback_generation});
        try request.writer.writeAll(",\"model\":");
        try request.writer.writeAll(model_json);
        try request.writer.writeAll(",\"streamContext\":");
        try request.writer.writeAll(stream_context_json);
        try request.writer.writeAll(",\"options\":");
        try request.writer.writeAll(options_json);

        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\",\"abortable\":true", .{invocation_id});
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire))
            try request.writer.writeAll(",\"aborted\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        @atomicStore(u64, &self.active_provider_hash, std.hash.Wyhash.hash(0, provider_name), .release);
        @atomicStore(u64, &self.active_provider_generation, callback_generation, .release);
        @atomicStore(u64, &self.active_provider_invocation_id, invocation_id, .release);
        @atomicStore(u64, &self.retired_provider_generation, 0, .release);
        @atomicStore(bool, &self.active_provider_stream, true, .release);
        defer {
            @atomicStore(bool, &self.active_provider_stream, false, .release);
            @atomicStore(u64, &self.active_provider_invocation_id, 0, .release);
            @atomicStore(u64, &self.active_provider_generation, 0, .release);
            @atomicStore(u64, &self.active_provider_hash, 0, .release);
            @atomicStore(u64, &self.retired_provider_generation, 0, .release);
        }
        return self.exchangeProviderStreamUnlocked(request.written(), invocation_id, abort_flag, event_fn, event_ctx);
    }

    /// Fetch a provider-owned deferred response through the same acknowledged
    /// event protocol and generation-retirement boundary as `streamSimple`.
    pub fn invokeProviderFetchDeferred(
        self: *Runtime,
        provider_name: []const u8,
        callback_id: []const u8,
        callback_generation: u64,
        model_json: []const u8,
        handle_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
        event_fn: ProviderStreamEventFn,
        event_ctx: ?*anyopaque,
    ) ![]u8 {
        if (provider_name.len == 0 or provider_name.len > 4096) return error.InvalidExtensionProviderName;
        if (callback_id.len == 0 or callback_id.len > 4096 or callback_generation == 0) return error.InvalidProviderCallbackId;
        try validateObjectJson(self.gpa, model_json);
        try validateObjectJson(self.gpa, handle_json);
        try validateObjectJson(self.gpa, options_json);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        const previous_timeout = self.timeout_ms;
        self.timeout_ms = self.provider_stream_timeout_ms;
        defer self.timeout_ms = previous_timeout;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_fetch_deferred\",\"callbackId\":");
        try std.json.Stringify.value(callback_id, .{}, &request.writer);
        try request.writer.writeAll(",\"providerName\":");
        try std.json.Stringify.value(provider_name, .{}, &request.writer);
        try request.writer.print(",\"callbackGeneration\":{d},\"model\":", .{callback_generation});
        try request.writer.writeAll(model_json);
        try request.writer.writeAll(",\"handle\":");
        try request.writer.writeAll(handle_json);
        try request.writer.writeAll(",\"options\":");
        try request.writer.writeAll(options_json);

        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\",\"abortable\":true", .{invocation_id});
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) try request.writer.writeAll(",\"aborted\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');

        @atomicStore(u64, &self.active_provider_hash, std.hash.Wyhash.hash(0, provider_name), .release);
        @atomicStore(u64, &self.active_provider_generation, callback_generation, .release);
        @atomicStore(u64, &self.active_provider_invocation_id, invocation_id, .release);
        @atomicStore(u64, &self.retired_provider_generation, 0, .release);
        @atomicStore(bool, &self.active_provider_stream, true, .release);
        defer {
            @atomicStore(bool, &self.active_provider_stream, false, .release);
            @atomicStore(u64, &self.active_provider_invocation_id, 0, .release);
            @atomicStore(u64, &self.active_provider_generation, 0, .release);
            @atomicStore(u64, &self.active_provider_hash, 0, .release);
            @atomicStore(u64, &self.retired_provider_generation, 0, .release);
        }
        return self.exchangeProviderStreamUnlocked(request.written(), invocation_id, abort_flag, event_fn, event_ctx);
    }

    pub fn invokeProviderCancelDeferred(
        self: *Runtime,
        provider_name: []const u8,
        callback_id: []const u8,
        callback_generation: u64,
        model_json: []const u8,
        handle_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
    ) ![]u8 {
        if (provider_name.len == 0 or provider_name.len > 4096) return error.InvalidExtensionProviderName;
        if (callback_id.len == 0 or callback_id.len > 4096 or callback_generation == 0) return error.InvalidProviderCallbackId;
        try validateObjectJson(self.gpa, model_json);
        try validateObjectJson(self.gpa, handle_json);
        try validateObjectJson(self.gpa, options_json);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_cancel_deferred\",\"callbackId\":");
        try std.json.Stringify.value(callback_id, .{}, &request.writer);
        try request.writer.writeAll(",\"providerName\":");
        try std.json.Stringify.value(provider_name, .{}, &request.writer);
        try request.writer.print(",\"callbackGeneration\":{d},\"model\":", .{callback_generation});
        try request.writer.writeAll(model_json);
        try request.writer.writeAll(",\"handle\":");
        try request.writer.writeAll(handle_json);
        try request.writer.writeAll(",\"options\":");
        try request.writer.writeAll(options_json);
        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\",\"abortable\":true", .{invocation_id});
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) try request.writer.writeAll(",\"aborted\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeWithUpdatesUnlocked(request.written(), invocation_id, abort_flag, null, null);
    }

    /// Request retirement of an active stream from a superseded callback
    /// generation and wait for its bounded JavaScript iterator cleanup. The
    /// provider hash is paired with the runtime-local generation, preventing a
    /// colliding generation from another provider or worker from being aborted.
    pub fn retireProviderGeneration(self: *Runtime, provider_name: []const u8, generation: u64, timeout_ms: u64) bool {
        if (generation == 0 or !@atomicLoad(bool, &self.active_provider_stream, .acquire)) return true;
        if (@atomicLoad(u64, &self.active_provider_hash, .acquire) != std.hash.Wyhash.hash(0, provider_name) or
            @atomicLoad(u64, &self.active_provider_generation, .acquire) != generation)
        {
            return true;
        }
        @atomicStore(u64, &self.retired_provider_generation, generation, .release);
        var elapsed_ms: u64 = 0;
        while (@atomicLoad(bool, &self.active_provider_stream, .acquire) and elapsed_ms < timeout_ms) : (elapsed_ms += 5) {
            const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(5), .clock = .awake } };
            pause.sleep(self.io) catch break;
        }
        return !@atomicLoad(bool, &self.active_provider_stream, .acquire);
    }

    /// Acknowledge the exact callback IDs selected by the committed native
    /// registry snapshot. JavaScript retains older generations until this
    /// exchange succeeds, so failed native handoff cannot create dangling IDs.
    pub fn commitProviderCallbacks(self: *Runtime, provider_name: []const u8, callback_ids: []const []const u8) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":\"provider_callback_commit\",\"providerName\":");
        try std.json.Stringify.value(provider_name, .{}, &request.writer);
        try request.writer.writeAll(",\"callbackIds\":[");
        for (callback_ids, 0..) |callback_id, index| {
            if (index > 0) try request.writer.writeByte(',');
            try std.json.Stringify.value(callback_id, .{}, &request.writer);
        }
        try request.writer.writeAll("]}");
        const response = try self.exchangeUnlocked(request.written());
        self.gpa.free(response);
    }

    /// Invoke a pure extension renderer or markdown transformer. The bridge
    /// returns an owned object such as `{"found":true,"lines":[...]}`.
    /// Renderer calls share the persistent worker, so tool renderer state and
    /// extension closures survive from call rendering to result rendering.
    pub fn invokeRenderer(self: *Runtime, kind: []const u8, name: []const u8, payload_json: []const u8) ![]u8 {
        if (!(std.mem.eql(u8, kind, "render_message") or
            std.mem.eql(u8, kind, "render_entry") or
            std.mem.eql(u8, kind, "transform_markdown") or
            std.mem.eql(u8, kind, "render_tool_call") or
            std.mem.eql(u8, kind, "render_tool_result") or
            std.mem.eql(u8, kind, "prepare_tool_arguments"))) return error.InvalidJavaScriptRendererKind;
        try validateObjectJson(self.gpa, payload_json);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":");
        try std.json.Stringify.value(kind, .{}, &request.writer);
        try request.writer.writeAll(",\"name\":");
        try std.json.Stringify.value(name, .{}, &request.writer);
        try request.writer.writeAll(",\"payload\":");
        try request.writer.writeAll(payload_json);
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeUnlocked(request.written());
    }

    const InvocationKind = enum { hook, tool };

    fn invoke(
        self: *Runtime,
        kind: InvocationKind,
        name: []const u8,
        payload_json: []const u8,
        flags_json: []const u8,
        tool_call_id: ?[]const u8,
        abort_flag: ?*bool,
        stream_updates: bool,
        update_fn: ?ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) ![]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.JavaScriptExtensionClosed;
        try validateObjectJson(self.gpa, payload_json);
        try validateObjectJson(self.gpa, flags_json);

        var request: std.Io.Writer.Allocating = .init(self.gpa);
        defer request.deinit();
        try request.writer.writeAll("{\"kind\":");
        try std.json.Stringify.value(@tagName(kind), .{}, &request.writer);
        try request.writer.writeAll(",\"name\":");
        try std.json.Stringify.value(name, .{}, &request.writer);
        try request.writer.writeAll(",\"payload\":");
        try request.writer.writeAll(payload_json);
        try request.writer.writeAll(",\"flags\":");
        try request.writer.writeAll(flags_json);
        if (tool_call_id) |id| {
            try request.writer.writeAll(",\"toolCallId\":");
            try std.json.Stringify.value(id, .{}, &request.writer);
        }
        const invocation_id = self.next_invocation_id;
        self.next_invocation_id +%= 1;
        if (self.next_invocation_id == 0) self.next_invocation_id = 1;
        try request.writer.print(",\"invocationId\":\"{d}\"", .{invocation_id});
        if (abort_flag) |flag| {
            try request.writer.writeAll(",\"abortable\":true");
            if (@atomicLoad(bool, flag, .acquire)) try request.writer.writeAll(",\"aborted\":true");
        }
        if (stream_updates) try request.writer.writeAll(",\"streamUpdates\":true");
        try request.writer.writeAll(",\"context\":");
        try self.writeContext(&request.writer);
        try request.writer.writeByte('}');
        return self.exchangeWithUpdatesUnlocked(request.written(), invocation_id, abort_flag, update_fn, update_ctx);
    }

    fn exchangeUnlocked(self: *Runtime, request: []const u8) ![]u8 {
        return self.exchangeWithUpdatesUnlocked(request, 0, null, null, null);
    }

    fn exchangeWithUpdatesUnlocked(
        self: *Runtime,
        request: []const u8,
        invocation_id: u64,
        abort_flag: ?*bool,
        update_fn: ?ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) ![]u8 {
        return self.exchangeWithCallbacksUnlocked(request, invocation_id, abort_flag, update_fn, update_ctx, null, null, false);
    }

    fn exchangeProviderStreamUnlocked(
        self: *Runtime,
        request: []const u8,
        invocation_id: u64,
        abort_flag: ?*bool,
        event_fn: ProviderStreamEventFn,
        event_ctx: ?*anyopaque,
    ) ![]u8 {
        return self.exchangeWithCallbacksUnlocked(request, invocation_id, abort_flag, null, null, event_fn, event_ctx, true);
    }

    fn exchangeWithCallbacksUnlocked(
        self: *Runtime,
        request: []const u8,
        invocation_id: u64,
        abort_flag: ?*bool,
        update_fn: ?ToolUpdateFn,
        update_ctx: ?*anyopaque,
        stream_event_fn: ?ProviderStreamEventFn,
        stream_event_ctx: ?*anyopaque,
        watch_provider_retirement: bool,
    ) ![]u8 {
        self.clearLastErrorUnlocked();
        self.writeLine(request) catch |err| {
            self.closeUnlocked();
            return err;
        };

        var watcher_done = false;
        var watcher_group: Io.Group = .init;
        const watching_abort = invocation_id != 0 and (abort_flag != null or watch_provider_retirement);
        if (watching_abort) watcher_group.async(self.io, abortWatcherTask, .{ self, abort_flag, invocation_id, &watcher_done, watch_provider_retirement });
        defer if (watching_abort) {
            @atomicStore(bool, &watcher_done, true, .release);
            watcher_group.cancel(self.io);
            watcher_group.await(self.io) catch {};
        };

        return self.readResultUnlocked(update_fn, update_ctx, stream_event_fn, stream_event_ctx, invocation_id) catch |err| {
            // Script exceptions are a completed protocol response and leave the
            // worker reusable. Every transport/protocol/callback error can leave
            // unread records behind, so close instead of risking the next
            // invocation consuming a stale final response.
            const forced_retirement = err == error.JavaScriptExtensionExecutionFailed and
                stream_event_fn != null and self.last_error != null and
                std.mem.indexOf(u8, self.last_error.?, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT") != null;
            if (err != error.JavaScriptExtensionExecutionFailed or forced_retirement) self.closeUnlocked();
            return err;
        };
    }

    fn readResultUnlocked(
        self: *Runtime,
        update_fn: ?ToolUpdateFn,
        update_ctx: ?*anyopaque,
        stream_event_fn: ?ProviderStreamEventFn,
        stream_event_ctx: ?*anyopaque,
        expected_invocation_id: u64,
    ) ![]u8 {
        var expected_stream_sequence: u64 = 1;
        while (true) {
            const line = try self.readRecordUnlocked();
            defer self.gpa.free(line);
            var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, line, .{});
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidJavaScriptExtensionResponse;

            if (parsed.value.object.get("type")) |type_value| {
                if (type_value != .string) return error.InvalidJavaScriptExtensionResponse;
                if (std.mem.eql(u8, type_value.string, "ui_request")) {
                    try self.handleUiRequestUnlocked(&parsed.value.object);
                    continue;
                }
                if (std.mem.eql(u8, type_value.string, "ui_action")) {
                    self.handleUiActionUnlocked(&parsed.value.object) catch {};
                    continue;
                }
                if (std.mem.eql(u8, type_value.string, "tool_update")) {
                    const update = parsed.value.object.get("update") orelse return error.InvalidJavaScriptExtensionResponse;
                    if (update != .object) return error.InvalidJavaScriptExtensionResponse;
                    if (update_fn) |callback| {
                        const raw_update = try stringifyValue(self.gpa, update);
                        defer self.gpa.free(raw_update);
                        callback(update_ctx, raw_update) catch |err| {
                            self.closeUnlocked();
                            return err;
                        };
                    }
                    continue;
                }
                if (std.mem.eql(u8, type_value.string, "provider_stream_event")) {
                    const callback = stream_event_fn orelse return error.UnexpectedProviderStreamEvent;
                    const invocation_value = parsed.value.object.get("invocationId") orelse return error.InvalidJavaScriptExtensionResponse;
                    const sequence_value = parsed.value.object.get("sequence") orelse return error.InvalidJavaScriptExtensionResponse;
                    const event_value = parsed.value.object.get("event") orelse return error.InvalidJavaScriptExtensionResponse;
                    if (invocation_value != .string or sequence_value != .integer or sequence_value.integer <= 0 or event_value != .object) {
                        return error.InvalidJavaScriptExtensionResponse;
                    }
                    const actual_invocation_id = std.fmt.parseUnsigned(u64, invocation_value.string, 10) catch return error.InvalidJavaScriptExtensionResponse;
                    const sequence: u64 = @intCast(sequence_value.integer);
                    if (actual_invocation_id != expected_invocation_id or sequence != expected_stream_sequence) {
                        return error.InvalidProviderStreamSequence;
                    }
                    const raw_event = try stringifyValue(self.gpa, event_value);
                    defer self.gpa.free(raw_event);
                    callback(stream_event_ctx, sequence, raw_event) catch |err| {
                        try self.sendProviderStreamAckUnlocked(invocation_value.string, sequence, false, @errorName(err));
                        continue;
                    };
                    try self.sendProviderStreamAckUnlocked(invocation_value.string, sequence, true, null);
                    expected_stream_sequence += 1;
                    continue;
                }
            }

            const ok_value = parsed.value.object.get("ok") orelse return error.InvalidJavaScriptExtensionResponse;
            if (ok_value != .bool) return error.InvalidJavaScriptExtensionResponse;
            if (!ok_value.bool) {
                if (parsed.value.object.get("error")) |message| if (message == .string) {
                    self.last_error = try self.gpa.dupe(u8, message.string);
                };
                return error.JavaScriptExtensionExecutionFailed;
            }
            const result = parsed.value.object.get("result") orelse return self.gpa.dupe(u8, "{}");
            if (result != .object) return error.InvalidJavaScriptExtensionResponse;
            return stringifyValue(self.gpa, result);
        }
    }

    fn sendProviderStreamAckUnlocked(
        self: *Runtime,
        invocation_id: []const u8,
        sequence: u64,
        ok: bool,
        error_message: ?[]const u8,
    ) !void {
        var response: std.Io.Writer.Allocating = .init(self.gpa);
        defer response.deinit();
        try response.writer.writeAll("{\"kind\":\"provider_stream_ack\",\"invocationId\":");
        try std.json.Stringify.value(invocation_id, .{}, &response.writer);
        try response.writer.print(",\"sequence\":{d},\"ok\":{s},\"accepted\":{s}", .{ sequence, if (ok) "true" else "false", if (ok) "true" else "false" });
        if (error_message) |message| {
            try response.writer.writeAll(",\"error\":");
            try std.json.Stringify.value(message, .{}, &response.writer);
        }
        try response.writer.writeByte('}');
        try self.writeLine(response.written());
    }

    fn handleUiRequestUnlocked(self: *Runtime, object: *const std.json.ObjectMap) !void {
        const id_value = object.get("id") orelse return error.InvalidJavaScriptExtensionResponse;
        if (id_value != .integer or id_value.integer < 0) return error.InvalidJavaScriptExtensionResponse;
        const method_value = object.get("method") orelse return error.InvalidJavaScriptExtensionResponse;
        if (method_value != .string or method_value.string.len == 0) return error.InvalidJavaScriptExtensionResponse;
        const args_value = object.get("args") orelse std.json.Value{ .object = .empty };
        if (args_value != .object) return error.InvalidJavaScriptExtensionResponse;
        const args_json = try stringifyValue(self.gpa, args_value);
        defer self.gpa.free(args_json);

        var result_json: ?[]u8 = null;
        var error_message: ?[]u8 = null;
        if (self.ui_bridge) |bridge| {
            result_json = bridge.request_fn(bridge.context, self.gpa, method_value.string, args_json) catch |err| blk: {
                error_message = try std.fmt.allocPrint(self.gpa, "native UI request failed: {s}", .{@errorName(err)});
                break :blk null;
            };
        } else {
            result_json = try self.gpa.dupe(u8, if (std.mem.eql(u8, method_value.string, "confirm")) "false" else "null");
        }
        defer if (result_json) |value| self.gpa.free(value);
        defer if (error_message) |value| self.gpa.free(value);

        if (result_json) |value| try validateAnyJson(self.gpa, value);
        var response: std.Io.Writer.Allocating = .init(self.gpa);
        defer response.deinit();
        try response.writer.print("{{\"kind\":\"ui_response\",\"id\":{d},", .{id_value.integer});
        if (result_json) |value| {
            try response.writer.writeAll("\"ok\":true,\"result\":");
            try response.writer.writeAll(value);
        } else {
            try response.writer.writeAll("\"ok\":false,\"error\":");
            try std.json.Stringify.value(error_message orelse "native UI request failed", .{}, &response.writer);
        }
        try response.writer.writeByte('}');
        try self.writeLine(response.written());
    }

    fn handleUiActionUnlocked(self: *Runtime, object: *const std.json.ObjectMap) !void {
        const bridge = self.ui_bridge orelse return;
        const method_value = object.get("method") orelse return error.InvalidJavaScriptExtensionResponse;
        if (method_value != .string or method_value.string.len == 0) return error.InvalidJavaScriptExtensionResponse;
        const args_value = object.get("args") orelse std.json.Value{ .object = .empty };
        if (args_value != .object) return error.InvalidJavaScriptExtensionResponse;
        const args_json = try stringifyValue(self.gpa, args_value);
        defer self.gpa.free(args_json);
        try bridge.action_fn(bridge.context, self.gpa, method_value.string, args_json);
    }

    fn clearLastErrorUnlocked(self: *Runtime) void {
        if (self.last_error) |message| self.gpa.free(message);
        self.last_error = null;
    }

    fn closeUnlocked(self: *Runtime) void {
        if (self.closed) return;
        terminateChild(&self.child, self.io);
        self.closed = true;
    }

    fn writeLine(self: *Runtime, line: []const u8) !void {
        self.write_mutex.lockUncancelable(self.io);
        defer self.write_mutex.unlock(self.io);
        const stdin_file = self.child.stdin orelse return error.JavaScriptExtensionClosed;
        var buffer: [4096]u8 = undefined;
        var writer = stdin_file.writerStreaming(self.io, &buffer);
        try writer.interface.writeAll(line);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    /// Ignore ordinary stdout from extension code and consume only bridge
    /// records prefixed with ASCII Record Separator (0x1e). The timeout races
    /// the complete record scan rather than each discarded line. This matters
    /// when an extension writes ordinary stdout immediately before a protocol
    /// record: both lines may already be in our persistent read buffer.
    fn readRecordUnlocked(self: *Runtime) ![]u8 {
        if (self.timeout_ms == 0) return self.readRecordBlockingUnlocked();
        const Race = union(enum) { record: anyerror![]u8, timeout: bool };
        var queue: [2]Race = undefined;
        var select = Io.Select(Race).init(self.io, &queue);
        select.async(.record, readRecordTask, .{self});
        select.async(.timeout, timeoutTask, .{ self.io, self.timeout_ms });
        const winner = try select.await();
        switch (winner) {
            .record => |result| {
                drainRecordRace(&select, self.gpa);
                return try result;
            },
            .timeout => |expired| {
                drainRecordRace(&select, self.gpa);
                if (expired) return error.JavaScriptExtensionTimeout;
                return error.Canceled;
            },
        }
    }

    fn readRecordBlockingUnlocked(self: *Runtime) ![]u8 {
        // The bridge record separator may follow arbitrary extension stdout
        // without a newline. Scan the byte stream itself rather than assuming
        // line alignment, while retaining unread bytes across invocations.
        var discarded: usize = 0;
        while (true) {
            const byte = try self.readByteBlockingUnlocked();
            if (byte != record_prefix) {
                discarded += 1;
                if (discarded > self.max_discard_bytes) return error.JavaScriptExtensionOutputTooLarge;
                continue;
            }

            var record: std.ArrayList(u8) = .empty;
            errdefer record.deinit(self.gpa);
            while (true) {
                const next = try self.readByteBlockingUnlocked();
                if (next == '\n') {
                    if (record.items.len > 0 and record.items[record.items.len - 1] == '\r') _ = record.pop();
                    if (record.items.len == 0) return error.InvalidJavaScriptExtensionResponse;
                    return record.toOwnedSlice(self.gpa);
                }
                try record.append(self.gpa, next);
                if (record.items.len > self.max_line_bytes) return error.JavaScriptExtensionResponseTooLarge;
            }
        }
    }

    fn readByteBlockingUnlocked(self: *Runtime) !u8 {
        if (self.read_start == self.read_end) {
            const stdout_file = self.child.stdout orelse return error.JavaScriptExtensionClosed;
            var slices = [_][]u8{self.read_buffer[0..]};
            const read_count = stdout_file.readStreaming(self.io, &slices) catch |err| switch (err) {
                error.Canceled => return err,
                else => return error.JavaScriptExtensionReadFailed,
            };
            if (read_count == 0) {
                self.closed = true;
                return error.JavaScriptExtensionClosed;
            }
            self.read_start = 0;
            self.read_end = read_count;
        }
        const byte = self.read_buffer[self.read_start];
        self.read_start += 1;
        return byte;
    }
};

/// Watch a shared native abort flag and send one invocation-scoped control
/// record without interrupting the stdout parser. Extensions that cooperate by
/// observing the supplied AbortSignal can settle normally and leave the worker
/// reusable for later commands and tools.
fn abortWatcherTask(
    runtime: *Runtime,
    abort_flag: ?*bool,
    invocation_id: u64,
    done: *bool,
    watch_provider_retirement: bool,
) Io.Cancelable!void {
    while (!@atomicLoad(bool, done, .acquire)) {
        const externally_aborted = if (abort_flag) |flag| @atomicLoad(bool, flag, .acquire) else false;
        const retired = watch_provider_retirement and
            @atomicLoad(bool, &runtime.active_provider_stream, .acquire) and
            @atomicLoad(u64, &runtime.active_provider_invocation_id, .acquire) == invocation_id and
            @atomicLoad(u64, &runtime.retired_provider_generation, .acquire) != 0 and
            @atomicLoad(u64, &runtime.retired_provider_generation, .acquire) ==
                @atomicLoad(u64, &runtime.active_provider_generation, .acquire);
        if (externally_aborted or retired) {
            if (!@atomicLoad(bool, done, .acquire)) {
                var buffer: [256]u8 = undefined;
                const reason = if (retired) "Provider callback generation retired" else "Operation aborted";
                const request = std.fmt.bufPrint(&buffer, "{{\"kind\":\"abort_current\",\"invocationId\":\"{d}\",\"reason\":{f}}}", .{ invocation_id, std.json.fmt(reason, .{}) }) catch return;
                runtime.writeLine(request) catch {};
            }
            return;
        }
        const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(5), .clock = .awake } };
        pause.sleep(runtime.io) catch return;
    }
}

/// Zig 0.16's POSIX `Child.kill()` sends SIGTERM and then waits forever. A
/// JavaScript extension can install a SIGTERM handler (directly or through a
/// dependency), which would make ordinary Pi shutdown uninterruptibly hang.
/// Force termination on POSIX before reaping; Windows Child.kill already uses
/// the native force-termination primitive.
fn terminateChild(child: *std.process.Child, io: Io) void {
    if (child.id == null) return;
    switch (@import("builtin").os.tag) {
        .windows => child.kill(io),
        else => {
            std.posix.kill(child.id.?, .KILL) catch {};
            _ = child.wait(io) catch {};
        },
    }
}

fn readRecordTask(runtime: *Runtime) anyerror![]u8 {
    return runtime.readRecordBlockingUnlocked();
}

fn timeoutTask(io: Io, timeout_ms: u64) bool {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(duration_ms), .clock = .real } };
    timeout.sleep(io) catch return false;
    return true;
}

fn drainRecordRace(select: anytype, gpa: std.mem.Allocator) void {
    while (select.cancel()) |pending| switch (pending) {
        .record => |result| {
            if (result) |record| gpa.free(record) else |_| {}
        },
        .timeout => {},
    };
}

fn stringifyValue(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn validateObjectJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidJavaScriptExtensionRequest;
}

fn validateAnyJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
}

fn validateArrayJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidJavaScriptExtensionRequest;
}

pub fn isScriptPath(path: []const u8) bool {
    const extensions = [_][]const u8{ ".js", ".mjs", ".cjs", ".ts", ".mts", ".cts" };
    for (extensions) |extension| {
        if (path.len >= extension.len and std.ascii.eqlIgnoreCase(path[path.len - extension.len ..], extension)) return true;
    }
    return false;
}

fn valueAtTestPath(root: std.json.Value, path: []const u8) !std.json.Value {
    var current = root;
    var segments = std.mem.splitScalar(u8, path, '.');
    while (segments.next()) |segment| {
        if (segment.len == 0) return error.InvalidTestPath;
        current = switch (current) {
            .object => |object| object.get(segment) orelse return error.TestPathNotFound,
            .array => |array| blk: {
                const index = std.fmt.parseInt(usize, segment, 10) catch return error.InvalidTestPath;
                if (index >= array.items.len) return error.TestPathNotFound;
                break :blk array.items[index];
            },
            else => return error.TestPathNotFound,
        };
    }
    return current;
}

fn callbackIdAtTestValue(gpa: std.mem.Allocator, root: std.json.Value, path: []const u8) ![]u8 {
    const descriptor = try valueAtTestPath(root, path);
    if (descriptor != .object) return error.InvalidTestCallbackDescriptor;
    const kind = descriptor.object.get("__pi_callback_kind") orelse return error.InvalidTestCallbackDescriptor;
    const callback_id = descriptor.object.get("__pi_callback_id") orelse return error.InvalidTestCallbackDescriptor;
    const descriptor_path = descriptor.object.get("__pi_callback_path") orelse return error.InvalidTestCallbackDescriptor;
    if (kind != .string or !std.mem.eql(u8, kind.string, "provider_method")) return error.InvalidTestCallbackDescriptor;
    if (callback_id != .string or callback_id.string.len == 0) return error.InvalidTestCallbackDescriptor;
    if (descriptor_path != .string or !std.mem.eql(u8, descriptor_path.string, path)) return error.InvalidTestCallbackDescriptor;
    return gpa.dupe(u8, callback_id.string);
}

fn providerManifestCallbackId(
    gpa: std.mem.Allocator,
    manifest_json: []const u8,
    provider_name: []const u8,
    path: []const u8,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidTestManifest;
    const providers = parsed.value.object.get("providers") orelse return error.InvalidTestManifest;
    if (providers != .array) return error.InvalidTestManifest;
    for (providers.array.items) |entry| {
        if (entry != .object) continue;
        const name = entry.object.get("name") orelse continue;
        const config = entry.object.get("config") orelse continue;
        if (name == .string and std.mem.eql(u8, name.string, provider_name)) {
            return callbackIdAtTestValue(gpa, config, path);
        }
    }
    return error.TestProviderNotFound;
}

fn providerActionCallbackId(
    gpa: std.mem.Allocator,
    result_json: []const u8,
    provider_name: []const u8,
    path: []const u8,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, result_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidTestAction;
    const providers = parsed.value.object.get("providers") orelse return error.InvalidTestAction;
    if (providers != .array) return error.InvalidTestAction;
    for (providers.array.items) |entry| {
        if (entry != .object) continue;
        const action = entry.object.get("action") orelse continue;
        const name = entry.object.get("name") orelse continue;
        const config = entry.object.get("config") orelse continue;
        if (action == .string and std.mem.eql(u8, action.string, "register") and
            name == .string and std.mem.eql(u8, name.string, provider_name))
        {
            return callbackIdAtTestValue(gpa, config, path);
        }
    }
    return error.TestProviderActionNotFound;
}

pub fn nodeAvailable(gpa: std.mem.Allocator, io: Io) bool {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "node", "--version" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return false;
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "script path recognition" {
    try std.testing.expect(isScriptPath("hello.ts"));
    try std.testing.expect(isScriptPath("hello.MJS"));
    try std.testing.expect(isScriptPath("hello.cts"));
    try std.testing.expect(!isScriptPath("extension.json"));
}

test "persistent TypeScript compatibility runtime registers and executes upstream-shaped APIs" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { Type } from '@earendil-works/pi-ai';
        \\import { defineTool, type ExtensionAPI } from '@earendil-works/pi-coding-agent';
        \\import { Key } from '@earendil-works/pi-tui';
        \\enum Tone { Friendly = 'friendly' }
        \\export default function(pi: ExtensionAPI) {
        \\  let count = 0;
        \\  pi.registerFlag('loud', { type: 'boolean', default: false });
        \\  pi.on('input', async (event) => event.text.startsWith('x:') ? { action: 'transform', text: event.text.slice(2) } : { action: 'continue' });
        \\  pi.registerCommand('inc', { description: 'increment', handler: async (_args, ctx) => { count++; ctx.ui.notify(`count=${count}`); } });
        \\  pi.registerShortcut(Key.ctrlShift('u'), { description: 'shortcut', handler: async (ctx) => { count += 10; ctx.ui.notify(`shortcut=${count}`); } });
        \\  pi.registerTool(defineTool({ name: 'hello', description: Tone.Friendly, parameters: Type.Object({ name: Type.String() }), async execute(_id, params) { return { content: [{ type: 'text', text: `Hello ${params.name} ${count}` }], details: {} }; } }));
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "extension.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "extension.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try std.testing.expect(std.mem.indexOf(u8, started.manifest_json, "\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.manifest_json, "\"inc\"") != null);

    const first = try started.runtime.invokeCommand("inc", "", "{}");
    defer gpa.free(first);
    const second = try started.runtime.invokeCommand("inc", "", "{}");
    defer gpa.free(second);
    try std.testing.expect(std.mem.indexOf(u8, first, "count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, second, "count=2") != null);

    const shortcut = try started.runtime.invokeShortcut("ctrl+shift+u", "{}");
    defer gpa.free(shortcut);
    try std.testing.expect(std.mem.indexOf(u8, shortcut, "shortcut=12") != null);

    const transformed = try started.runtime.invokeHook("before_prompt", "{\"prompt\":\"x:hello\"}", "{}");
    defer gpa.free(transformed);
    try std.testing.expect(std.mem.indexOf(u8, transformed, "\"prompt\":\"hello\"") != null);

    const tool = try started.runtime.invokeTool("hello", "{\"name\":\"Ada\"}", "{}");
    defer gpa.free(tool);
    try std.testing.expect(std.mem.indexOf(u8, tool, "Hello Ada 12") != null);
}

test "provider methods use the production manifest bridge with ownership re-registration errors cancellation and cleanup" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  const captured = 'closure-181';
        \\  const provider = {
        \\    name: 'Bridge Provider',
        \\    baseUrl: 'https://provider.invalid/v1',
        \\    api: 'openai-completions',
        \\    apiKey: 'unused',
        \\    models: [{ id: 'bridge-model', name: 'Bridge Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      owner: 'oauth-owner',
        \\      async refreshToken(credentials, signal) {
        \\        if (this.owner !== 'oauth-owner') throw new Error('refresh receiver lost');
        \\        if (!(signal instanceof AbortSignal)) throw new Error('refresh signal missing');
        \\        return { ...credentials, access: `${captured}:${this.owner}:${credentials.refresh}`, expires: 181 };
        \\      },
        \\      getApiKey(credentials) {
        \\        if (this.owner !== 'oauth-owner') throw new Error('key receiver lost');
        \\        return `${captured}:${credentials.access}`;
        \\      },
        \\      async rejectRefresh() { throw new Error('provider-refresh-exploded-181'); },
        \\      async waitForAbort(_credentials, signal) {
        \\        await new Promise((resolve, reject) => {
        \\          if (signal.aborted) { reject(signal.reason); return; }
        \\          const timer = setTimeout(() => reject(new Error('provider abort was not delivered')), 1500);
        \\          signal.addEventListener('abort', () => { clearTimeout(timer); reject(signal.reason); }, { once: true });
        \\        });
        \\      },
        \\    },
        \\    nested: { methods: [function(value) { return `${this.length}:${captured}:${value}`; }] },
        \\  };
        \\  pi.registerProvider('bridge-demo', provider);
        \\  pi.registerCommand('replace-provider', { handler: async () => { pi.registerProvider('bridge-demo', { name: 'Renamed Bridge Provider' }); } });
        \\  pi.registerCommand('cycle-provider', { handler: async (_args, ctx) => { const cyclic = {}; cyclic.self = cyclic; try { pi.registerProvider('bridge-demo', { cyclic }); } catch (error) { ctx.ui.notify(error.message); } } });
        \\  pi.registerCommand('unregister-provider', { handler: async () => { pi.unregisterProvider('bridge-demo'); } });
        \\  pi.registerCommand('provider-ping', { handler: async (_args, ctx) => { ctx.ui.notify('provider-worker-reused'); } });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "provider-methods.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "provider-methods.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 5000;

    const refresh_id = try providerManifestCallbackId(gpa, started.manifest_json, "bridge-demo", "oauth.refreshToken");
    defer gpa.free(refresh_id);
    const key_id = try providerManifestCallbackId(gpa, started.manifest_json, "bridge-demo", "oauth.getApiKey");
    defer gpa.free(key_id);
    const nested_id = try providerManifestCallbackId(gpa, started.manifest_json, "bridge-demo", "nested.methods.0");
    defer gpa.free(nested_id);
    const reject_id = try providerManifestCallbackId(gpa, started.manifest_json, "bridge-demo", "oauth.rejectRefresh");
    defer gpa.free(reject_id);
    const abort_id = try providerManifestCallbackId(gpa, started.manifest_json, "bridge-demo", "oauth.waitForAbort");
    defer gpa.free(abort_id);

    const refreshed = try started.runtime.invokeProviderMethod(refresh_id, "[{\"refresh\":\"refresh-value\"}]", true, null);
    defer gpa.free(refreshed);
    try std.testing.expect(std.mem.indexOf(u8, refreshed, "closure-181:oauth-owner:refresh-value") != null);
    try std.testing.expect(std.mem.indexOf(u8, refreshed, "\"expires\":181") != null);

    const key = try started.runtime.invokeProviderMethod(key_id, "[{\"access\":\"access-value\"}]", false, null);
    defer gpa.free(key);
    try std.testing.expectEqualStrings("{\"value\":\"closure-181:access-value\"}", key);

    const nested = try started.runtime.invokeProviderMethod(nested_id, "[\"array-value\"]", false, null);
    defer gpa.free(nested);
    try std.testing.expectEqualStrings("{\"value\":\"1:closure-181:array-value\"}", nested);

    try std.testing.expectError(
        error.JavaScriptExtensionExecutionFailed,
        started.runtime.invokeProviderMethod(reject_id, "[]", false, null),
    );
    try std.testing.expect(started.runtime.lastError() != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "provider-refresh-exploded-181") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "rejectRefresh") != null);

    const AbortTask = struct {
        fn run(task_io: Io, flag: *bool) Io.Cancelable!void {
            const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(40), .clock = .awake } };
            try pause.sleep(task_io);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var aborted = false;
    var group: Io.Group = .init;
    group.async(io, AbortTask.run, .{ io, &aborted });
    try std.testing.expectError(
        error.JavaScriptExtensionExecutionFailed,
        started.runtime.invokeProviderMethod(abort_id, "[{}]", true, &aborted),
    );
    try group.await(io);
    try std.testing.expect(started.runtime.lastError() != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "Operation aborted") != null);

    const replacement = try started.runtime.invokeCommand("replace-provider", "", "{}");
    defer gpa.free(replacement);
    const replacement_refresh_id = try providerActionCallbackId(gpa, replacement, "bridge-demo", "oauth.refreshToken");
    defer gpa.free(replacement_refresh_id);
    try std.testing.expect(!std.mem.eql(u8, refresh_id, replacement_refresh_id));
    try std.testing.expect(std.mem.indexOf(u8, replacement, "Renamed Bridge Provider") != null);

    // Both generations remain live through the native action handoff window.
    const old_generation = try started.runtime.invokeProviderMethod(refresh_id, "[{\"refresh\":\"old-generation\"}]", true, null);
    defer gpa.free(old_generation);
    try std.testing.expect(std.mem.indexOf(u8, old_generation, "old-generation") != null);
    const new_generation = try started.runtime.invokeProviderMethod(replacement_refresh_id, "[{\"refresh\":\"new-generation\"}]", true, null);
    defer gpa.free(new_generation);
    try std.testing.expect(std.mem.indexOf(u8, new_generation, "new-generation") != null);
    try started.runtime.commitProviderCallbacks("bridge-demo", &.{replacement_refresh_id});
    try std.testing.expectError(
        error.JavaScriptExtensionExecutionFailed,
        started.runtime.invokeProviderMethod(refresh_id, "[{\"refresh\":\"retired-generation\"}]", true, null),
    );
    try std.testing.expect(started.runtime.lastError() != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "unknown or unloaded provider callback") != null);

    const rejected_registration = try started.runtime.invokeCommand("cycle-provider", "", "{}");
    defer gpa.free(rejected_registration);
    try std.testing.expect(std.mem.indexOf(u8, rejected_registration, "contains a cycle") != null);
    const after_rejection = try started.runtime.invokeProviderMethod(replacement_refresh_id, "[{\"refresh\":\"after-rejection\"}]", true, null);
    defer gpa.free(after_rejection);
    try std.testing.expect(std.mem.indexOf(u8, after_rejection, "after-rejection") != null);

    const unregistered = try started.runtime.invokeCommand("unregister-provider", "", "{}");
    defer gpa.free(unregistered);
    try std.testing.expect(std.mem.indexOf(u8, unregistered, "unregister") != null);
    try std.testing.expectError(
        error.JavaScriptExtensionExecutionFailed,
        started.runtime.invokeProviderMethod(refresh_id, "[{}]", true, null),
    );
    try std.testing.expect(started.runtime.lastError() != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "unknown or unloaded provider callback") != null);

    const ping = try started.runtime.invokeCommand("provider-ping", "", "{}");
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "provider-worker-reused") != null);
}

test "provider OAuth login uses a human interaction timeout distinct from ordinary callbacks" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerProvider('timeout-oauth', {
        \\    name: 'Timeout OAuth', baseUrl: 'https://timeout.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'timeout-model', name: 'Timeout Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      async login(callbacks) {
        \\        if (!(callbacks.signal instanceof AbortSignal)) throw new Error('missing OAuth signal');
        \\        await new Promise((resolve) => setTimeout(resolve, 80));
        \\        return { refresh: 'timeout-refresh', access: 'timeout-access', expires: 9999999999999 };
        \\      },
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "timeout-oauth.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "timeout-oauth.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 10;
    started.runtime.oauth_login_timeout_ms = 1000;
    const login_id = try providerManifestCallbackId(gpa, started.manifest_json, "timeout-oauth", "oauth.login");
    defer gpa.free(login_id);

    const result = try started.runtime.invokeProviderOAuthLogin(login_id, null, null);
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "timeout-access") != null);
    try std.testing.expectEqual(@as(u64, 10), started.runtime.timeout_ms);
}

test "command and shortcut contexts expose reload as an ordered native action" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerCommand('reload-command', { handler: async (_args, ctx) => { await ctx.reload(); } });
        \\  pi.registerShortcut('ctrl+r', { handler: async (ctx) => { await ctx.reload(); } });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "reload.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "reload.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);

    const command = try started.runtime.invokeCommand("reload-command", "", "{}");
    defer gpa.free(command);
    try std.testing.expect(std.mem.indexOf(u8, command, "\"type\":\"reload\"") != null);

    const shortcut = try started.runtime.invokeShortcut("ctrl+r", "{}");
    defer gpa.free(shortcut);
    try std.testing.expect(std.mem.indexOf(u8, shortcut, "\"type\":\"reload\"") != null);
}

test "TypeScript package entrypoints below node_modules bypass Node stripping restriction" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "node_modules/package-155");
    try tmp.dir.writeFile(io, .{
        .sub_path = "node_modules/package-155/package.json",
        .data = "{\"name\":\"package-155\",\"version\":\"1.0.0\"}\n",
    });
    const source =
        \\import { Type } from '@earendil-works/pi-ai';
        \\import { defineTool, type ExtensionAPI } from '@earendil-works/pi-coding-agent';
        \\enum Marker { Value = 'node-modules-ts-ok' }
        \\export default function(pi: ExtensionAPI) {
        \\  pi.registerTool(defineTool({
        \\    name: 'package155',
        \\    description: Marker.Value,
        \\    parameters: Type.Object({ value: Type.String() }),
        \\    async execute(_id, params) { return { content: [{ type: 'text', text: `${Marker.Value}:${params.value}` }], details: {} }; }
        \\  }));
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/package-155/index.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "node_modules", "package-155", "index.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try std.testing.expect(std.mem.indexOf(u8, started.manifest_json, "\"package155\"") != null);
    const result = try started.runtime.invokeTool("package155", "{\"value\":\"pass\"}", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "node-modules-ts-ok:pass") != null);
}

test "JavaScript runtime ignores ordinary stdout before protocol records" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  process.stdout.write('extension-noise');
        \\  pi.registerCommand('noise', { handler: async (_args, ctx) => { process.stdout.write('command-noise'); ctx.ui.notify('clean'); } });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "noise.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "noise.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const result = try started.runtime.invokeCommand("noise", "", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "clean") != null);
}

test "hung JavaScript extension invocation is terminated at the runtime deadline" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerCommand('hang', { handler: async () => await new Promise(() => {}) });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "hang.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "hang.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 100;
    try std.testing.expectError(error.JavaScriptExtensionTimeout, started.runtime.invokeCommand("hang", "", "{}"));
    try std.testing.expect(started.runtime.closed);
}

test "runtime teardown force-reaps extensions that ignore SIGTERM" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\process.on('SIGTERM', () => {});
        \\export default function(pi) {
        \\  pi.registerCommand('ready', { handler: async (_args, ctx) => ctx.ui.notify('ready') });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "ignore-term.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "ignore-term.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer gpa.free(started.manifest_json);
    const result = try started.runtime.invokeCommand("ready", "", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ready") != null);
    started.runtime.deinit();
}

test "script tool receives exact call ID and live AbortSignal" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerCommand('after-abort', { handler: async (_args, ctx) => ctx.ui.notify('worker-reused') });
        \\  pi.registerTool({
        \\    name: 'abort-aware', description: 'abort aware', parameters: { type: 'object', properties: {} },
        \\    async execute(id, _params, signal, onUpdate, ctx) {
        \\      onUpdate({ content: [{ type: 'text', text: `id=${id};same=${signal === ctx.signal};aborted=${signal.aborted}` }] });
        \\      await new Promise((resolve, reject) => {
        \\        if (signal.aborted) { reject(signal.reason); return; }
        \\        const timer = setTimeout(() => reject(new Error('abort signal was not delivered')), 1500);
        \\        signal.addEventListener('abort', () => { clearTimeout(timer); reject(signal.reason); }, { once: true });
        \\      });
        \\      return { content: [{ type: 'text', text: 'unreachable' }] };
        \\    }
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "abort.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "abort.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 5000;

    const Probe = struct {
        abort_flag: *bool,
        count: usize = 0,
        saw_exact_id: bool = false,
        saw_same_signal: bool = false,

        fn update(raw_ctx: ?*anyopaque, raw: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw_ctx.?));
            self.count += 1;
            self.saw_exact_id = std.mem.indexOf(u8, raw, "call-exact-152") != null;
            self.saw_same_signal = std.mem.indexOf(u8, raw, "same=true") != null and
                std.mem.indexOf(u8, raw, "aborted=false") != null;
            @atomicStore(bool, self.abort_flag, true, .release);
        }
    };

    var aborted = false;
    var probe = Probe{ .abort_flag = &aborted };
    const result = try started.runtime.invokeToolCallStreaming(
        "call-exact-152",
        "abort-aware",
        "{}",
        "{}",
        &aborted,
        Probe.update,
        &probe,
    );
    defer gpa.free(result);

    try std.testing.expectEqual(@as(usize, 1), probe.count);
    try std.testing.expect(probe.saw_exact_id);
    try std.testing.expect(probe.saw_same_signal);
    try std.testing.expect(std.mem.indexOf(u8, result, "Tool execution aborted: Operation aborted") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"aborted\\\":true") != null or
        std.mem.indexOf(u8, result, "\"aborted\":true") != null);

    // Cooperative cancellation must settle the promise without poisoning the
    // persistent worker or leaving the abort control record queued.
    const reused = try started.runtime.invokeCommand("after-abort", "", "{}");
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "worker-reused") != null);
}

test "lifecycle hook context receives live abort signal and worker remains reusable" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.on('before_prompt', async (_event, ctx) => {
        \\    if (!ctx.signal) throw new Error('missing lifecycle signal');
        \\    await new Promise((resolve, reject) => {
        \\      if (ctx.signal.aborted) { reject(ctx.signal.reason); return; }
        \\      const timer = setTimeout(() => reject(new Error('lifecycle abort signal was not delivered')), 1500);
        \\      ctx.signal.addEventListener('abort', () => { clearTimeout(timer); reject(ctx.signal.reason); }, { once: true });
        \\    });
        \\  });
        \\  pi.registerCommand('after-hook-abort', { handler: async (_args, ctx) => ctx.ui.notify('hook-worker-reused') });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "hook-abort.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "hook-abort.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 5000;

    const AbortTask = struct {
        fn run(task_io: Io, flag: *bool) Io.Cancelable!void {
            const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(40), .clock = .awake } };
            try pause.sleep(task_io);
            @atomicStore(bool, flag, true, .release);
        }
    };

    var aborted = false;
    var group: Io.Group = .init;
    group.async(io, AbortTask.run, .{ io, &aborted });
    try std.testing.expectError(
        error.JavaScriptExtensionExecutionFailed,
        started.runtime.invokeHookWithAbort("before_prompt", "{\"prompt\":\"cancel me\"}", "{}", &aborted),
    );
    try group.await(io);
    try std.testing.expect(started.runtime.last_error != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.last_error.?, "Operation aborted") != null);

    const reused = try started.runtime.invokeCommand("after-hook-abort", "", "{}");
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "hook-worker-reused") != null);
}

test "script UI requests round-trip through native bridge and retain synchronous actions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    const FakeUi = struct {
        request_count: usize = 0,
        action_count: usize = 0,
        saw_status: bool = false,
        saw_widget: bool = false,
        saw_title: bool = false,
        saw_editor: bool = false,

        fn request(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.request_count += 1;
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
            defer parsed.deinit();
            try std.testing.expect(parsed.value == .object);
            if (std.mem.eql(u8, method, "select")) return allocator.dupe(u8, "\"green\"");
            if (std.mem.eql(u8, method, "confirm")) return allocator.dupe(u8, "true");
            if (std.mem.eql(u8, method, "input")) return allocator.dupe(u8, "\"Ada\"");
            if (std.mem.eql(u8, method, "editor")) return allocator.dupe(u8, "\"edited\"");
            if (std.mem.eql(u8, method, "custom")) return allocator.dupe(u8, "\"closed\"");
            return allocator.dupe(u8, "null");
        }

        fn action(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.action_count += 1;
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
            defer parsed.deinit();
            try std.testing.expect(parsed.value == .object);
            if (std.mem.eql(u8, method, "setStatus")) self.saw_status = true;
            if (std.mem.eql(u8, method, "setWidget")) self.saw_widget = true;
            if (std.mem.eql(u8, method, "setTitle")) self.saw_title = true;
            if (std.mem.eql(u8, method, "setEditorText")) self.saw_editor = true;
        }
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { Text } from '@earendil-works/pi-tui';
        \\export default function(pi) {
        \\  pi.registerCommand('ui-roundtrip', { handler: async (_args, ctx) => {
        \\    const selected = await ctx.ui.select('Color', ['red', 'green']);
        \\    const confirmed = await ctx.ui.confirm('Confirm', 'Continue?');
        \\    const input = await ctx.ui.input('Name', 'placeholder');
        \\    const edited = await ctx.ui.editor('Edit', 'prefill');
        \\    const custom = await ctx.ui.custom(() => new Text('custom view'));
        \\    ctx.ui.setStatus('mode', 'active');
        \\    ctx.ui.setWidget('widget', () => new Text('widget line'));
        \\    ctx.ui.setHeader(() => new Text('header line'));
        \\    ctx.ui.setFooter(() => new Text('footer line'));
        \\    ctx.ui.setTitle('Pi UI');
        \\    ctx.ui.setEditorText('next prompt');
        \\    return { message: JSON.stringify({ selected, confirmed, input, edited, custom, mode: ctx.mode, cwd: ctx.cwd, editor: ctx.ui.getEditorText() }) };
        \\  }});
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "ui.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "ui.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    var fake = FakeUi{};
    started.runtime.setUiBridge(.{ .context = &fake, .request_fn = FakeUi.request, .action_fn = FakeUi.action });
    try started.runtime.setContextJson("{\"mode\":\"tui\",\"hasUI\":true,\"cwd\":\"/workspace\",\"editorText\":\"before\"}");

    const result = try started.runtime.invokeCommand("ui-roundtrip", "", "{}");
    defer gpa.free(result);
    try std.testing.expectEqual(@as(usize, 5), fake.request_count);
    try std.testing.expect(fake.action_count >= 6);
    try std.testing.expect(fake.saw_status and fake.saw_widget and fake.saw_title and fake.saw_editor);
    try std.testing.expect(std.mem.indexOf(u8, result, "green") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Ada") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "edited") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "closed") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "workspace") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "next prompt") != null);
}

test "streaming tool updates arrive before the JavaScript promise resolves" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { writeFileSync } from 'node:fs';
        \\export default function(pi) {
        \\  pi.registerTool({
        \\    name: 'live-progress', description: 'live progress', parameters: { type: 'object', properties: { marker: { type: 'string' } }, required: ['marker'] },
        \\    async execute(_id, params, _signal, onUpdate) {
        \\      onUpdate({ content: [{ type: 'text', text: 'first-live' }], details: { sequence: 1 } });
        \\      await new Promise(resolve => setTimeout(resolve, 120));
        \\      writeFileSync(params.marker, 'done');
        \\      return { content: [{ type: 'text', text: 'complete-live' }], details: { sequence: 2 } };
        \\    }
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "live.ts", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const source_path = try std.fs.path.join(gpa, &.{ root_buf[0..root_len], "live.ts" });
    defer gpa.free(source_path);
    const marker_path = try std.fs.path.join(gpa, &.{ root_buf[0..root_len], "resolved.marker" });
    defer gpa.free(marker_path);

    var started = try Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);

    var payload: std.Io.Writer.Allocating = .init(gpa);
    defer payload.deinit();
    try payload.writer.writeAll("{\"marker\":");
    try std.json.Stringify.value(marker_path, .{}, &payload.writer);
    try payload.writer.writeByte('}');

    const Probe = struct {
        io: Io,
        marker: []const u8,
        count: usize = 0,
        saw_before_resolution: bool = false,
        saw_payload: bool = false,

        fn update(raw_ctx: ?*anyopaque, raw: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw_ctx.?));
            self.count += 1;
            self.saw_payload = std.mem.indexOf(u8, raw, "first-live") != null and
                std.mem.indexOf(u8, raw, "\"sequence\":1") != null;
            var resolved = true;
            std.Io.Dir.cwd().access(self.io, self.marker, .{}) catch {
                resolved = false;
            };
            self.saw_before_resolution = !resolved;
        }
    };
    var probe = Probe{ .io = io, .marker = marker_path };
    const result = try started.runtime.invokeToolCallStreaming("call-live-progress", "live-progress", payload.written(), "{}", null, Probe.update, &probe);
    defer gpa.free(result);

    try std.testing.expectEqual(@as(usize, 1), probe.count);
    try std.testing.expect(probe.saw_payload);
    try std.testing.expect(probe.saw_before_resolution);
    try std.testing.expect(std.mem.indexOf(u8, result, "complete-live") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"updates\"") == null);
    try std.Io.Dir.cwd().access(io, marker_path, .{});
}

test "reload invalidates the producing command context and quarantines later actions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerCommand('reload-stale', {
        \\    handler: async (_args, ctx) => {
        \\      await ctx.reload();
        \\      pi.appendEntry('must-not-escape', { stale: true });
        \\      return { prompt: 'must-not-run', sessionName: 'must-not-apply' };
        \\    }
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "reload-stale.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "reload-stale.ts" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);

    const result = try started.runtime.invokeCommand("reload-stale", "", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"type\":\"reload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "append_entry") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "must-not-escape") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "must-not-run") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "staleContextError") != null);
}

test "provider streamSimple crosses the persistent worker with ordered acknowledgements" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { createAssistantMessageEventStream } from '@mariozechner/pi-ai';
        \\const usage = { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, totalTokens: 3, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
        \\const assistant = (content, stopReason = 'pending') => ({ role: 'assistant', content, api: 'custom-stream', provider: 'native-stream', model: 'native-model', usage, stopReason, timestamp: 185 });
        \\export default function(pi) {
        \\  pi.registerProvider('native-stream', {
        \\    name: 'Native Stream', api: 'custom-stream', apiKey: 'local',
        \\    models: [{ id: 'native-model', name: 'Native Model', reasoning: true, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    streamSimple(model, context, options) {
        \\      if (model.id !== 'native-model' || context.marker !== 185 || !(options.signal instanceof AbortSignal)) throw new Error('native stream inputs missing');
        \\      const stream = createAssistantMessageEventStream();
        \\      const partial = assistant([]);
        \\      stream.push({ type: 'start', partial });
        \\      stream.push({ type: 'text_start', contentIndex: 0, partial });
        \\      stream.push({ type: 'thinking_start', contentIndex: 1, partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: 'N', partial });
        \\      stream.push({ type: 'thinking_delta', contentIndex: 1, delta: 'plan', partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: '\uD83D', partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: '\uDE80', partial });
        \\      stream.push({ type: 'thinking_end', contentIndex: 1, content: 'plan', partial });
        \\      stream.push({ type: 'text_end', contentIndex: 0, content: 'N🚀', partial });
        \\      stream.push({ type: 'done', reason: 'stop', message: assistant([{ type: 'text', text: 'N🚀' }, { type: 'thinking', thinking: 'plan' }], 'stop') });
        \\      return stream;
        \\    },
        \\  });
        \\  pi.registerCommand('stream-native-ping', { handler: async (_args, ctx) => ctx.ui.notify('native-stream-worker-reused') });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "provider-stream.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "provider-stream.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const stream_id = try providerManifestCallbackId(gpa, started.manifest_json, "native-stream", "streamSimple");
    defer gpa.free(stream_id);

    const Capture = struct {
        count: u64 = 0,
        saw_empty_surrogate_carry: bool = false,
        saw_rocket: bool = false,
        saw_done: bool = false,
        reject_sequence: ?u64 = null,

        fn consume(raw_context: ?*anyopaque, sequence: u64, event_json: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw_context.?));
            try std.testing.expectEqual(self.count + 1, sequence);
            self.count = sequence;
            if (self.reject_sequence == sequence) return error.DeliberateStreamConsumerRejection;
            if (std.mem.indexOf(u8, event_json, "\"delta\":\"\"") != null) self.saw_empty_surrogate_carry = true;
            if (std.mem.indexOf(u8, event_json, "🚀") != null) self.saw_rocket = true;
            if (std.mem.indexOf(u8, event_json, "\"type\":\"done\"") != null) self.saw_done = true;
        }
    };

    var capture: Capture = .{};
    const summary = try started.runtime.invokeProviderStreamSimple(
        "native-stream",
        stream_id,
        1,
        "{\"id\":\"native-model\",\"provider\":\"native-stream\",\"api\":\"custom-stream\"}",
        "{\"marker\":185,\"messages\":[]}",
        "{\"apiKey\":\"local\",\"maxTokens\":128}",
        null,
        Capture.consume,
        &capture,
    );
    defer gpa.free(summary);
    try std.testing.expect(capture.count >= 10);
    try std.testing.expect(capture.saw_empty_surrogate_carry);
    try std.testing.expect(capture.saw_rocket);
    try std.testing.expect(capture.saw_done);
    try std.testing.expect(std.mem.indexOf(u8, summary, "\"terminal\":\"done\"") != null);

    var rejected_capture: Capture = .{ .reject_sequence = 1 };
    try std.testing.expectError(
        error.JavaScriptExtensionExecutionFailed,
        started.runtime.invokeProviderStreamSimple(
            "native-stream",
            stream_id,
            1,
            "{\"id\":\"native-model\",\"provider\":\"native-stream\",\"api\":\"custom-stream\"}",
            "{\"marker\":185,\"messages\":[]}",
            "{}",
            null,
            Capture.consume,
            &rejected_capture,
        ),
    );
    try std.testing.expect(started.runtime.lastError() != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "DeliberateStreamConsumerRejection") != null);

    const ping = try started.runtime.invokeCommand("stream-native-ping", "", "{}");
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "native-stream-worker-reused") != null);
}

test "provider stream generation retirement drains cooperative iterators and preserves worker reuse" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
        \\const partial = { role: 'assistant', content: [], api: 'retire-api', provider: 'retire-provider', model: 'retire-model', usage, stopReason: 'pending', timestamp: 186 };
        \\export default function(pi) {
        \\  pi.registerProvider('retire-provider', {
        \\    name: 'Retire Provider', api: 'retire-api', apiKey: 'local',
        \\    models: [{ id: 'retire-model', name: 'Retire Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    streamSimple() {
        \\      let first = true;
        \\      return {
        \\        [Symbol.asyncIterator]() { return this; },
        \\        next() { if (first) { first = false; return Promise.resolve({ done: false, value: { type: 'start', partial } }); } return new Promise(() => {}); },
        \\        return() { return Promise.resolve({ done: true }); },
        \\      };
        \\    },
        \\  });
        \\  pi.registerCommand('after-retire', { handler: async (_args, ctx) => ctx.ui.notify('retired-worker-reused') });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "retire-provider.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "retire-provider.mjs" });
    defer gpa.free(path);

    var started = try Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const stream_id = try providerManifestCallbackId(gpa, started.manifest_json, "retire-provider", "streamSimple");
    defer gpa.free(stream_id);

    const Invocation = struct {
        runtime: *Runtime,
        callback_id: []const u8,
        output: ?[]u8 = null,
        failure: ?anyerror = null,
        events: u64 = 0,

        fn consume(raw: ?*anyopaque, _: u64, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.events += 1;
        }

        fn run(self: *@This()) void {
            self.output = self.runtime.invokeProviderStreamSimple(
                "retire-provider",
                self.callback_id,
                1,
                "{\"id\":\"retire-model\",\"provider\":\"retire-provider\",\"api\":\"retire-api\"}",
                "{\"messages\":[]}",
                "{}",
                null,
                consume,
                self,
            ) catch |err| {
                self.failure = err;
                return;
            };
        }
    };

    var invocation = Invocation{ .runtime = started.runtime, .callback_id = stream_id };
    defer if (invocation.output) |output| gpa.free(output);
    var group: Io.Group = .init;
    group.async(io, Invocation.run, .{&invocation});
    var waited_ms: u64 = 0;
    while (!@atomicLoad(bool, &started.runtime.active_provider_stream, .acquire) and waited_ms < 1_000) : (waited_ms += 5) {
        const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(5), .clock = .awake } };
        try pause.sleep(io);
    }
    try std.testing.expect(@atomicLoad(bool, &started.runtime.active_provider_stream, .acquire));
    try std.testing.expect(started.runtime.retireProviderGeneration("retire-provider", 1, 1_000));
    try group.await(io);
    try std.testing.expectEqual(@as(u64, 1), invocation.events);
    try std.testing.expectEqual(error.JavaScriptExtensionExecutionFailed, invocation.failure.?);

    const ping = try started.runtime.invokeCommand("after-retire", "", "{}");
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "retired-worker-reused") != null);
}

test "provider stream retirement force-closes only the worker whose iterator ignores return" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const hostile_source =
        \\const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
        \\const partial = { role: 'assistant', content: [], api: 'hostile-api', provider: 'hostile-provider', model: 'hostile-model', usage, stopReason: 'pending', timestamp: 186 };
        \\export default function(pi) {
        \\  pi.registerProvider('hostile-provider', {
        \\    name: 'Hostile Provider', api: 'hostile-api', apiKey: 'local',
        \\    models: [{ id: 'hostile-model', name: 'Hostile Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    streamSimple() {
        \\      let first = true;
        \\      return {
        \\        [Symbol.asyncIterator]() { return this; },
        \\        next() { if (first) { first = false; return Promise.resolve({ done: false, value: { type: 'start', partial } }); } return new Promise(() => {}); },
        \\        return() { return new Promise(() => {}); },
        \\      };
        \\    },
        \\  });
        \\}
    ;
    const healthy_source =
        \\export default function(pi) { pi.registerCommand('healthy-ping', { handler: async (_args, ctx) => ctx.ui.notify('healthy-worker-reused') }); }
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "hostile-provider.mjs", .data = hostile_source });
    try tmp.dir.writeFile(io, .{ .sub_path = "healthy-worker.mjs", .data = healthy_source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const hostile_path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "hostile-provider.mjs" });
    defer gpa.free(hostile_path);
    const healthy_path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "healthy-worker.mjs" });
    defer gpa.free(healthy_path);

    var hostile = try Runtime.start(gpa, io, hostile_path, "node");
    defer hostile.runtime.deinit();
    defer gpa.free(hostile.manifest_json);
    var healthy = try Runtime.start(gpa, io, healthy_path, "node");
    defer healthy.runtime.deinit();
    defer gpa.free(healthy.manifest_json);
    const stream_id = try providerManifestCallbackId(gpa, hostile.manifest_json, "hostile-provider", "streamSimple");
    defer gpa.free(stream_id);

    const Invocation = struct {
        runtime: *Runtime,
        callback_id: []const u8,
        failure: ?anyerror = null,

        fn consume(_: ?*anyopaque, _: u64, _: []const u8) !void {}

        fn run(self: *@This()) void {
            const output = self.runtime.invokeProviderStreamSimple(
                "hostile-provider",
                self.callback_id,
                1,
                "{\"id\":\"hostile-model\",\"provider\":\"hostile-provider\",\"api\":\"hostile-api\"}",
                "{\"messages\":[]}",
                "{}",
                null,
                consume,
                null,
            ) catch |err| {
                self.failure = err;
                return;
            };
            self.runtime.gpa.free(output);
        }
    };

    var invocation = Invocation{ .runtime = hostile.runtime, .callback_id = stream_id };
    var group: Io.Group = .init;
    group.async(io, Invocation.run, .{&invocation});
    var waited_ms: u64 = 0;
    while (!@atomicLoad(bool, &hostile.runtime.active_provider_stream, .acquire) and waited_ms < 1_000) : (waited_ms += 5) {
        const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(5), .clock = .awake } };
        try pause.sleep(io);
    }
    try std.testing.expect(@atomicLoad(bool, &hostile.runtime.active_provider_stream, .acquire));
    try std.testing.expect(hostile.runtime.retireProviderGeneration("hostile-provider", 1, 1_000));
    try group.await(io);
    try std.testing.expectEqual(error.JavaScriptExtensionExecutionFailed, invocation.failure.?);
    try std.testing.expect(hostile.runtime.closed);
    try std.testing.expect(hostile.runtime.lastError() != null);
    try std.testing.expect(std.mem.indexOf(u8, hostile.runtime.lastError().?, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT") != null);

    const ping = try healthy.runtime.invokeCommand("healthy-ping", "", "{}");
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "healthy-worker-reused") != null);
}
