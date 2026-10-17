//! Genuine native AsyncFunction mkdir: owner validation, Env worker filesystem
//! calls, intrinsic PromiseThen and real VM Await. No mkdirSync dispatch.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const af = async_body.native;
const async_body = @import("native_async_body.zig");
const hub = @import("native_env_io.zig");
const metadata = @import("node_fs_metadata.zig");
const url = @import("native_url.zig");
const maximum_pending = 64;
var pending_workers: std.atomic.Value(u32) = .init(0);
const exits = @import("native_node_fs_mkdir_exit.zig");
fn release(engine: *js.Engine, owned: c.JSValue) void { exits.release(engine, owned); }
fn recordFailure(engine: *js.Engine, err: anyerror) void {
    const frame = exits.active(engine) orelse return;
    if (url.isFilePathError(err) and frame.chosen == null and !c.JS_HasException(engine.context)) {
        frame.adoptFailureValue(url.filePathErrorValue(engine, err));
    } else frame.record(err);
}
fn checked(engine: *js.Engine, result: anytype) anyerror!@typeInfo(@TypeOf(result)).error_union.payload {
    return result catch |err| { recordFailure(engine, err); return error.JavaScriptException; };
}

fn pending(engine: *js.Engine) !void {
    return exits.pending(engine);
}
fn value(engine: *js.Engine, raw: c.JSValue) !c.JSValue {
    return exits.value(engine, raw);
}
fn get(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    try pending(engine); exits.before(engine); return value(engine, c.JS_GetPropertyStr(engine.context, object, name));
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn raise(engine: *js.Engine, kind: [*:0]const u8, code: []const u8, message: []const u8) anyerror {
    const constructor = get(engine, engine.intrinsic_clone_operations, kind) catch |err| return err;
    defer release(engine, constructor);
    const reason = value(engine, c.JS_CallConstructor(engine.context, constructor, 0, null)) catch |err| return err;
    defer release(engine, reason);
    inline for (.{ "code", "message" }, .{ code, message }) |key, text| {
        const text_value = value(engine, c.JS_NewStringLen(engine.context, text.ptr, text.len)) catch |err| return err;
        const status = c.JS_DefinePropertyValueStr(engine.context, reason, key, text_value, if (std.mem.eql(u8, key, "message")) c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE else c.JS_PROP_C_W_E);
        pending(engine) catch |err| return err;
        if (status < 0) return exits.capture(engine);
    }
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    return exits.capture(engine);
}
fn parseMode(engine: *js.Engine, input: c.JSValue) !u32 {
    if (c.JS_IsUndefined(input) or c.JS_IsNull(input)) return 0o777;
    var number: f64 = 0;
    if (c.JS_IsString(input)) {
        const text = try checked(engine, engine.toString(input)); defer engine.gpa.free(text); try pending(engine);
        if (text.len == 0) return raise(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The argument 'mode' must be a 32-bit unsigned integer or an octal string");
        for (text) |byte| if (byte < '0' or byte > '7') return raise(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The argument 'mode' must be a 32-bit unsigned integer or an octal string");
        for (text) |byte| { number = number * 8 + @as(f64, @floatFromInt(byte - '0')); }
    } else {
        if (!c.JS_IsNumber(input)) return raise(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The mode argument must be of type number");
        if (c.JS_ToFloat64(engine.context, &number, input) < 0) return exits.capture(engine);
        try pending(engine);
    }
    if (!std.math.isFinite(number) or @trunc(number) != number or number < 0 or number > std.math.maxInt(u32)) return raise(engine, "RangeError", "ERR_OUT_OF_RANGE", "The mode argument must be an integer >= 0 and <= 4294967295");
    return @intFromFloat(number);
}
const Parameters = struct { path: []u8, mode: u32, recursive: bool };
fn parameters(engine: *js.Engine, args: []const c.JSValue) !Parameters {
    const options = arg(args, 1);
    const mode_shortcut = c.JS_IsNumber(options) or c.JS_IsString(options);
    // Source destructures recursive THEN mode before validating the path.
    const recursive = if (!mode_shortcut and c.JS_ToBool(engine.context, options) == 1) try get(engine, options, "recursive") else c.pi_js_undefined();
    defer release(engine, recursive);
    const mode = if (mode_shortcut) c.JS_DupValue(engine.context, options) else if (c.JS_ToBool(engine.context, options) == 1) try get(engine, options, "mode") else c.pi_js_undefined();
    defer release(engine, mode);
    exits.before(engine);
    const path = try checked(engine, metadata.pathTextNamed(engine, arg(args, 0), false, "path")); errdefer engine.gpa.free(path);
    try pending(engine);
    if (!c.JS_IsUndefined(recursive) and !c.JS_IsBool(recursive)) return raise(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The options.recursive property must be of type boolean");
    return .{ .path = path, .mode = try parseMode(engine, mode), .recursive = c.JS_ToBool(engine.context, recursive) == 1 };
}
fn reserve() !void {
    var observed = pending_workers.load(.acquire);
    while (observed < maximum_pending) {
        if (pending_workers.cmpxchgWeak(observed, observed + 1, .acq_rel, .acquire)) |actual| observed = actual else return;
    }
    return error.NativeFsMkdirCapacity;
}

/// Entire worker payload is native: stable bytes, offsets, options and result.
/// No guest value/coercion, allocator call or user callback occurs in run().
const Packet = struct {
    io: std.Io,
    path: []u8,
    recursive: bool,
    mode: u32,
    ancestors: []usize,
    stop: std.atomic.Value(bool) = .init(false),
    first: ?usize = null,
    failure: ?anyerror = null,
    failed_length: usize = 0,
    fn run(self: *Packet) void {
        self.perform() catch |err| { self.failure = err; };
    }
    fn perform(self: *Packet) !void {
        const permissions: std.Io.Dir.Permissions = if (builtin.os.tag == .windows) .default_dir else .fromMode(@truncate(self.mode));
        var cursor: usize = 0;
        while (true) {
            if (self.stop.load(.acquire)) return error.Canceled;
            const path = self.path[0..self.ancestors[cursor]];
            self.failed_length = path.len;
            if (path.len == 0) return error.FileNotFound;
            if (std.Io.Dir.cwd().createDir(self.io, path, permissions)) |_| {
                if (!self.recursive) return;
                if (self.first == null) self.first = path.len;
            } else |original| {
                if (!self.recursive) return original;
                switch (original) {
                    error.Canceled, error.AccessDenied, error.PermissionDenied, error.NoSpaceLeft, error.NotDir => return original,
                    error.FileNotFound => {
                        if (cursor + 1 >= self.ancestors.len) return original;
                        cursor += 1; continue;
                    },
                    else => {},
                }
                if (self.stop.load(.acquire)) return error.Canceled;
                const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = true }) catch |err| {
                    if (err == error.Canceled) return err;
                    return if (original == error.PathAlreadyExists and cursor > 0) error.NotDir else err;
                };
                if (stat.kind != .directory) return if (original == error.PathAlreadyExists and cursor > 0) error.NotDir else error.PathAlreadyExists;
            }
            if (cursor == 0) return;
            cursor -= 1;
        }
    }
};
const Request = struct {
    task: hub.Task,
    packet: Packet,
    resolvers_released: bool = false,
    fn work(base: *hub.Task) void {
        const self: *Request = @alignCast(@fieldParentPtr("task", base));
        self.packet.run(); base.finish();
    }
    fn cancel(base: *hub.Task) void {
        const self: *Request = @alignCast(@fieldParentPtr("task", base)); self.packet.stop.store(true, .release);
    }
    fn complete(base: *hub.Task) !void {
        const engine = base.hub.engine;
        const self: *Request = @alignCast(@fieldParentPtr("task", base));
        var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
        // Entry pending completion aborts BEFORE result/error construction or
        // either resolver. An ordinary error born inside completion can reject.
        const clean_entry = if (frame.check()) |_| true else |_| false;
        if (clean_entry) completeValue(base) catch |err| {
            recordFailure(engine, err);
            if (frame.takeOrdinary()) |reason| {
                defer release(engine, reason);
                checked(engine, base.settled(true, reason)) catch {};
                frame.check() catch {};
            }
        };
        // Resolver finalizers run inside the SAME escrow before Hub gets its
        // return/error. The later Hub-deferred destroy then frees native data.
        releaseResolvers(self);
        return frame.finishVoid();
    }
    fn completeValue(base: *hub.Task) !void {
        const self: *Request = @alignCast(@fieldParentPtr("task", base)); const engine = base.hub.engine;
        if (self.packet.failure) |err| {
            const reason = try filesystemError(engine, err, self.packet.path[0..self.packet.failed_length]); defer release(engine, reason);
            exits.before(engine); try checked(engine, base.settled(true, reason)); try pending(engine);
        } else {
            const result = if (self.packet.first) |length| try value(engine, c.JS_NewStringLen(engine.context, self.packet.path.ptr, length)) else c.pi_js_undefined();
            defer release(engine, result); exits.before(engine); try checked(engine, base.settled(false, result)); try pending(engine);
        }
    }
    fn destroy(base: *hub.Task) void {
        const self: *Request = @alignCast(@fieldParentPtr("task", base)); const engine = base.hub.engine;
        if (!self.resolvers_released) {
            var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
            releaseResolvers(self);
            // Abandoned teardown has no Promise callback; leave the actual
            // completion pending, retaining first-fatal priority, for its host.
            frame.finishVoid() catch {};
        }
        engine.gpa.free(self.packet.path); engine.gpa.free(self.packet.ancestors);
        engine.gpa.destroy(self);
        _ = pending_workers.fetchSub(1, .acq_rel);
    }
    fn releaseResolvers(self: *Request) void {
        if (self.resolvers_released) return;
        self.resolvers_released = true;
        const resolve = self.task.resolve; const reject = self.task.reject;
        self.task.resolve = c.pi_js_undefined(); self.task.reject = c.pi_js_undefined();
        release(self.task.hub.engine, resolve); release(self.task.hub.engine, reject);
    }
};

fn filesystemError(engine: *js.Engine, err: anyerror, original: []const u8) !c.JSValue {
    const Info = struct { code: []const u8, detail: []const u8, posix: i32, windows: i32 };
    const info: Info = switch (err) {
        error.FileNotFound, error.NetworkNotFound => .{ .code = "ENOENT", .detail = "no such file or directory", .posix = -2, .windows = -4058 },
        error.PathAlreadyExists => .{ .code = "EEXIST", .detail = "file already exists", .posix = -17, .windows = -4075 },
        error.NotDir => .{ .code = "ENOTDIR", .detail = "not a directory", .posix = -20, .windows = -4052 },
        error.AccessDenied => .{ .code = "EACCES", .detail = "permission denied", .posix = -13, .windows = -4092 },
        error.PermissionDenied => .{ .code = "EPERM", .detail = "operation not permitted", .posix = -1, .windows = -4048 },
        error.NoSpaceLeft => .{ .code = "ENOSPC", .detail = "no space left on device", .posix = -28, .windows = -4055 },
        error.ReadOnlyFileSystem => .{ .code = "EROFS", .detail = "read-only file system", .posix = -30, .windows = -4043 },
        error.BadPathName => .{ .code = "EINVAL", .detail = "invalid argument", .posix = -22, .windows = -4071 },
        error.SystemResources => .{ .code = "ENOMEM", .detail = "not enough memory", .posix = -12, .windows = -4057 },
        error.LinkQuotaExceeded => .{ .code = "EMLINK", .detail = "too many links", .posix = -31, .windows = -4032 },
        error.NoDevice => .{ .code = "ENODEV", .detail = "no such device", .posix = -19, .windows = -4059 },
        error.NameTooLong => .{ .code = "ENAMETOOLONG", .detail = "name too long", .posix = -36, .windows = -4064 },
        error.SymLinkLoop => .{ .code = "ELOOP", .detail = "too many symbolic links encountered", .posix = -40, .windows = -4067 },
        error.Canceled => .{ .code = "ECANCELED", .detail = "operation canceled", .posix = -125, .windows = -4081 },
        else => return err,
    };
    const path = if (builtin.os.tag == .windows and std.mem.startsWith(u8, original, "\\\\?\\UNC\\")) try checked(engine, std.fmt.allocPrint(engine.gpa, "\\\\{s}", .{original[8..]})) else if (builtin.os.tag == .windows and std.mem.startsWith(u8, original, "\\\\?\\")) try checked(engine, engine.gpa.dupe(u8, original[4..])) else try checked(engine, engine.gpa.dupe(u8, original));
    defer engine.gpa.free(path);
    const message = try checked(engine, std.fmt.allocPrint(engine.gpa, "{s}: {s}, mkdir '{s}'", .{ info.code, info.detail, path })); defer engine.gpa.free(message);
    const reason = try value(engine, c.JS_NewError(engine.context)); errdefer release(engine, reason);
    const texts = [_][]const u8{message, info.code, "mkdir", path};
    inline for (.{ "message", "code", "syscall", "path" }, 0..) |key, index| {
        const text = try value(engine, c.JS_NewStringLen(engine.context, texts[index].ptr, texts[index].len));
        const status = c.JS_DefinePropertyValueStr(engine.context, reason, key, text, if (index == 0) c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE else c.JS_PROP_C_W_E);
        try pending(engine); if (status < 0) return exits.capture(engine);
    }
    if (c.JS_DefinePropertyValueStr(engine.context, reason, "errno", c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) info.windows else info.posix), c.JS_PROP_C_W_E) < 0) return exits.capture(engine);
    return reason;
}

fn submit(engine: *js.Engine, parsed: Parameters) !c.JSValue {
    var parsed_owned = true; defer if (parsed_owned) engine.gpa.free(parsed.path);
    const native_path = if (builtin.os.tag == .windows) try checked(engine, @import("native_file_stat.zig").windowsNamespacedPath(engine.gpa, parsed.path)) else try checked(engine, engine.gpa.dupe(u8, parsed.path));
    var path_owned = true; defer if (path_owned) engine.gpa.free(native_path);
    var ancestors: std.ArrayList(usize) = .empty; defer ancestors.deinit(engine.gpa);
    var length = native_path.len;
    while (true) {
        try checked(engine, ancestors.append(engine.gpa, length));
        if (!parsed.recursive or length == 0) break;
        const previous = if (builtin.os.tag == .windows) std.mem.lastIndexOfAny(u8, native_path[0..length], "/\\") else std.mem.lastIndexOfScalar(u8, native_path[0..length], '/');
        length = previous orelse break;
    }
    const offsets = try checked(engine, ancestors.toOwnedSlice(engine.gpa)); var offsets_owned = true; defer if (offsets_owned) engine.gpa.free(offsets);
    const env = try checked(engine, hub.get(engine));
    try checked(engine, reserve()); var admission_owned = true; defer if (admission_owned) { _ = pending_workers.fetchSub(1, .acq_rel); };
    var resolvers: [2]c.JSValue = undefined;
    const raw_promise = c.JS_NewPromiseCapability(engine.context, &resolvers);
    if (c.JS_IsException(raw_promise)) return exits.capture(engine);
    var functions_owned = true; defer if (functions_owned) { release(engine, resolvers[0]); release(engine, resolvers[1]); };
    const promise = try value(engine, raw_promise);
    errdefer release(engine, promise);
    const request = try checked(engine, engine.gpa.create(Request)); var request_owned = true; defer if (request_owned) engine.gpa.destroy(request);
    request.* = .{ .task = .{ .hub = env, .work = Request.work, .complete = Request.complete, .destroy = Request.destroy, .cancel = Request.cancel, .resolve = resolvers[0], .reject = resolvers[1], .propagate_completion_errors = true }, .packet = .{ .io = env.io, .path = native_path, .recursive = parsed.recursive, .mode = parsed.mode, .ancestors = offsets } };
    try checked(engine, env.submit(&request.task));
    admission_owned = false; functions_owned = false; path_owned = false; offsets_owned = false; request_owned = false;
    // parsed.path is an owner-only validation snapshot; worker uses native_path.
    engine.gpa.free(parsed.path); parsed_owned = false;
    return promise;
}
fn failure(engine: *js.Engine, err: anyerror, _: u64) !af.Action {
    recordFailure(engine, err); return error.JavaScriptException;
}
fn body(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    const action: af.Action = if (frame.check()) |_| bodyInner(engine, args, roots, completion, input) catch |err| failed: { recordFailure(engine, err); break :failed .{ .returned = c.pi_js_undefined() }; } else |_| .{ .returned = c.pi_js_undefined() };
    return frame.finishAction(action);
}
fn bodyInner(engine: *js.Engine, args: []const c.JSValue, roots: []const c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    switch (completion) {
        .fulfilled => return .{ .returned = c.JS_DupValue(engine.context, input) },
        .rejected => return .{ .thrown = c.JS_DupValue(engine.context, input) },
        .start => {},
    }
    const generation = engine.native_allocation_generation;
    pending(engine) catch |err| return failure(engine, err, generation);
    const parsed = parameters(engine, args) catch |err| return failure(engine, err, generation);
    const binding = submit(engine, parsed) catch |err| return failure(engine, err, generation);
    defer release(engine, binding);
    exits.before(engine);
    const chained = value(engine, c.JS_PromiseThen(engine.context, binding, c.pi_js_undefined(), roots[0])) catch |err| return failure(engine, err, generation);
    return .{ .awaited = chained };
}
fn bindingFailure(engine: *js.Engine, owner: c.JSValue, reason: c.JSValue) !c.JSValue {
    const capture = try get(engine, owner, "capture"); defer release(engine, capture);
    const handler = try get(engine, owner, "handler"); defer release(engine, handler);
    var args = [_]c.JSValue{reason, handler};
    exits.before(engine);
    const ignored = try value(engine, c.JS_Call(engine.context, capture, c.pi_js_undefined(), args.len, &args)); release(engine, ignored);
    // Source PromiseReject(error), rather than throwing or passing through,
    // preserves the rejection-handler adoption/real Await job sequence.
    return value(engine, c.JS_NewSettledPromise(engine.context, true, reason));
}
fn onBindingFailure(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    const result = if (frame.check()) |_| bindingFailure(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| failed: { recordFailure(engine, err); break :failed c.pi_js_undefined(); } else |_| c.pi_js_undefined();
    return frame.finishValue(result) catch engine.throwCaptured();
}
pub const Inputs = struct { error_capture_stack_trace: c.JSValue };
/// Embedders with captured primordials pass the actual captureStackTrace binding.
pub fn createWithInputs(engine: *js.Engine, inputs: Inputs) !c.JSValue {
    var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    const result = if (frame.check()) |_| createWithInputsInner(engine, inputs) catch |err| failed: { recordFailure(engine, err); break :failed c.pi_js_undefined(); } else |_| c.pi_js_undefined();
    return frame.finishValue(result);
}
fn createWithInputsInner(engine: *js.Engine, inputs: Inputs) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, inputs.error_capture_stack_trace)) return error.RequiredActualErrorCaptureStackTrace;
    const owner = try value(engine, c.JS_NewObjectProto(engine.context, c.pi_js_null())); defer release(engine, owner);
    if (c.JS_DefinePropertyValueStr(engine.context, owner, "capture", c.JS_DupValue(engine.context, inputs.error_capture_stack_trace), c.JS_PROP_C_W_E) < 0) return exits.capture(engine);
    var data = [_]c.JSValue{owner};
    const handler = try value(engine, c.JS_NewCFunctionData2(engine.context, onBindingFailure, "handleErrorFromBinding", 1, 0, data.len, &data)); defer release(engine, handler);
    if (c.JS_DefinePropertyValueStr(engine.context, owner, "handler", c.JS_DupValue(engine.context, handler), c.JS_PROP_C_W_E) < 0) return exits.capture(engine);
    return value(engine, try checked(engine, af.createResumable(engine, "mkdir", 2, body, &.{handler})));
}
/// Bootstrap convenience: call before extension code can replace primordials.
pub fn create(engine: *js.Engine) !c.JSValue {
    var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    const result = if (frame.check()) |_| createInner(engine) catch |err| failed: { recordFailure(engine, err); break :failed c.pi_js_undefined(); } else |_| c.pi_js_undefined();
    return frame.finishValue(result);
}
fn createInner(engine: *js.Engine) !c.JSValue {
    const constructor = try get(engine, engine.intrinsic_clone_operations, "Error"); defer release(engine, constructor);
    const capture = try get(engine, constructor, "captureStackTrace"); defer release(engine, capture);
    return checked(engine, createWithInputs(engine, .{ .error_capture_stack_trace = capture }));
}
/// Install before fs ESM exports are frozen. Replaces only the old mkdir member;
/// caller supplies the actual shared fs.promises namespace used by both aliases.
pub fn install(engine: *js.Engine, promises: c.JSValue) !void {
    var frame: exits.Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    if (frame.check()) |_| installInner(engine, promises) catch |err| { recordFailure(engine, err); } else |_| {};
    return frame.finishVoid();
}
fn installInner(engine: *js.Engine, promises: c.JSValue) !void {
    const function = try checked(engine, create(engine));
    const status = c.JS_DefinePropertyValueStr(engine.context, promises, "mkdir", function, c.JS_PROP_C_W_E);
    try pending(engine); if (status < 0) return exits.capture(engine);
}

test "mkdir is a real native AsyncFunction and validation preserves Source ordering and raw reasons" {
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const function = try create(engine); defer release(engine, function);
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    const global = c.JS_GetGlobalObject(engine.context); defer release(engine, global);
    try js.define(engine, global, "mkdirPrepared", c.JS_DupValue(engine.context, function));
    const result = try engine.evalModule(
        \\const reason={toString(){throw Error('reason formatted')}};const order=[];
        \\let p;try{p=mkdirPrepared(null,{get recursive(){order.push('recursive');return false},get mode(){order.push('mode');throw reason}})}catch(e){throw Error('synchronous validation throw')}
        \\if(!(p instanceof Promise))throw Error('not Promise');try{await p;throw Error('getter accepted')}catch(e){if(e!==reason)throw e}
        \\if(order.join(',')!=='recursive,mode')throw Error('Source validation order');
        \\for(const options of [{recursive:null},{mode:'888'},{mode:-1},{mode:1.5},{mode:{}}]){const q=mkdirPrepared('unused-native-mkdir-path',options);if(!(q instanceof Promise))throw Error('validation Promise');try{await q;throw Error('invalid accepted')}catch(e){if(!['ERR_INVALID_ARG_TYPE','ERR_INVALID_ARG_VALUE','ERR_OUT_OF_RANGE'].includes(e.code))throw e}}
    , "native-mkdir-async-validation.mjs");
    release(engine, result);
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expectEqual(@as(u32, 0), pending_workers.load(.acquire));
}

test "mkdir completion pending entry precedes settlement and survives resolver cleanup and destroy" {
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    engine.native_io = std.testing.io;
    const env = try hub.get(engine);
    const original = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(original);
    const ordinary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary);
    const later = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(later);
    c.JS_SetUncatchableError(engine.context, original); c.JS_SetUncatchableError(engine.context, later);
    var resolvers: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolvers)); defer engine.freeValue(promise);
    var functions_owned = true;
    defer if (functions_owned) { engine.freeValue(resolvers[0]); engine.freeValue(resolvers[1]); };
    const ordinary_witness = try exits.Testing.cleanup(engine, ordinary);
    if (c.JS_DefinePropertyValueStr(engine.context, resolvers[0], "cleanup", ordinary_witness, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const later_witness = try exits.Testing.cleanup(engine, later);
    if (c.JS_DefinePropertyValueStr(engine.context, resolvers[1], "cleanup", later_witness, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const path = try engine.gpa.dupe(u8, ""); var path_owned = true; defer if (path_owned) engine.gpa.free(path);
    const offsets = try engine.gpa.dupe(usize, &.{0}); var offsets_owned = true; defer if (offsets_owned) engine.gpa.free(offsets);
    try reserve(); var admission_owned = true; defer if (admission_owned) { _ = pending_workers.fetchSub(1, .acq_rel); };
    const request = try engine.gpa.create(Request);
    request.* = .{ .task = .{ .hub = env, .work = Request.work, .complete = Request.complete, .destroy = Request.destroy, .cancel = Request.cancel, .resolve = resolvers[0], .reject = resolvers[1], .propagate_completion_errors = true }, .packet = .{ .io = std.testing.io, .path = path, .recursive = false, .mode = 0o777, .ancestors = offsets, .failure = error.FileNotFound } };
    functions_owned = false; path_owned = false; offsets_owned = false; admission_owned = false;
    var request_owned = true; defer if (request_owned) Request.destroy(&request.task);
    request.task.done.store(true, .release); // completion-boundary control; no worker/file syscall
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
    try std.testing.expectError(error.JavaScriptException, Request.complete(&request.task));
    try std.testing.expect(request.resolvers_released);
    try std.testing.expect(c.JS_IsUndefined(request.task.resolve) and c.JS_IsUndefined(request.task.reject));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, promise));
    request_owned = false; Request.destroy(&request.task);
    const observed = c.JS_GetException(engine.context); defer engine.freeValue(observed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, original));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(@as(u32, 0), pending_workers.load(.acquire));
}
