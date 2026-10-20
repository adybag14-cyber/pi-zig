//! Actual native Script/source/location owners. These controls use the linked
//! compiler, genuine captured frames and the bytecode reader/writer.
//! Message construction, failed-parse attachment and Node reporting are separate.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Script = c.JSNativeScript;
const compile_flags: c_int = c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_COMPILE_ONLY;
const strip_flags = [_]c_int{
    c.JS_WRITE_OBJ_BYTECODE,
    c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_SOURCE,
    c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_DEBUG,
    c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_SOURCE | c.JS_WRITE_OBJ_STRIP_DEBUG,
};
fn capture(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 32, c.pi_js_undefined(), null, 0, 0,
        c.JS_ERROR_STACK_SKIP_FIRST);
}
fn captureAll(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 32, c.pi_js_undefined(), null, 0, 0, 0);
}
fn errorCapture(context: ?*c.JSContext, _: c.JSValue, phase: c_int, filter: c.JSValue,
    filename: [*c]const u8, line: c_int, column: c_int, flags: c_int,
    raw_owner: ?*anyopaque) callconv(.c) c_int
{
    const fixture: *Fixture = @ptrCast(@alignCast(raw_owner orelse return -1));
    if (context != fixture.context) return -1;
    fixture.error_captures += 1;
    if (phase == c.JS_ERROR_STACK_PREPARE) return 0;
    const frames = c.JS_CaptureCurrentStackFrames(context, 16, filter, filename, line, column, flags);
    defer c.JS_FreeValue(context, frames);
    return if (c.JS_IsException(frames) or c.JS_HasException(context)) -1 else 0;
}
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    error_captures: usize = 0,

    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(64 * 1024 * 1024, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        const first = try self.checked(c.JS_NewCFunction(self.context.?, capture, "capture", 0));
        defer c.JS_FreeValue(self.context.?, first);
        const second = try self.checked(c.JS_NewCFunction(self.context.?, captureAll, "captureAll", 0));
        defer c.JS_FreeValue(self.context.?, second);
        try self.publish("capture", first); try self.publish("captureAll", second);
    }
    fn closeContext(self: *Fixture) void {
        if (self.context) |context| {
            c.JS_SetNativeErrorStackHook(self.runtime.?, null, null);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            while (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            self.context = null;
            c.JS_FreeContext(context);
        }
    }
    fn closeRuntime(self: *Fixture) void {
        self.closeContext();
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn deinit(self: *Fixture) void {
        self.closeRuntime();
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, result: c.JSValue) !c.JSValue {
        if (c.JS_IsException(result) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, result);
            return error.ActualScriptControlException;
        }
        return result;
    }
    fn eval(self: *Fixture, program: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, program.ptr, program.len,
            "actual-script-input.js", c.JS_EVAL_TYPE_GLOBAL));
    }
    fn run(self: *Fixture, program: [:0]const u8) !void {
        const result = try self.eval(program); defer c.JS_FreeValue(self.context.?, result);
    }
    fn compile(self: *Fixture, program: [:0]const u8, line: c_int) !c.JSValue {
        var options: c.JSEvalOptions = .{ .version = c.JS_EVAL_OPTIONS_VERSION,
            .eval_flags = compile_flags, .filename = "actual-script-input.js", .line_num = line };
        return self.checked(c.JS_Eval2(self.context.?, program.ptr, program.len, &options));
    }
    fn privateCompile(self: *Fixture, program: [:0]const u8, cjs: bool) !c.JSValue {
        c.JS_SetNativeErrorStackHook(self.runtime.?, errorCapture, self);
        const input = try self.checked(c.JS_NewStringLen(self.context.?, program.ptr, program.len));
        defer c.JS_FreeValue(self.context.?, input);
        const filename = try self.checked(c.JS_NewString(self.context.?, "actual-private.cjs"));
        defer c.JS_FreeValue(self.context.?, filename);
        if (cjs) {
            var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_NO_SYNTAX_CATEGORY;
            const result = try self.checked(c.JS_PiCompileCJSFunction(self.context.?, input, filename, &category));
            errdefer c.JS_FreeValue(self.context.?, result);
            try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
            return result;
        }
        var url = c.pi_js_undefined(); var map = c.pi_js_undefined();
        defer c.JS_FreeValue(self.context.?, url); defer c.JS_FreeValue(self.context.?, map);
        return self.checked(c.JS_PiCompileCommonJSScriptInfo(self.context.?, input, filename, &url, &map));
    }
    fn execute(self: *Fixture, compiled: c.JSValue) !c.JSValue {
        return self.checked(c.JS_EvalFunction(self.context.?, c.JS_DupValue(self.context.?, compiled)));
    }
    fn call(self: *Fixture, function: c.JSValue, receiver: c.JSValue) !c.JSValue {
        return self.checked(c.JS_Call(self.context.?, function, receiver, 0, null));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_DefinePropertyValueStr(self.context.?, global_object, name,
                c.JS_DupValue(self.context.?, value), c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn global(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        return self.checked(c.JS_GetPropertyStr(self.context.?, global_object, name));
    }
    fn item(self: *Fixture, array: c.JSValue, index: u32) !c.JSValue {
        try std.testing.expect(c.JS_IsArray(array));
        return self.checked(c.JS_GetPropertyUint32(self.context.?, array, index));
    }
    fn frameScript(self: *Fixture, frames: c.JSValue, index: u32, source_position: *c_int) !*Script {
        const frame = try self.item(frames, index); defer c.JS_FreeValue(self.context.?, frame);
        return c.JS_PiGetCapturedStackFrameScript(frame, source_position) orelse error.MissingActualFrameScript;
    }
    fn string(self: *Fixture, value: c.JSValue, expected: []const u8) !void {
        try std.testing.expect(c.JS_IsString(value));
        var length: usize = 0;
        const bytes = c.JS_ToCStringLen(self.context.?, &length, value) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(self.context.?, bytes);
        try std.testing.expectEqualStrings(expected, bytes[0..length]);
    }
    fn source(self: *Fixture, owner: *Script, expected: []const u8) !void {
        const value = c.JS_PiScriptGetSource(owner); defer c.JS_FreeValue(self.context.?, value);
        try self.string(value, expected);
    }
    fn drain(self: *Fixture) !void {
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 64) return error.ScriptControlJobLimit;
            var context: ?*c.JSContext = null;
            if (c.JS_ExecutePendingJob(self.runtime.?, &context) <= 0)
                return error.ActualScriptJobFailure;
            count += 1;
        }
    }
    fn exception(self: *Fixture, result: c.JSValue, expected: []const u8) !void {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.context.?));
        const reason = c.JS_GetException(self.context.?); defer c.JS_FreeValue(self.context.?, reason);
        const message = try self.checked(c.JS_GetPropertyStr(self.context.?, reason, "message"));
        defer c.JS_FreeValue(self.context.?, message);
        try self.string(message, expected);
    }
};
fn script(value: c.JSValue) !*Script {
    return c.JS_PiGetCompiledScript(value) orelse error.MissingActualCompiledScript;
}
fn info(owner: *Script) !c.JSPiScriptInfo {
    var result: c.JSPiScriptInfo = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiScriptReadInfo(owner, &result));
    return result;
}
fn position(owner: *Script, at: c_int, offset: bool, line: i64, column: i64,
    start: c_int, end: c_int) !void
{
    var result: c.JSPiScriptPositionInfo = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiScriptGetPositionInfo(owner, at, offset, &result));
    try std.testing.expectEqual(line, result.line); try std.testing.expectEqual(column, result.column);
    try std.testing.expectEqual(start, result.line_start); try std.testing.expectEqual(end, result.line_end);
}
fn utf16Length(bytes: []const u8) !c_int {
    var units: c_int = 0;
    var iterator = (try std.unicode.Utf8View.init(bytes)).iterator();
    while (iterator.nextCodepoint()) |codepoint| units += if (codepoint > 0xffff) @as(c_int, 2) else 1;
    return units;
}
fn callPosition(program: []const u8, private: bool) !c_int {
    // The linked parser selects ')' for a default zero-argument call, and its
    // saved identifier token for the diagnostic compiler's direct identifier.
    const start = std.mem.indexOf(u8, program, "capture()") orelse return error.MissingControlCall;
    return utf16Length(program[0 .. start + (if (private) @as(usize, 0) else 8)]);
}

test "VM Script complete input and UTF16 length are independent of function presentation source" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "/* complete 😀 input */\n(function child(){ return 'é'; })";
    const function = try f.eval(program); defer c.JS_FreeValue(f.context.?, function);
    const owner = try script(function); defer c.JS_PiFreeScript(owner);
    try f.source(owner, program);
    const details = try info(owner);
    try std.testing.expectEqual(try utf16Length(program), details.source_length);
    try std.testing.expectEqual(@as(c_int, program.len), details.source_byte_length);
    try std.testing.expect(!details.is_eval and !details.is_module);
    const resource = c.JS_PiScriptGetResourceName(owner); defer c.JS_FreeValue(f.context.?, resource);
    try f.string(resource, "actual-script-input.js");
}

test "VM Script root nested and sibling bytecode retain one actual native source identity" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "[(function first(){}),(function second(){ return ()=>1; })]";
    const compiled = try f.compile(program, 1); defer c.JS_FreeValue(f.context.?, compiled);
    const root = try script(compiled); defer c.JS_PiFreeScript(root);
    const functions = try f.execute(compiled); defer c.JS_FreeValue(f.context.?, functions);
    const first = try f.item(functions, 0); defer c.JS_FreeValue(f.context.?, first);
    const second = try f.item(functions, 1); defer c.JS_FreeValue(f.context.?, second);
    const nested = try f.call(second, c.pi_js_undefined()); defer c.JS_FreeValue(f.context.?, nested);
    for ([_]c.JSValue{ first, second, nested }) |function| {
        const owner = try script(function); defer c.JS_PiFreeScript(owner);
        try std.testing.expect(owner == root);
    }
}

test "VM Script separate compilations of identical input have distinct owners" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const first = try f.compile("1", 1); defer c.JS_FreeValue(f.context.?, first);
    const second = try f.compile("1", 1); defer c.JS_FreeValue(f.context.?, second);
    const a = try script(first); defer c.JS_PiFreeScript(a);
    const b = try script(second); defer c.JS_PiFreeScript(b);
    try std.testing.expect(a != b);
    try f.source(a, "1"); try f.source(b, "1");
}

test "VM Script duplicate native entitlement outlives function and originating context" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var owned: ?*Script = null; defer if (owned) |owner| c.JS_PiFreeScript(owner);
    {
        const function = try f.eval("(function retained(){return 1;})"); defer c.JS_FreeValue(f.context.?, function);
        const original = try script(function); defer c.JS_PiFreeScript(original);
        owned = c.JS_PiDupScript(original);
        try std.testing.expect(owned.? == original);
    }
    f.closeContext();
    f.context = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    try f.source(owned.?, "(function retained(){return 1;})");
}

test "VM Script brand projection excludes native bound and proxy functions without guest access" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const values = try f.eval(
        \\globalThis.traps=0;
        \\const fn=function actual(){};
        \\[capture, fn.bind(null), new Proxy(fn,{get(){traps++;throw 1;}}), {}, 1];
    ); defer c.JS_FreeValue(f.context.?, values);
    for (0..5) |index| {
        const value = try f.item(values, @intCast(index)); defer c.JS_FreeValue(f.context.?, value);
        const unexpected = c.JS_PiGetCompiledScript(value); defer c.JS_PiFreeScript(unexpected);
        try std.testing.expect(unexpected == null);
    }
    const traps = try f.global("traps"); defer c.JS_FreeValue(f.context.?, traps);
    var count: i32 = -1; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context.?, &count, traps));
    try std.testing.expectEqual(@as(i32, 0), count);
}

test "VM Script source URL and map come from actual lexer comments with last-event semantics" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "'//# sourceURL=string.js';\n/*# sourceMappingURL=block.map */\n" ++
        "\x60//# sourceURL=template.js\x60;\n//# sourceURL=first.js\n//# sourceURL=last.js\n//# sourceMappingURL=actual.map\n0";
    const compiled = try f.compile(program, 1); defer c.JS_FreeValue(f.context.?, compiled);
    const owner = try script(compiled); defer c.JS_PiFreeScript(owner);
    const resource = c.JS_PiScriptGetResourceName(owner); defer c.JS_FreeValue(f.context.?, resource);
    const map = c.JS_PiScriptGetSourceMapURL(owner); defer c.JS_FreeValue(f.context.?, map);
    try f.string(resource, "last.js"); try f.string(map, "actual.map"); try f.source(owner, program);
}

test "VM Script empty later metadata clears earlier recognized lexer metadata" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "//# sourceURL=first.js\n//# sourceMappingURL=first.map\n//# sourceURL=\n//# sourceMappingURL=\n0";
    const compiled = try f.compile(program, 1); defer c.JS_FreeValue(f.context.?, compiled);
    const owner = try script(compiled); defer c.JS_PiFreeScript(owner);
    const resource = c.JS_PiScriptGetResourceName(owner); defer c.JS_FreeValue(f.context.?, resource);
    const map = c.JS_PiScriptGetSourceMapURL(owner); defer c.JS_FreeValue(f.context.?, map);
    try f.string(resource, "actual-script-input.js"); try std.testing.expect(c.JS_IsUndefined(map));
}

test "VM Script genuine module frames retain complete host module source" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "function moduleBody(){return capture();}\nglobalThis.savedFrames=moduleBody();";
    const result = try f.checked(c.JS_Eval(f.context.?, program, program.len, "actual-module.mjs", c.JS_EVAL_TYPE_MODULE));
    defer c.JS_FreeValue(f.context.?, result); try f.drain();
    const frames = try f.global("savedFrames"); defer c.JS_FreeValue(f.context.?, frames);
    var at: c_int = -2;
    const first = try f.frameScript(frames, 0, &at); defer c.JS_PiFreeScript(first);
    const second = try f.frameScript(frames, 1, &at); defer c.JS_PiFreeScript(second);
    try std.testing.expect(first == second);
    const details = try info(first); try std.testing.expect(details.is_module and !details.is_eval);
    try f.source(first, program);
}

test "VM Script direct and indirect eval preserve their actual separate input" {
    for ([_][:0]const u8{
        "(function(){return eval('(function evaluated(){return 7;})');})()",
        "(0,eval)('(function evaluated(){return 7;})')",
    }) |program| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const function = try f.eval(program); defer c.JS_FreeValue(f.context.?, function);
        const owner = try script(function); defer c.JS_PiFreeScript(owner);
        const details = try info(owner); try std.testing.expect(details.is_eval and !details.is_module);
        try f.source(owner, "(function evaluated(){return 7;})");
    }
}

test "VM Script all four dynamic constructors retain actual generated eval input" {
    for ([_][:0]const u8{
        "Function('return 7;')",
        "Object.getPrototypeOf(function*(){}).constructor('return 7;')",
        "Object.getPrototypeOf(async function(){}).constructor('return 7;')",
        "Object.getPrototypeOf(async function*(){}).constructor('return 7;')",
    }) |program| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const function = try f.eval(program); defer c.JS_FreeValue(f.context.?, function);
        const owner = try script(function); defer c.JS_PiFreeScript(owner);
        try std.testing.expect((try info(owner)).is_eval);
        const source = c.JS_PiScriptGetSource(owner); defer c.JS_FreeValue(f.context.?, source);
        var length: usize = 0;
        const bytes = c.JS_ToCStringLen(f.context.?, &length, source) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(f.context.?, bytes);
        try std.testing.expect(std.mem.indexOf(u8, bytes[0..length], "return 7;") != null);
        try std.testing.expect(!std.mem.eql(u8, bytes[0..length], program));
    }
}

test "VM Script genuine CJS compiler keeps original body without presentation wrapper" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "return (function nested(){return capture();})();";
    const function = try f.privateCompile(program, true); defer c.JS_FreeValue(f.context.?, function);
    const owner = try script(function); defer c.JS_PiFreeScript(owner);
    try f.source(owner, program); try std.testing.expect(!(try info(owner)).is_eval);
    const arity = try f.checked(c.JS_GetPropertyStr(f.context.?, function, "length"));
    defer c.JS_FreeValue(f.context.?, arity);
    var count: i32 = -1; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context.?, &count, arity));
    try std.testing.expectEqual(@as(i32, 5), count);
    const frames = try f.call(function, c.pi_js_undefined()); defer c.JS_FreeValue(f.context.?, frames);
    var at: c_int = -2;
    const nested = try f.frameScript(frames, 0, &at); defer c.JS_PiFreeScript(nested);
    try std.testing.expect(nested == owner); try std.testing.expectEqual(@as(usize, 0), f.error_captures);
}

test "VM Script UTF16 line table handles CRLF lone CR LS PS negative and EOF positions" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const program = "/*😀*/\r\n0\r1\u{2028}2\u{2029}3\n";
    const compiled = try f.compile(program, 1); defer c.JS_FreeValue(f.context.?, compiled);
    const owner = try script(compiled); defer c.JS_PiFreeScript(owner);
    try position(owner, -8, false, 0, 0, 0, 6);
    try position(owner, 6, false, 0, 6, 0, 6); // CR before LF
    try position(owner, 7, false, 0, 7, 0, 6); // LF belongs to preceding line
    try position(owner, 8, false, 1, 0, 8, 9);
    try position(owner, 10, false, 2, 0, 10, 11);
    try position(owner, 12, false, 3, 0, 12, 13);
    try position(owner, 14, false, 4, 0, 14, 15);
    try position(owner, 16, false, 5, 0, 16, 16);
    const line = try f.checked(c.JS_PiScriptGetSourceLine(f.context.?, owner, 7));
    defer c.JS_FreeValue(f.context.?, line); try f.string(line, "/*😀*/");
}

test "VM Script empty source and actual initial line offset retain canonical EOF behavior" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const empty = try f.compile("", 17); defer c.JS_FreeValue(f.context.?, empty);
    const a = try script(empty); defer c.JS_PiFreeScript(a);
    try position(a, 0, false, 0, 0, 0, 0); try position(a, 0, true, 16, 0, 0, 0);
    const compiled = try f.compile("0\n1", 101); defer c.JS_FreeValue(f.context.?, compiled);
    const b = try script(compiled); defer c.JS_PiFreeScript(b);
    try std.testing.expectEqual(@as(i64, 100), (try info(b)).line_offset);
    try position(b, 2, true, 101, 0, 2, 3);
}

test "VM Script captured positions use actual token bytes in both compiler modes" {
    const program = "/*😀*/\r\n(function selected(){return capture();})()";
    for ([_]bool{ false, true }) |private| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const compiled = if (private) try f.privateCompile(program, false) else try f.compile(program, 1);
        defer c.JS_FreeValue(f.context.?, compiled);
        const frames = try f.execute(compiled); defer c.JS_FreeValue(f.context.?, frames);
        var at: c_int = -2;
        const owner = try f.frameScript(frames, 0, &at); defer c.JS_PiFreeScript(owner);
        try std.testing.expectEqual(try callPosition(program, private), at);
        try f.source(owner, program);
        try std.testing.expect(at < std.mem.indexOf(u8, program, "capture()").? + 8);
    }
}

test "VM Script source positions survive real backward and long forward branch rewriting" {
    const program = "(function selected(){let n=0;for(let i=0;i<3;i++){n+=i;}" ++
        "if(n===999){" ++ ("n+=1;" ** 100) ++ "}" ++
        "for(const key in {one:1}){if(key==='one')return capture();}return null;})()";
    for ([_]bool{ false, true }) |private| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const compiled = if (private) try f.privateCompile(program, false) else try f.compile(program, 1);
        defer c.JS_FreeValue(f.context.?, compiled);
        const frames = try f.execute(compiled); defer c.JS_FreeValue(f.context.?, frames);
        var at: c_int = -2;
        const owner = try f.frameScript(frames, 0, &at); defer c.JS_PiFreeScript(owner);
        try std.testing.expectEqual(try callPosition(program, private), at);
    }
}

test "VM Script cloned captured frame owns source after original frames retire" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var clone = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, clone);
    var expected: c_int = -2;
    {
        const frames = try f.eval("(function selected(){return capture();})()");
        defer c.JS_FreeValue(f.context.?, frames);
        const frame = try f.item(frames, 0); defer c.JS_FreeValue(f.context.?, frame);
        const owner = c.JS_PiGetCapturedStackFrameScript(frame, &expected) orelse return error.MissingActualFrameScript;
        defer c.JS_PiFreeScript(owner);
        clone = try f.checked(c.JS_CloneCapturedStackFrame(f.context.?, frame));
    }
    c.JS_RunGC(f.runtime.?);
    var actual: c_int = -3;
    const owner = c.JS_PiGetCapturedStackFrameScript(clone, &actual) orelse return error.MissingActualFrameScript;
    defer c.JS_PiFreeScript(owner);
    try std.testing.expectEqual(expected, actual);
    try f.source(owner, "(function selected(){return capture();})()");
}

test "VM Script native synthetic and proxy frames have no fabricated source owner" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const frames = try f.eval("captureAll()"); defer c.JS_FreeValue(f.context.?, frames);
    const native_frame = try f.item(frames, 0); defer c.JS_FreeValue(f.context.?, native_frame);
    const synthetic = try f.checked(c.JS_CaptureCurrentStackFrames(f.context.?, 8, c.pi_js_undefined(),
        "fake-source.js", 7, 8, c.JS_ERROR_STACK_SINGLE_LEVEL));
    defer c.JS_FreeValue(f.context.?, synthetic);
    const fake_frame = try f.item(synthetic, 0); defer c.JS_FreeValue(f.context.?, fake_frame);
    const real_frame = try f.item(frames, 1); defer c.JS_FreeValue(f.context.?, real_frame);
    try f.publish("realFrame", real_frame);
    const proxy = try f.eval("new Proxy(realFrame,{get(){throw 9;}})"); defer c.JS_FreeValue(f.context.?, proxy);
    for ([_]c.JSValue{ native_frame, fake_frame, proxy, c.pi_js_undefined() }) |value| {
        var at: c_int = 123;
        const unexpected = c.JS_PiGetCapturedStackFrameScript(value, &at); defer c.JS_PiFreeScript(unexpected);
        try std.testing.expect(unexpected == null); try std.testing.expectEqual(@as(c_int, 123), at);
    }
    const unexpected = c.JS_PiGetCapturedStackFrameScript(real_frame, null); defer c.JS_PiFreeScript(unexpected);
    try std.testing.expect(unexpected == null); try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM Script raw projections allocate nothing and preserve actual ordinary fatal and private pending" {
    for (0..3) |mode| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const frames = try f.eval("capture()"); defer c.JS_FreeValue(f.context.?, frames);
        const frame = try f.item(frames, 0); defer c.JS_FreeValue(f.context.?, frame);
        var at: c_int = -2;
        const owner = c.JS_PiGetCapturedStackFrameScript(frame, &at) orelse return error.MissingActualFrameScript;
        defer c.JS_PiFreeScript(owner);
        const reason = if (mode == 2) c.JS_PiNativeTerminationResult() else try f.checked(c.JS_NewError(f.context.?));
        defer c.JS_FreeValue(f.context.?, reason);
        if (mode == 1) c.JS_SetUncatchableError(f.context.?, reason);
        if (mode == 2) {
            c.JS_PiRequestExecutionTermination(f.runtime.?);
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
        } else _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        var details: c.JSPiScriptInfo = undefined;
        const status = c.JS_PiScriptReadInfo(owner, &details);
        const source = c.JS_PiScriptGetSource(owner);
        const resource = c.JS_PiScriptGetResourceName(owner);
        const map = c.JS_PiScriptGetSourceMapURL(owner);
        const duplicate = c.JS_PiGetCapturedStackFrameScript(frame, &at);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        defer c.JS_FreeValue(f.context.?, source); defer c.JS_FreeValue(f.context.?, resource);
        defer c.JS_FreeValue(f.context.?, map); defer c.JS_PiFreeScript(duplicate);
        try std.testing.expectEqual(@as(c_int, 0), status);
        try std.testing.expect(duplicate == owner and c.JS_IsString(source) and c.JS_IsString(resource));
        try std.testing.expect(c.JS_HasException(f.context.?));
        if (mode == 2) try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
        if (mode != 2) try std.testing.expectEqual(mode == 1, c.JS_IsUncatchableError(actual));
        if (mode == 2) {
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, actual));
            c.JS_PiCancelExecutionTermination(f.runtime.?);
        }
    }
}

test "VM Script position failure leaves outputs unchanged and source line enforces runtime ownership" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const compiled = try f.compile("0", 1); defer c.JS_FreeValue(f.context.?, compiled);
    const owner = try script(compiled); defer c.JS_PiFreeScript(owner);
    var output: c.JSPiScriptPositionInfo = .{ .line = 11, .column = 12, .line_start = 13, .line_end = 14 };
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiScriptGetPositionInfo(owner, 2, false, &output));
    try std.testing.expectEqual(@as(i64, 11), output.line); try std.testing.expectEqual(@as(i64, 12), output.column);
    try std.testing.expectEqual(@as(c_int, 13), output.line_start); try std.testing.expectEqual(@as(c_int, 14), output.line_end);
    var foreign: Fixture = .{}; try foreign.init(); defer foreign.deinit();
    const raw = c.JS_PiScriptGetSourceLine(foreign.context.?, owner, 0); defer c.JS_FreeValue(foreign.context.?, raw);
    try foreign.exception(raw, "Script belongs to a different runtime");
}

const ReceiverProbe = struct { released: usize = 0, class_id: c.JSClassID = 0 };
fn receiverFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owner: *ReceiverProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null); owner.released += 1;
}
test "VM Script native source owner retains no receiver or function graph after frame retirement" {
    var probe: ReceiverProbe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    if (c.JS_NewClassID(f.runtime.?, &probe.class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual Script receiver", .finalizer = receiverFinalizer };
    if (c.JS_NewClass(f.runtime.?, probe.class_id, &definition) < 0) return error.OutOfMemory;
    var owned: ?*Script = null; defer if (owned) |owner| c.JS_PiFreeScript(owner);
    {
        const receiver = try f.checked(c.JS_NewObjectClass(f.context.?, probe.class_id));
        defer c.JS_FreeValue(f.context.?, receiver); _ = c.JS_SetOpaque(receiver, &probe);
        const function = try f.eval("(function selected(){return capture();})");
        defer c.JS_FreeValue(f.context.?, function);
        const frames = try f.call(function, receiver); defer c.JS_FreeValue(f.context.?, frames);
        var at: c_int = -2;
        owned = try f.frameScript(frames, 0, &at);
        try std.testing.expectEqual(@as(usize, 0), probe.released);
    }
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.released);
    try f.source(owned.?, "(function selected(){return capture();})");
}


fn write(f: *Fixture, value: c.JSValue, flags: c_int) ![]u8 {
    var length: usize = 0;
    const bytes = c.JS_WriteObject(f.context.?, &length, value, flags) orelse return error.ActualScriptWriteFailure;
    errdefer c.js_free(f.context.?, bytes);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(length > 5);
    try std.testing.expectEqual(@as(u8, 31), bytes[0]);
    return bytes[0..length];
}
fn load(f: *Fixture, bytes: []const u8) !c.JSValue {
    return f.checked(c.JS_ReadObject(f.context.?, bytes.ptr, bytes.len, c.JS_READ_OBJ_BYTECODE));
}

test "VM Script serialized siblings keep one source identity without object reference mode under every strip flag" {
    const program = "[(function first(){}),(function second(){return ()=>1;})]";
    for ([_]bool{ false, true }) |private| {
        for (strip_flags) |flags| {
            var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
            const compiled = if (private) try writer.privateCompile(program, false) else try writer.compile(program, 1);
            defer c.JS_FreeValue(writer.context.?, compiled);
            const bytes = try write(&writer, compiled, flags); defer c.js_free(writer.context.?, bytes.ptr);
            var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
            const restored = try load(&reader, bytes); defer c.JS_FreeValue(reader.context.?, restored);
            const root = try script(restored); defer c.JS_PiFreeScript(root);
            try reader.source(root, program);
            const values = try reader.execute(restored); defer c.JS_FreeValue(reader.context.?, values);
            for (0..2) |index| {
                const function = try reader.item(values, @intCast(index)); defer c.JS_FreeValue(reader.context.?, function);
                const owner = try script(function); defer c.JS_PiFreeScript(owner);
                try std.testing.expect(owner == root);
            }
            const original = try script(compiled); defer c.JS_PiFreeScript(original);
            try std.testing.expect(original != root);
        }
    }
}

test "VM Script serialized actual token positions survive source and debug stripping in both compilers" {
    const program = "/*😀*/\r\n(function selected(){return capture();})()";
    for ([_]bool{ false, true }) |private| {
        for (strip_flags) |flags| {
            var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
            const compiled = if (private) try writer.privateCompile(program, false) else try writer.compile(program, 1);
            defer c.JS_FreeValue(writer.context.?, compiled);
            const bytes = try write(&writer, compiled, flags); defer c.js_free(writer.context.?, bytes.ptr);
            var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
            const restored = try load(&reader, bytes); defer c.JS_FreeValue(reader.context.?, restored);
            const frames = try reader.execute(restored); defer c.JS_FreeValue(reader.context.?, frames);
            var at: c_int = -2;
            const owner = try reader.frameScript(frames, 0, &at); defer c.JS_PiFreeScript(owner);
            try std.testing.expectEqual(try callPosition(program, private), at);
            try reader.source(owner, program);
        }
    }
}

test "VM Script ordinary lexer resource and map metadata survive serialization independently of display stripping" {
    var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
    const program = "0\n//# sourceURL=actual-resource.js\n//# sourceMappingURL=actual-resource.map";
    const compiled = try writer.compile(program, 1); defer c.JS_FreeValue(writer.context.?, compiled);
    const bytes = try write(&writer, compiled, c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_DEBUG);
    defer c.js_free(writer.context.?, bytes.ptr);
    var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
    const restored = try load(&reader, bytes); defer c.JS_FreeValue(reader.context.?, restored);
    const owner = try script(restored); defer c.JS_PiFreeScript(owner);
    const resource = c.JS_PiScriptGetResourceName(owner); defer c.JS_FreeValue(reader.context.?, resource);
    const map = c.JS_PiScriptGetSourceMapURL(owner); defer c.JS_FreeValue(reader.context.?, map);
    try reader.string(resource, "actual-resource.js"); try reader.string(map, "actual-resource.map");
    try reader.source(owner, program);
}

test "VM Script serialized module retains complete source module origin and nested identity" {
    var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
    const program = "function nested(){return capture();}globalThis.moduleFrames=nested();";
    const compiled = try writer.checked(c.JS_Eval(writer.context.?, program, program.len,
        "actual-module.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY));
    defer c.JS_FreeValue(writer.context.?, compiled);
    const bytes = try write(&writer, compiled, c.JS_WRITE_OBJ_BYTECODE | c.JS_WRITE_OBJ_STRIP_DEBUG);
    defer c.js_free(writer.context.?, bytes.ptr);
    var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
    const restored = try load(&reader, bytes); defer c.JS_FreeValue(reader.context.?, restored);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ResolveModule(reader.context.?, restored));
    const result = try reader.execute(restored); defer c.JS_FreeValue(reader.context.?, result);
    try reader.drain();
    const frames = try reader.global("moduleFrames"); defer c.JS_FreeValue(reader.context.?, frames);
    var at: c_int = -2;
    const a = try reader.frameScript(frames, 0, &at); defer c.JS_PiFreeScript(a);
    const b = try reader.frameScript(frames, 1, &at); defer c.JS_PiFreeScript(b);
    try std.testing.expect(a == b and (try info(a)).is_module);
    try reader.source(a, program);
}

// This bounded reader locates fields in the genuine writer output; it does not
// implement or replace bytecode loading. All mutated bytes go to JS_ReadObject.
const Cursor = struct {
    bytes: []const u8,
    at: usize = 0,
    fn byte(self: *Cursor) !u8 {
        if (self.at >= self.bytes.len) return error.InvalidScriptControlEnvelope;
        const result = self.bytes[self.at]; self.at += 1; return result;
    }
    fn leb(self: *Cursor) !u32 {
        var result: u32 = 0;
        for (0..5) |index| {
            const next = try self.byte();
            if (index == 4 and next > 15) return error.InvalidScriptControlEnvelope;
            result |= @as(u32, next & 0x7f) << @as(u5, @intCast(index * 7));
            if (next & 0x80 == 0) return result;
        }
        return error.InvalidScriptControlEnvelope;
    }
    fn skip(self: *Cursor, count: usize) !void {
        if (count > self.bytes.len - self.at) return error.InvalidScriptControlEnvelope;
        self.at += count;
    }
    fn string(self: *Cursor) !void {
        const encoded = try self.leb();
        try self.skip(@as(usize, encoded >> 1) << @as(u1, @intCast(encoded & 1)));
    }
};
const Metadata = struct {
    tag: usize, origin: usize, module: usize, input: usize, input_length: usize,
    resource: usize, positions: usize, first_pc: usize, first_offset: usize,
};
fn metadata(bytes: []const u8) !Metadata {
    var cursor: Cursor = .{ .bytes = bytes };
    try std.testing.expectEqual(@as(u8, 31), try cursor.byte());
    try cursor.skip(4);
    const atom_count = try cursor.leb();
    for (0..atom_count) |_| {
        const kind = try cursor.byte();
        if (kind & 0x80 != 0) {
            if (kind & 0x40 != 0) _ = try cursor.leb();
        } else try cursor.string();
    }
    try std.testing.expectEqual(@as(u8, 12), try cursor.byte()); // real function tag
    try cursor.skip(3); // flags, strict
    _ = try cursor.leb(); // actual name atom
    var counts: [8]u32 = undefined;
    for (&counts) |*value| value.* = try cursor.leb();
    const local_count = try cursor.leb();
    for (0..local_count) |_| {
        _ = try cursor.leb(); _ = try cursor.leb(); _ = try cursor.leb();
        const flags = try cursor.byte();
        if (flags & 0x40 != 0) _ = try cursor.leb();
    }
    for (0..counts[5]) |_| { _ = try cursor.leb(); _ = try cursor.leb(); _ = try cursor.leb(); }
    const tag = cursor.at;
    try std.testing.expectEqual(@as(u8, 2), try cursor.byte());
    const origin = cursor.at; _ = try cursor.byte();
    const module = cursor.at; _ = try cursor.byte();
    _ = try cursor.leb(); // selected positive initial line uses same one-byte representation
    const input_length = try cursor.leb(); const input = cursor.at;
    try cursor.skip(input_length);
    const resource = cursor.at; try cursor.string();
    for (0..2) |_| {
        const present = try cursor.byte();
        if (present == 1) try cursor.string() else try std.testing.expectEqual(@as(u8, 0), present);
    }
    const positions = cursor.at; const count = try cursor.leb();
    try std.testing.expect(count > 0);
    const first_pc = cursor.at; _ = try cursor.leb();
    const first_offset = cursor.at; _ = try cursor.leb();
    return .{ .tag = tag, .origin = origin, .module = module, .input = input,
        .input_length = input_length, .resource = resource, .positions = positions,
        .first_pc = first_pc, .first_offset = first_offset };
}
fn readRejected(f: *Fixture, bytes: []const u8, message: []const u8) !void {
    const raw = c.JS_ReadObject(f.context.?, bytes.ptr, bytes.len, c.JS_READ_OBJ_BYTECODE);
    defer c.JS_FreeValue(f.context.?, raw);
    try f.exception(raw, message);
}

test "VM Script real reader rejects invalid owner tags references origin and module bits" {
    var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
    const compiled = try writer.compile("capture()", 1); defer c.JS_FreeValue(writer.context.?, compiled);
    const bytes = try write(&writer, compiled, c.JS_WRITE_OBJ_BYTECODE);
    defer c.js_free(writer.context.?, bytes.ptr);
    const fields = try metadata(bytes);
    const edits = [_]struct { at: usize, byte: u8 }{
        .{ .at = fields.tag, .byte = 3 }, .{ .at = fields.tag, .byte = 1 },
        .{ .at = fields.tag, .byte = 0 }, .{ .at = fields.origin, .byte = 0 },
        .{ .at = fields.origin, .byte = 3 }, .{ .at = fields.module, .byte = 2 },
    };
    for (edits) |edit| {
        var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
        const old = bytes[edit.at]; bytes[edit.at] = edit.byte; defer bytes[edit.at] = old;
        @memset(bytes[1..5], 0xff); // existing corpus gate: bypass checksum only
        try readRejected(&reader, bytes, "invalid bytecode Script provenance");
        reader.closeRuntime();
        try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(reader.memory));
    }
}

test "VM Script reader validates actual PC and source-byte bounds before publication" {
    var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
    const compiled = try writer.compile("capture()", 1); defer c.JS_FreeValue(writer.context.?, compiled);
    const bytes = try write(&writer, compiled, c.JS_WRITE_OBJ_BYTECODE); defer c.js_free(writer.context.?, bytes.ptr);
    const fields = try metadata(bytes);
    for ([_]usize{ fields.first_pc, fields.first_offset }) |at| {
        var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
        try std.testing.expect(bytes[at] < 0x80);
        const old = bytes[at]; bytes[at] = 0x7f; defer bytes[at] = old;
        @memset(bytes[1..5], 0xff);
        try readRejected(&reader, bytes, "invalid bytecode Script provenance");
        reader.closeRuntime();
        try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(reader.memory));
    }
}

test "VM Script partial reader failure retires source records position arrays and table entitlements" {
    var writer: Fixture = .{}; try writer.init(); defer writer.deinit();
    const compiled = try writer.compile("capture()", 1); defer c.JS_FreeValue(writer.context.?, compiled);
    const bytes = try write(&writer, compiled, c.JS_WRITE_OBJ_BYTECODE); defer c.js_free(writer.context.?, bytes.ptr);
    const fields = try metadata(bytes);
    @memset(bytes[1..5], 0xff);
    for ([_]usize{ fields.input + fields.input_length / 2, fields.resource + 1, fields.first_offset, bytes.len - 1 }) |cut| {
        var reader: Fixture = .{}; try reader.init(); defer reader.deinit();
        {
            const raw = c.JS_ReadObject(reader.context.?, bytes.ptr, cut, c.JS_READ_OBJ_BYTECODE);
            defer c.JS_FreeValue(reader.context.?, raw);
            try std.testing.expect(c.JS_IsException(raw)); try std.testing.expect(c.JS_HasException(reader.context.?));
            const reason = c.JS_GetException(reader.context.?); defer c.JS_FreeValue(reader.context.?, reason);
        }
        reader.closeRuntime();
        try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(reader.memory));
    }
}

test "VM Script version31 rejects actual version30 bytes at the unchanged version gate" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const compiled = try f.compile("0", 1); defer c.JS_FreeValue(f.context.?, compiled);
    const bytes = try write(&f, compiled, c.JS_WRITE_OBJ_BYTECODE); defer c.js_free(f.context.?, bytes.ptr);
    bytes[0] = 30;
    try readRejected(&f, bytes, "invalid version (30 expected=31)");
}

test "VM Script real compiler and reader heap failure cleanly retire all native source owners" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    {
        const compiled = try f.compile("capture()", 1); defer c.JS_FreeValue(f.context.?, compiled);
        const bytes = try write(&f, compiled, c.JS_WRITE_OBJ_BYTECODE); defer c.js_free(f.context.?, bytes.ptr);
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const raw = c.JS_ReadObject(f.context.?, bytes.ptr, bytes.len, c.JS_READ_OBJ_BYTECODE);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw)); try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
    }
    {
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const raw = c.JS_Eval(f.context.?, "0", 1, "new-script-allocation.js", compile_flags);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw)); try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
    }
    f.closeRuntime();
    try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(f.memory));
}

test "VM Script prior actual pending wins before allocating source line while raw getters remain available" {
    for ([_]bool{ false, true }) |fatal| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const compiled = try f.compile("0\n1", 1); defer c.JS_FreeValue(f.context.?, compiled);
        const owner = try script(compiled); defer c.JS_PiFreeScript(owner);
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (fatal) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const raw = c.JS_PiScriptGetSourceLine(f.context.?, owner, 0);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw));
        try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
        try std.testing.expect(c.JS_HasException(f.context.?));
        const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsSameValue(f.context.?, actual, reason));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(actual));
    }
}

test "VM Script existing private logical URL serialization restriction is preserved" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const compiled = try f.privateCompile("0\n//# sourceURL=private-logical.js", false);
    defer c.JS_FreeValue(f.context.?, compiled);
    const owner = try script(compiled); defer c.JS_PiFreeScript(owner);
    const resource = c.JS_PiScriptGetResourceName(owner); defer c.JS_FreeValue(f.context.?, resource);
    try f.string(resource, "private-logical.js");
    var length: usize = 999;
    const raw = c.JS_WriteObject(f.context.?, &length, compiled, c.JS_WRITE_OBJ_BYTECODE);
    defer if (raw != null) c.js_free(f.context.?, raw);
    try std.testing.expect(raw == null);
    try std.testing.expectEqual(@as(usize, 0), length);
    try std.testing.expect(c.JS_HasException(f.context.?));
    const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
    const message = try f.checked(c.JS_GetPropertyStr(f.context.?, reason, "message"));
    defer c.JS_FreeValue(f.context.?, message);
    try f.string(message, "Cannot serialize private logical source URL metadata");
}

test "VM Script failed parsing releases native source without fabricating synthetic-frame provenance" {
    const ParseCapture = struct {
        context: ?*c.JSContext,
        frames: ?c.JSValue = null,
        actual_error: ?c.JSValue = null,
        captures: usize = 0,

        fn observe(context: ?*c.JSContext, actual_error: c.JSValue, phase: c_int,
            filter: c.JSValue, filename: [*c]const u8, line: c_int, column: c_int,
            flags: c_int, raw_owner: ?*anyopaque) callconv(.c) c_int
        {
            const self: *@This() = @ptrCast(@alignCast(raw_owner orelse return -1));
            if (context != self.context) return -1;
            if (phase == c.JS_ERROR_STACK_PREPARE or filename == null) return 0;
            const frames = c.JS_CaptureCurrentStackFrames(context, 16, filter, filename, line, column, flags);
            if (c.JS_IsException(frames) or c.JS_HasException(context)) {
                c.JS_FreeValue(context, frames);
                return -1;
            }
            const previous_frames = self.frames;
            const previous_error = self.actual_error;
            self.frames = frames;
            self.actual_error = c.JS_DupValue(context, actual_error);
            self.captures += 1;
            if (previous_frames) |value| c.JS_FreeValue(context, value);
            if (previous_error) |value| c.JS_FreeValue(context, value);
            return if (c.JS_HasException(context)) -1 else 0;
        }
        fn deinit(self: *@This()) void {
            const frames = self.frames;
            const actual_error = self.actual_error;
            self.frames = null;
            self.actual_error = null;
            if (frames) |value| c.JS_FreeValue(self.context, value);
            if (actual_error) |value| c.JS_FreeValue(self.context, value);
        }
    };
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    {
        var observed: ParseCapture = .{ .context = f.context };
        defer observed.deinit();
        c.JS_SetNativeErrorStackHook(f.runtime.?, ParseCapture.observe, &observed);
        defer c.JS_SetNativeErrorStackHook(f.runtime.?, null, null);
        const raw = c.JS_Eval(f.context.?, "function (", 10, "failed-source.js", compile_flags);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw)); try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsError(reason));
        try std.testing.expectEqual(@as(usize, 1), observed.captures);
        try std.testing.expect(c.JS_IsSameValue(f.context.?, reason,
            observed.actual_error orelse return error.MissingActualParseError));
        const frame = try f.item(observed.frames orelse return error.MissingActualParseFrames, 0);
        defer c.JS_FreeValue(f.context.?, frame);
        var filename = c.pi_js_undefined(); var function_name = c.pi_js_undefined();
        defer c.JS_FreeValue(f.context.?, filename); defer c.JS_FreeValue(f.context.?, function_name);
        var line: c_int = 0; var column: c_int = 0;
        var is_native: c_int = -1; var is_constructor: c_int = -1;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ReadCapturedStackFrame(f.context.?, frame,
            &filename, &function_name, &line, &column, &is_native, &is_constructor));
        try f.string(filename, "failed-source.js");
        try std.testing.expect(c.JS_IsNull(function_name));
        try std.testing.expect(line > 0 and column > 0 and is_native == 0 and is_constructor == 0);
        var at: c_int = 471;
        const unexpected = c.JS_PiGetCapturedStackFrameScript(frame, &at);
        defer c.JS_PiFreeScript(unexpected);
        try std.testing.expect(unexpected == null);
        try std.testing.expectEqual(@as(c_int, 471), at);
    }
    f.closeRuntime();
    try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(f.memory));
}
