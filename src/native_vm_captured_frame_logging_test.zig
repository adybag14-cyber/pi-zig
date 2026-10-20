//! Actual compiled-script origin projected from genuine captured frames.
//! Raw QuickJS controls; Node's process-terminal CHECK formatter is separate.
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});

fn capture(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 16, c.pi_js_undefined(), null, 0, 0, c.JS_ERROR_STACK_SKIP_FIRST);
}
fn captureAll(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 16, c.pi_js_undefined(), null, 0, 0, 0);
}
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,

    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        try self.bind(self.context.?);
    }
    fn deinit(self: *Fixture) void {
        if (self.context) |context| {
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| {
            self.runtime = null;
            c.JS_FreeRuntime(runtime);
        }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.ActualLoggingFrameControlException;
        }
        return value;
    }
    fn bind(self: *Fixture, context: *c.JSContext) !void {
        const plain = try self.checked(c.JS_NewCFunction(context, capture, "capture", 0));
        defer c.JS_FreeValue(context, plain);
        const all = try self.checked(c.JS_NewCFunction(context, captureAll, "captureAll", 0));
        defer c.JS_FreeValue(context, all);
        try self.publishIn(context, "capture", plain);
        try self.publishIn(context, "captureAll", all);
    }
    fn publishIn(self: *Fixture, context: *c.JSContext, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(context));
        defer c.JS_FreeValue(context, global_object);
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_DefinePropertyValueStr(context, global_object, name,
                c.JS_DupValue(context, value), c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(context));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        try self.publishIn(self.context.?, name, value);
    }
    fn evalAt(self: *Fixture, context: *c.JSContext, text: [:0]const u8,
        filename: [*:0]const u8, flags: c_int) !c.JSValue
    {
        return self.checked(c.JS_Eval(context, text.ptr, text.len, filename, flags));
    }
    fn eval(self: *Fixture, text: [:0]const u8) !c.JSValue {
        return self.evalAt(self.context.?, text, "actual-logging-origin.js",
            c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    }
    fn run(self: *Fixture, text: [:0]const u8) !void {
        const result = try self.eval(text);
        defer c.JS_FreeValue(self.context.?, result);
    }
    fn globalValue(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        return self.checked(c.JS_GetPropertyStr(self.context.?, global_object, name));
    }
    fn item(self: *Fixture, array: c.JSValue, index: u32) !c.JSValue {
        try std.testing.expect(c.JS_IsArray(array));
        return self.checked(c.JS_GetPropertyUint32(self.context.?, array, index));
    }
    fn origin(self: *Fixture, frame: c.JSValue, is_eval: bool, has_script: bool) !void {
        var eval_origin: c_int = 71;
        var script_origin: c_int = 83;
        try std.testing.expectEqual(@as(c_int, 0),
            c.JS_ReadCapturedStackFrameLoggingInfo(self.context.?, frame, &eval_origin, &script_origin));
        try std.testing.expectEqual(@as(c_int, @intFromBool(is_eval)), eval_origin);
        try std.testing.expectEqual(@as(c_int, @intFromBool(has_script)), script_origin);
    }
    fn expectFrame(self: *Fixture, frames: c.JSValue, index: u32, is_eval: bool, has_script: bool) !void {
        const value = try self.item(frames, index);
        defer c.JS_FreeValue(self.context.?, value);
        try self.origin(value, is_eval, has_script);
    }
    fn drain(self: *Fixture) !void {
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 64) return error.LoggingControlJobLimit;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
            if (status < 0 or c.JS_HasException(self.context.?)) return error.LoggingControlJobException;
            if (status == 0) return error.LoggingControlUnexpectedBlockedJob;
            count += 1;
        }
    }
    fn stringEquals(self: *Fixture, value: c.JSValue, expected: []const u8) !void {
        try std.testing.expect(c.JS_IsString(value));
        var size: usize = 0;
        const bytes = c.JS_ToCStringLen(self.context.?, &size, value) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(self.context.?, bytes);
        try std.testing.expectEqualStrings(expected, bytes[0..size]);
    }
    fn exceptionMessage(self: *Fixture, result: c.JSValue, expected: []const u8) !void {
        // Caller owns the raw result before any assertion, including unexpected success.
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.context.?));
        const reason = c.JS_GetException(self.context.?);
        defer c.JS_FreeValue(self.context.?, reason);
        try std.testing.expect(c.JS_IsError(reason));
        const message = try self.checked(c.JS_GetPropertyStr(self.context.?, reason, "message"));
        defer c.JS_FreeValue(self.context.?, message);
        try self.stringEquals(message, expected);
    }
};

test "VM logging origin host script and nested functions ignore eval display names" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.evalAt(f.context.?,
        \\const misleading = function ordinary() { return capture(); };
        \\Object.defineProperty(misleading, "name", {value:"eval"});
        \\misleading();
        \\//# sourceURL=[eval]
        , "[eval]", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    defer c.JS_FreeValue(f.context.?, frames);
    try f.expectFrame(frames, 0, false, true);
    try f.expectFrame(frames, 1, false, true);
}

test "VM logging origin module and its function retain actual host script origin" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const result = try f.evalAt(f.context.?,
        \\function fromModule() { return capture(); }
        \\globalThis.moduleFrames = fromModule();
        , "[eval]-module.mjs", c.JS_EVAL_TYPE_MODULE);
    defer c.JS_FreeValue(f.context.?, result);
    try f.drain();
    const frames = try f.globalValue("moduleFrames"); defer c.JS_FreeValue(f.context.?, frames);
    try f.expectFrame(frames, 0, false, true);
    try f.expectFrame(frames, 1, false, true);
}

test "VM logging origin direct eval keeps its host caller distinct" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.eval(
        \\(function caller() { return eval("capture()"); })();
    );
    defer c.JS_FreeValue(f.context.?, frames);
    try f.expectFrame(frames, 0, true, true);
    try f.expectFrame(frames, 1, false, true);
}

test "VM logging origin indirect eval uses actual eval origin without filename inference" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.eval(
        \\(function caller() { return (0, eval)("capture()\n//# sourceURL=ordinary-module.mjs"); })();
    );
    defer c.JS_FreeValue(f.context.?, frames);
    try f.expectFrame(frames, 0, true, true);
    // Indirect eval is the actual native eval call between its compiled
    // body and the host caller; that native frame has no Script owner.
    try f.expectFrame(frames, 1, false, false);
    try f.expectFrame(frames, 2, false, true);
}

test "VM logging origin escaped eval functions arrows and methods retain their compiled owner" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const groups = try f.eval(
        \\const saved = (0, eval)("({fn: function named() { return capture(); }, arrow: () => capture(), method() { return capture(); }})");
        \\Object.defineProperty(saved.fn, "name", {value:"ordinary"});
        \\[saved.fn(), saved.arrow(), saved.method()];
    );
    defer c.JS_FreeValue(f.context.?, groups);
    for (0..3) |index| {
        const frames = try f.item(groups, @intCast(index)); defer c.JS_FreeValue(f.context.?, frames);
        try f.expectFrame(frames, 0, true, true);
        try f.expectFrame(frames, 1, false, true);
    }
}

test "VM logging origin all four dynamic Function constructors compile actual eval scripts" {
    const programs = [_][:0]const u8{
        \\globalThis.dynamicFrames = Function("return capture();")();
        ,
        \\const G = Object.getPrototypeOf(function*(){}).constructor;
        \\globalThis.dynamicFrames = G("return capture();")().next().value;
        ,
        \\const A = Object.getPrototypeOf(async function(){}).constructor;
        \\A("return capture();")().then(value => { globalThis.dynamicFrames = value; });
        ,
        \\const A = Object.getPrototypeOf(async function*(){}).constructor;
        \\A("return capture();")().next().then(value => { globalThis.dynamicFrames = value.value; });
        ,
    };
    for (programs) |program| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try f.run(program); try f.drain();
        const frames = try f.globalValue("dynamicFrames"); defer c.JS_FreeValue(f.context.?, frames);
        try f.expectFrame(frames, 0, true, true);
    }
}

test "VM logging origin class constructor and field initializer inherit the actual eval compilation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const groups = try f.eval(
        \\const Classes = (0, eval)("({ Explicit: class Named { constructor() { this.frames = capture(); } }, Default: class { frames = capture(); } })");
        \\[(new Classes.Explicit()).frames, (new Classes.Default()).frames];
    );
    defer c.JS_FreeValue(f.context.?, groups);
    for (0..2) |index| {
        const frames = try f.item(groups, @intCast(index)); defer c.JS_FreeValue(f.context.?, frames);
        try f.expectFrame(frames, 0, true, true);
    }
}

test "VM logging origin real foreign context compilation does not use the reading context" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const foreign = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    try f.bind(foreign);
    const host_frames = try f.evalAt(foreign,
        "(function foreignHost(){return capture();})()", "[eval]", c.JS_EVAL_TYPE_GLOBAL);
    defer c.JS_FreeValue(foreign, host_frames);
    const eval_frames = try f.evalAt(foreign,
        "(0,eval)('(function foreignEval(){return capture();})()')", "foreign.js", c.JS_EVAL_TYPE_GLOBAL);
    defer c.JS_FreeValue(foreign, eval_frames);
    try f.expectFrame(host_frames, 0, false, true);
    try f.expectFrame(eval_frames, 0, true, true);
    const original = try f.checked(c.JS_GetPropertyUint32(foreign, eval_frames, 0));
    defer c.JS_FreeValue(foreign, original);
    const clone = try f.checked(c.JS_CloneCapturedStackFrame(f.context.?, original));
    defer c.JS_FreeValue(f.context.?, clone);
    try f.origin(clone, true, true);
}

test "VM logging origin native and filename-only synthetic frames have no compiled Script owner" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.eval("captureAll()");
    defer c.JS_FreeValue(f.context.?, frames);
    try f.expectFrame(frames, 0, false, false);
    try f.expectFrame(frames, 1, false, true);
    const synthetic = try f.checked(c.JS_CaptureCurrentStackFrames(f.context.?, 10,
        c.pi_js_undefined(), "[eval]", 17, 23, c.JS_ERROR_STACK_SINGLE_LEVEL));
    defer c.JS_FreeValue(f.context.?, synthetic);
    try f.expectFrame(synthetic, 0, false, false);
}

test "VM logging origin cloned frames retain private origin after original frame removal" {
    const programs = [_][:0]const u8{"(function(){return capture();})()", "(0,eval)('capture()')", "captureAll()"};
    for (programs, 0..) |program, index| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const frames = try f.eval(program);
        const frame = f.item(frames, 0) catch |err| { c.JS_FreeValue(f.context.?, frames); return err; };
        const result = c.JS_CloneCapturedStackFrame(f.context.?, frame);
        c.JS_FreeValue(f.context.?, frame);
        c.JS_FreeValue(f.context.?, frames);
        const clone = try f.checked(result); defer c.JS_FreeValue(f.context.?, clone);
        try f.origin(clone, index == 1, index != 2);
    }
}

test "VM logging origin projection ignores poisoned public fields and proxy traps" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.eval("(0,eval)('capture()')");
    defer c.JS_FreeValue(f.context.?, frames);
    const frame = try f.item(frames, 0); defer c.JS_FreeValue(f.context.?, frame);
    try f.publish("selectedFrame", frame);
    try f.run(
        \\globalThis.loggingProgress = {calls:0};
        \\for (const name of ["isEval","hasScriptId","getScriptId","getFileName","getFunctionName"]) {
        \\  Object.defineProperty(selectedFrame, name, {configurable:true,get(){loggingProgress.calls++;throw 19;}});
        \\}
        \\globalThis.frameProxy = new Proxy(selectedFrame, {
        \\  get(){loggingProgress.calls++;throw 20;},
        \\  getPrototypeOf(){loggingProgress.calls++;throw 21;}
        \\});
    );
    const proxy = try f.globalValue("frameProxy"); defer c.JS_FreeValue(f.context.?, proxy);
    try f.origin(frame, true, true);
    var a: c_int = 37; var b: c_int = 41;
    try std.testing.expectEqual(@as(c_int, -1), c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, proxy, &a, &b));
    try std.testing.expectEqual(@as(c_int, 37), a); try std.testing.expectEqual(@as(c_int, 41), b);
    try f.run("if(loggingProgress.calls!==0)throw new Error('projection entered guest fields');");
}

test "VM logging origin invalid brand and missing outputs leave caller storage unchanged" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.eval("capture()");
    defer c.JS_FreeValue(f.context.?, frames);
    const frame = try f.item(frames, 0); defer c.JS_FreeValue(f.context.?, frame);
    const invalid = try f.checked(c.JS_NewObject(f.context.?)); defer c.JS_FreeValue(f.context.?, invalid);
    var a: c_int = 47; var b: c_int = 53;
    try std.testing.expectEqual(@as(c_int, -1), c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, invalid, &a, &b));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, c.pi_js_null(), &a, &b));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, frame, null, &b));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, frame, &a, null));
    try std.testing.expectEqual(@as(c_int, 47), a); try std.testing.expectEqual(@as(c_int, 53), b);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM logging origin projection allocates nothing and preserves ordinary and actual fatal pending" {
    for ([_]bool{ false, true }) |fatal| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const frames = try f.eval("(0,eval)('capture()')"); defer c.JS_FreeValue(f.context.?, frames);
        const frame = try f.item(frames, 0); defer c.JS_FreeValue(f.context.?, frame);
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (fatal) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        var a: c_int = 0; var b: c_int = 0;
        const status = c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, frame, &a, &b);
        var invalid_a: c_int = 59; var invalid_b: c_int = 61;
        const invalid_status = c.JS_ReadCapturedStackFrameLoggingInfo(f.context.?, c.pi_js_undefined(), &invalid_a, &invalid_b);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(@as(c_int, 0), status);
        try std.testing.expectEqual(@as(c_int, 1), a); try std.testing.expectEqual(@as(c_int, 1), b);
        try std.testing.expectEqual(@as(c_int, -1), invalid_status);
        try std.testing.expectEqual(@as(c_int, 59), invalid_a); try std.testing.expectEqual(@as(c_int, 61), invalid_b);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const pending = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, pending);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, pending));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(pending));
    }
}

const ReceiverProbe = struct { released: u32 = 0, class_id: c.JSClassID = 0 };
fn receiverFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *ReceiverProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    probe.released += 1;
}
test "VM logging origin projection borrows the frame without extending receiver lifetime" {
    var probe: ReceiverProbe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    if (c.JS_NewClassID(f.runtime.?, &probe.class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Logging actual receiver", .finalizer = receiverFinalizer };
    if (c.JS_NewClass(f.runtime.?, probe.class_id, &definition) < 0) return error.OutOfMemory;
    const receiver = try f.checked(c.JS_NewObjectClass(f.context.?, probe.class_id));
    _ = c.JS_SetOpaque(receiver, &probe);
    const function = f.eval("(function(){return capture();})") catch |err| { c.JS_FreeValue(f.context.?, receiver); return err; };
    defer c.JS_FreeValue(f.context.?, function);
    const raw = c.JS_Call(f.context.?, function, receiver, 0, null);
    c.JS_FreeValue(f.context.?, receiver);
    const frames = try f.checked(raw);
    const frame = f.item(frames, 0) catch |err| { c.JS_FreeValue(f.context.?, frames); return err; };
    c.JS_FreeValue(f.context.?, frames);
    {
        defer c.JS_FreeValue(f.context.?, frame);
        try std.testing.expectEqual(@as(u32, 0), probe.released);
        for (0..7) |_| try f.origin(frame, false, true);
        try std.testing.expectEqual(@as(u32, 0), probe.released);
    }
    try std.testing.expectEqual(@as(u32, 1), probe.released);
}

const serialization_flags = [_]c_int{
    c.JS_WRITE_OBJ_BYTECODE,
    c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_SOURCE,
    c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_DEBUG,
    c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_SOURCE | c.JS_WRITE_OBJ_STRIP_DEBUG,
};
fn serializedHost(module: bool) !void {
    for (serialization_flags) |flags| {
        var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
        const text: [:0]const u8 =
            \\globalThis.serialFrames = (function serialChild(){ return capture(); })();
        ;
        const compiled = try writer.evalAt(writer.context.?, text, "[eval]-serialized.js",
            (if (module) @as(c_int, c.JS_EVAL_TYPE_MODULE) else @as(c_int, c.JS_EVAL_TYPE_GLOBAL)) | c.JS_EVAL_FLAG_COMPILE_ONLY);
        defer c.JS_FreeValue(writer.context.?, compiled);
        var size: usize = 0;
        const data = c.JS_WriteObject(writer.context.?, &size, compiled, flags) orelse return error.OutOfMemory;
        defer c.js_free(writer.context.?, data);
        try std.testing.expect(!c.JS_HasException(writer.context.?));
        var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
        const loaded = try reader.checked(c.JS_ReadObject(reader.context.?, data, size, c.JS_READ_OBJ_BYTECODE));
        defer c.JS_FreeValue(reader.context.?, loaded);
        if (module) try std.testing.expectEqual(@as(c_int, 0), c.JS_ResolveModule(reader.context.?, loaded));
        const result = try reader.checked(c.JS_EvalFunction(reader.context.?, c.JS_DupValue(reader.context.?, loaded)));
        defer c.JS_FreeValue(reader.context.?, result);
        try reader.drain();
        const frames = try reader.globalValue("serialFrames"); defer c.JS_FreeValue(reader.context.?, frames);
        try reader.expectFrame(frames, 0, false, true);
        try reader.expectFrame(frames, 1, false, true);
    }
}
test "VM logging origin serialized host bytecode retains origin with source and debug stripped" { try serializedHost(false); }
test "VM logging origin serialized module bytecode retains origin in a fresh runtime" { try serializedHost(true); }

fn readLeb(bytes: []const u8, cursor: *usize) !u32 {
    var result: u32 = 0;
    for (0..5) |index| {
        if (cursor.* >= bytes.len) return error.LoggingControlInvalidBytecodeEnvelope;
        const byte = bytes[cursor.*]; cursor.* += 1;
        const shift: u5 = @intCast(index * 7);
        if (index == 4 and byte > 15) return error.LoggingControlInvalidBytecodeEnvelope;
        result |= @as(u32, byte & 0x7f) << shift;
        if (byte & 0x80 == 0) return result;
    }
    return error.LoggingControlInvalidBytecodeEnvelope;
}
fn functionFlagsOffset(bytes: []const u8) !usize {
    // Parse the real version/checksum/atom envelope to locate this compiled
    // top-level function. No hard-coded offset depends on its actual names.
    if (bytes.len < 6) return error.LoggingControlInvalidBytecodeEnvelope;
    try std.testing.expectEqual(@as(u8, 30), bytes[0]);
    var cursor: usize = 5;
    const count = try readLeb(bytes, &cursor);
    for (0..count) |_| {
        if (cursor >= bytes.len) return error.LoggingControlInvalidBytecodeEnvelope;
        const atom_type = bytes[cursor]; cursor += 1;
        if (atom_type & 0x80 != 0) {
            if (atom_type & 0x40 != 0) _ = try readLeb(bytes, &cursor);
        } else {
            const length = try readLeb(bytes, &cursor);
            const byte_length = @as(usize, length >> 1) << @as(u1, @intCast(length & 1));
            if (byte_length > bytes.len - cursor) return error.LoggingControlInvalidBytecodeEnvelope;
            cursor += byte_length;
        }
    }
    if (cursor + 3 > bytes.len) return error.LoggingControlInvalidBytecodeEnvelope;
    try std.testing.expectEqual(@as(u8, 12), bytes[cursor]); // Actual BC_TAG_FUNCTION_BYTECODE.
    return cursor + 1;
}
test "VM logging origin prior bytecode version is rejected by the actual version gate" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const compiled = try f.evalAt(f.context.?, "capture()", "old-version.js",
        c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer c.JS_FreeValue(f.context.?, compiled);
    var size: usize = 0;
    const data = c.JS_WriteObject(f.context.?, &size, compiled, c.JS_WRITE_OBJ_BYTECODE) orelse return error.OutOfMemory;
    defer c.js_free(f.context.?, data);
    try std.testing.expect(size > 5);
    try std.testing.expectEqual(@as(u8, 30), data[0]);
    data[0] = 29;
    const result = c.JS_ReadObject(f.context.?, data, size, c.JS_READ_OBJ_BYTECODE);
    defer c.JS_FreeValue(f.context.?, result);
    try f.exceptionMessage(result, "invalid version (29 expected=30)");
}

test "VM logging origin malformed serialized origin reaches its exact validation error" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const compiled = try f.evalAt(f.context.?, "capture()", "bad-origin.js",
        c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer c.JS_FreeValue(f.context.?, compiled);
    var size: usize = 0;
    const data = c.JS_WriteObject(f.context.?, &size, compiled, c.JS_WRITE_OBJ_BYTECODE) orelse return error.OutOfMemory;
    defer c.js_free(f.context.?, data);
    const bytes = data[0..size];
    const offset = try functionFlagsOffset(bytes);
    const order = builtin.target.cpu.arch.endian();
    const flags = std.mem.readInt(u16, bytes[offset..][0..2], order);
    try std.testing.expectEqual(@as(u16, 1), (flags >> 12) & 3);
    std.mem.writeInt(u16, bytes[offset..][0..2], flags | (@as(u16, 3) << 12), order);
    // The linked reader's documented corpus escape disables only checksum
    // validation, so this controlled mutation reaches the new field validator.
    @memset(bytes[1..5], 0xff);
    const result = c.JS_ReadObject(f.context.?, data, size, c.JS_READ_OBJ_BYTECODE);
    defer c.JS_FreeValue(f.context.?, result);
    try f.exceptionMessage(result, "invalid bytecode script origin");
}

const CaptureOwner = struct {
    context: *c.JSContext,
    frames: ?c.JSValue = null,
    calls: u32 = 0,
    fn close(self: *CaptureOwner) void {
        c.JS_SetNativeErrorStackHook(c.JS_GetRuntime(self.context), null, null);
        if (self.frames) |frames| { self.frames = null; c.JS_FreeValue(self.context, frames); }
    }
};
fn captureError(context: ?*c.JSContext, _: c.JSValue, phase: c_int, filter: c.JSValue,
    filename: [*c]const u8, line: c_int, column: c_int, flags: c_int, raw_owner: ?*anyopaque) callconv(.c) c_int
{
    const owner: *CaptureOwner = @ptrCast(@alignCast(raw_owner orelse return -1));
    if (context.? != owner.context) return -1;
    owner.calls += 1;
    if (phase == c.JS_ERROR_STACK_PREPARE) return 0;
    const frames = c.JS_CaptureCurrentStackFrames(context, 16, filter, filename, line, column, flags);
    if (c.JS_IsException(frames) or c.JS_HasException(context)) {
        c.JS_FreeValue(context, frames);
        return -1;
    }
    const previous = owner.frames;
    owner.frames = frames;
    if (previous) |value| c.JS_FreeValue(context, value);
    return if (c.JS_HasException(context)) -1 else 0;
}
test "VM logging origin genuine CommonJS compiler root and its nested function are host scripts" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var owner: CaptureOwner = .{ .context = f.context.? };
    defer owner.close();
    c.JS_SetNativeErrorStackHook(f.runtime.?, captureError, &owner);
    const text = try f.checked(c.JS_NewString(f.context.?,
        "return (function commonJsChild(){ return capture(); })();"));
    defer c.JS_FreeValue(f.context.?, text);
    const filename = try f.checked(c.JS_NewString(f.context.?, "[eval]-commonjs.cjs"));
    defer c.JS_FreeValue(f.context.?, filename);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_NO_SYNTAX_CATEGORY;
    const function = try f.checked(c.JS_PiCompileCJSFunction(f.context.?, text, filename, &category));
    defer c.JS_FreeValue(f.context.?, function);
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    const frames = try f.checked(c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null));
    defer c.JS_FreeValue(f.context.?, frames);
    try f.expectFrame(frames, 0, false, true);
    try f.expectFrame(frames, 1, false, true);
    try std.testing.expectEqual(@as(u32, 0), owner.calls);
}
