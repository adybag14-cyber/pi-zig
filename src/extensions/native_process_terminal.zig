//! Source ProcessTerminal: ordinary mutable fields, genuine StdinBuffer,
//! observable stream methods and timers, and private native frontend bindings.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
const keys = @import("../tui/keys.zig");
const Method = enum(c_int) { kittyProtocolActive, modifyOtherKeysActive, start, setupStdinBuffer, queryAndEnableKittyProtocol, handleKeyboardProtocolNegotiationSequence, readKeyboardProtocolNegotiationSequence, setKeyboardProtocolNegotiationBuffer, clearKeyboardProtocolNegotiationBuffer, flushKeyboardProtocolNegotiationBufferAsInput, scheduleKeyboardProtocolNegotiationBufferFlush, clearKeyboardProtocolNegotiationBufferFlushTimer, forwardInputSequence, enableModifyOtherKeys, disableModifyOtherKeys, enableWindowsVTInput, drainInput, stop, write, columns, rows, moveBy, hideCursor, showCursor, clearLine, clearFromCursor, clearScreen, setTitle, setProgramStatus, writeProgramStatus, setProgress, clearProgressInterval, stdinData, stdinPaste, stdinRaw, flushTimer, progressTimer, drainContinue, drainError, drainData, drainExecutor };
const progress_active = "\x1b]9;4;3\x07";
const progress_clear = "\x1b]9;4;0\x07";
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native ProcessTerminal: %s", @as([*:0]const u8, @errorName(err)));
}
fn truthy(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn textEquals(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn invokeVoid(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const returned = try js.invoke(engine, object, name, args);
    engine.freeValue(returned);
}
fn stdout(engine: *js.Engine, value: c.JSValue) !void {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const output = try js.get(engine, process, "stdout");
    defer engine.freeValue(output);
    try invokeVoid(engine, output, "write", &.{value});
}
fn writeText(engine: *js.Engine, text: []const u8) !void {
    const value = try v.text(engine, text);
    defer engine.freeValue(value);
    try stdout(engine, value);
}
fn clearException(engine: *js.Engine) void {
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
}
fn regexp(engine: *js.Engine, pattern: []const u8) !c.JSValue {
    const value = try v.text(engine, pattern);
    defer engine.freeValue(value);
    var args = [_]c.JSValue{value};
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 1, &args));
}
fn testPattern(engine: *js.Engine, value: c.JSValue, pattern: []const u8) !bool {
    const expression = try regexp(engine, pattern);
    defer engine.freeValue(expression);
    const matched = try js.invoke(engine, expression, "test", &.{value});
    defer engine.freeValue(matched);
    return v.truthy(engine, matched);
}
fn parseNegotiation(engine: *js.Engine, value: c.JSValue) !c.JSValue {
    const expression = try regexp(engine, "^\\x1b\\[\\?(\\d+)u$");
    defer engine.freeValue(expression);
    const match = try js.invoke(engine, value, "match", &.{expression});
    defer engine.freeValue(match);
    if (v.truthy(engine, match)) {
        const flags = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 1));
        defer engine.freeValue(flags);
        const number = try js.global(engine, "Number");
        defer engine.freeValue(number);
        const result = try js.object(engine);
        errdefer engine.freeValue(result);
        try js.define(engine, result, "type", try v.text(engine, "kitty-flags"));
        try js.define(engine, result, "flags", try js.invoke(engine, number, "parseInt", &.{ flags, c.JS_NewInt32(engine.context, 10) }));
        return result;
    }
    if (try testPattern(engine, value, "^\\x1b\\[\\?[\\d;]*c$")) {
        const result = try js.object(engine);
        errdefer engine.freeValue(result);
        try js.define(engine, result, "type", try v.text(engine, "device-attributes"));
        return result;
    }
    return c.pi_js_undefined();
}
fn prefix(engine: *js.Engine, value: c.JSValue) !bool {
    return try textEquals(engine, value, "\x1b[") or try testPattern(engine, value, "^\\x1b\\[\\?[\\d;]*$");
}
fn parsedPair(engine: *js.Engine, parsed: c.JSValue, sequence: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "parsed", c.JS_DupValue(engine.context, parsed));
    try js.define(engine, result, "sequence", c.JS_DupValue(engine.context, sequence));
    return result;
}
fn callback(engine: *js.Engine, object: c.JSValue, state: c.JSValue, method_value: Method, name: [*:0]const u8, length: c_int) !c.JSValue {
    var data = [_]c.JSValue{ object, state };
    const value = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(method_value), 2, &data));
    errdefer engine.freeValue(value);
    if (method_value == .drainInput) {
        const intrinsic = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(intrinsic);
        if (c.JS_SetPrototype(engine.context, value, intrinsic) < 0) return js.capture(engine);
    }
    return value;
}
fn call(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const method_value: Method = @enumFromInt(magic);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const object = if (c.JS_IsUndefined(data[0])) receiver else data[0];
    return operation(engine, object, data[1], method_value, args) catch |err| fail(engine, err);
}
fn operation(engine: *js.Engine, object: c.JSValue, state: c.JSValue, method_value: Method, args: []const c.JSValue) !c.JSValue {
    return switch (method_value) {
        .kittyProtocolActive, .modifyOtherKeysActive => terminalOp_kittyProtocolActive(engine, object, state, method_value, args),
        .start => terminalOp_start(engine, object, state, method_value, args),
        .setupStdinBuffer => terminalOp_setupStdinBuffer(engine, object, state, method_value, args),
        .queryAndEnableKittyProtocol => terminalOp_queryAndEnableKittyProtocol(engine, object, state, method_value, args),
        .handleKeyboardProtocolNegotiationSequence => terminalOp_handleKeyboardProtocolNegotiationSequence(engine, object, state, method_value, args),
        .readKeyboardProtocolNegotiationSequence => terminalOp_readKeyboardProtocolNegotiationSequence(engine, object, state, method_value, args),
        .setKeyboardProtocolNegotiationBuffer, .clearKeyboardProtocolNegotiationBuffer => terminalOp_setKeyboardProtocolNegotiationBuffer(engine, object, state, method_value, args),
        .flushKeyboardProtocolNegotiationBufferAsInput => terminalOp_flushKeyboardProtocolNegotiationBufferAsInput(engine, object, state, method_value, args),
        .scheduleKeyboardProtocolNegotiationBufferFlush => terminalOp_scheduleKeyboardProtocolNegotiationBufferFlush(engine, object, state, method_value, args),
        .clearKeyboardProtocolNegotiationBufferFlushTimer => terminalOp_clearKeyboardProtocolNegotiationBufferFlushTimer(engine, object, state, method_value, args),
        .forwardInputSequence => terminalOp_forwardInputSequence(engine, object, state, method_value, args),
        .enableModifyOtherKeys => terminalOp_enableModifyOtherKeys(engine, object, state, method_value, args),
        .disableModifyOtherKeys => terminalOp_disableModifyOtherKeys(engine, object, state, method_value, args),
        .enableWindowsVTInput => terminalOp_enableWindowsVTInput(engine, object, state, method_value, args),
        .stop => terminalOp_stop(engine, object, state, method_value, args),
        .write => terminalOp_write(engine, object, state, method_value, args),
        .columns, .rows => terminalOp_columns(engine, object, state, method_value, args),
        .moveBy => terminalOp_moveBy(engine, object, state, method_value, args),
        .hideCursor, .showCursor, .clearLine, .clearFromCursor, .clearScreen => terminalOp_hideCursor(engine, object, state, method_value, args),
        .setTitle => terminalOp_setTitle(engine, object, state, method_value, args),
        .setProgramStatus => terminalOp_setProgramStatus(engine, object, state, method_value, args),
        .writeProgramStatus => terminalOp_writeProgramStatus(engine, object, state, method_value, args),
        .setProgress => terminalOp_setProgress(engine, object, state, method_value, args),
        .clearProgressInterval => terminalOp_clearProgressInterval(engine, object, state, method_value, args),
        .stdinData => terminalOp_stdinData(engine, object, state, method_value, args),
        .stdinPaste => terminalOp_stdinPaste(engine, object, state, method_value, args),
        .stdinRaw => terminalOp_stdinRaw(engine, object, state, method_value, args),
        .flushTimer => terminalOp_flushTimer(engine, object, state, method_value, args),
        .progressTimer => terminalOp_progressTimer(engine, object, state, method_value, args),
        .drainInput => terminalOp_drainInput(engine, object, state, method_value, args),
        .drainContinue => terminalOp_drainContinue(engine, object, state, method_value, args),
        .drainError => terminalOp_drainError(engine, object, state, method_value, args),
        .drainData => terminalOp_drainData(engine, object, state, method_value, args),
        .drainExecutor => terminalOp_drainExecutor(engine, object, state, method_value, args),
    };
}
fn terminalOp_kittyProtocolActive(engine: *js.Engine, object: c.JSValue, _: c.JSValue, method_value: Method, _: []const c.JSValue) !c.JSValue {
    return js.get(engine, object, if (method_value == .kittyProtocolActive) "_kittyProtocolActive" else "_modifyOtherKeysActive");
}
fn terminalOp_start(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    try v.set(engine, object, "inputHandler", c.JS_DupValue(engine.context, first));
    try v.set(engine, object, "resizeHandler", c.JS_DupValue(engine.context, v.arg(args, 1)));
    var input = try processStream(engine, "stdin");
    defer engine.freeValue(input);
    const raw = try js.get(engine, input, "isRaw");
    defer engine.freeValue(raw);
    try v.set(engine, object, "wasRaw", if (v.truthy(engine, raw)) c.JS_DupValue(engine.context, raw) else c.pi_js_bool(engine.context, 0));
    engine.freeValue(input);
    input = try processStream(engine, "stdin");
    if (try truthy(engine, input, "setRawMode")) {
        engine.freeValue(input);
        input = try processStream(engine, "stdin");
        try invokeVoid(engine, input, "setRawMode", &.{c.pi_js_bool(engine.context, 1)});
    }
    // Read global stream properties again as Source does at each call.
    engine.freeValue(input);
    input = try processStream(engine, "stdin");
    const encoding = try v.text(engine, "utf8");
    defer engine.freeValue(encoding);
    try invokeVoid(engine, input, "setEncoding", &.{encoding});
    engine.freeValue(input);
    input = try processStream(engine, "stdin");
    try invokeVoid(engine, input, "resume", &.{});
    try writeText(engine, "\x1b[?2004h");
    const output = try processStream(engine, "stdout");
    defer engine.freeValue(output);
    const resize = try v.text(engine, "resize");
    defer engine.freeValue(resize);
    const handler = try js.get(engine, object, "resizeHandler");
    defer engine.freeValue(handler);
    try invokeVoid(engine, output, "on", &.{ resize, handler });
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    try refreshDimensions(engine, process);
    try invokeVoid(engine, object, "enableWindowsVTInput", &.{});
    try invokeVoid(engine, object, "queryAndEnableKittyProtocol", &.{});
    return c.pi_js_undefined();
}
fn terminalOp_setupStdinBuffer(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "escapeTimeout", try escapeTimeout(engine));
    const constructor = try js.get(engine, state, "stdinConstructor");
    defer engine.freeValue(constructor);
    var parameters = [_]c.JSValue{options};
    const buffer = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &parameters));
    defer engine.freeValue(buffer);
    try v.set(engine, object, "stdinBuffer", c.JS_DupValue(engine.context, buffer));
    const data_name = try v.text(engine, "data");
    defer engine.freeValue(data_name);
    const data_callback = try callback(engine, object, state, .stdinData, "", 1);
    defer engine.freeValue(data_callback);
    try invokeVoid(engine, buffer, "on", &.{ data_name, data_callback });
    const paste_name = try v.text(engine, "paste");
    defer engine.freeValue(paste_name);
    const paste_callback = try callback(engine, object, state, .stdinPaste, "", 1);
    defer engine.freeValue(paste_callback);
    const current = try js.get(engine, object, "stdinBuffer");
    defer engine.freeValue(current);
    try invokeVoid(engine, current, "on", &.{ paste_name, paste_callback });
    try v.set(engine, object, "stdinDataHandler", try callback(engine, object, state, .stdinRaw, "", 1));
    return c.pi_js_undefined();
}
fn terminalOp_queryAndEnableKittyProtocol(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    try invokeVoid(engine, object, "setupStdinBuffer", &.{});
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const input = try js.get(engine, process, "stdin");
    defer engine.freeValue(input);
    const name = try v.text(engine, "data");
    defer engine.freeValue(name);
    const handler = try js.get(engine, object, "stdinDataHandler");
    defer engine.freeValue(handler);
    try invokeVoid(engine, input, "on", &.{ name, handler });
    try v.set(engine, object, "keyboardProtocolPushed", c.pi_js_bool(engine.context, 1));
    const pending = try js.get(engine, object, "pendingKeyboardProtocolDeviceAttributes");
    defer engine.freeValue(pending);
    const primitive_symbol = try js.get(engine, state, "primitiveSymbol");
    defer engine.freeValue(primitive_symbol);
    try v.set(engine, object, "pendingKeyboardProtocolDeviceAttributes", try arithmetic.add(engine, pending, c.JS_NewInt32(engine.context, 1), primitive_symbol));
    try invokeVoid(engine, object, "clearKeyboardProtocolNegotiationBuffer", &.{});
    const current_process = try js.global(engine, "process");
    defer engine.freeValue(current_process);
    const environment = try js.get(engine, current_process, "env");
    defer engine.freeValue(environment);
    const override = try js.get(engine, environment, "PI_PROGRAM_STATUS");
    defer engine.freeValue(override);
    try v.set(engine, object, "programStatusSupported", c.pi_js_bool(engine.context, @intFromBool(try textEquals(engine, override, "1"))));
    try v.set(engine, object, "programStatusQueryPending", c.pi_js_bool(engine.context, @intFromBool(!try textEquals(engine, override, "1") and !try textEquals(engine, override, "0"))));
    try writeText(engine, if (try truthy(engine, object, "programStatusQueryPending")) "\x1b[>7u\x1b[?u\x1b]7501;?\x1b\\\x1b[c" else "\x1b[>7u\x1b[?u\x1b[c");
    try invokeVoid(engine, object, "writeProgramStatus", &.{});
    return c.pi_js_undefined();
}
fn terminalOp_handleKeyboardProtocolNegotiationSequence(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    try invokeVoid(engine, object, "clearKeyboardProtocolNegotiationBuffer", &.{});
    const kind = try js.get(engine, first, "type");
    defer engine.freeValue(kind);
    if (try textEquals(engine, kind, "device-attributes")) {
        const pending = try js.get(engine, object, "pendingKeyboardProtocolDeviceAttributes");
        defer engine.freeValue(pending);
        if (c.JS_IsNumber(pending) and try v.number(engine, pending) == 0) return c.pi_js_bool(engine.context, 0);
        try v.set(engine, object, "pendingKeyboardProtocolDeviceAttributes", v.numeric(engine, try v.number(engine, pending) - 1));
        const current = try js.get(engine, object, "pendingKeyboardProtocolDeviceAttributes");
        defer engine.freeValue(current);
        if (c.JS_IsNumber(current) and try v.number(engine, current) == 0) try v.set(engine, object, "programStatusQueryPending", c.pi_js_bool(engine.context, 0));
    }
    const current_kind = try js.get(engine, first, "type");
    defer engine.freeValue(current_kind);
    if (try textEquals(engine, current_kind, "kitty-flags")) {
        const flags = try js.get(engine, first, "flags");
        defer engine.freeValue(flags);
        if (!(c.JS_IsNumber(flags) and try v.number(engine, flags) == 0)) {
            try invokeVoid(engine, object, "disableModifyOtherKeys", &.{});
            if (!try truthy(engine, object, "_kittyProtocolActive")) {
                try v.set(engine, object, "_kittyProtocolActive", c.pi_js_bool(engine.context, 1));
                keys.setKittyProtocolActive(true);
            }
        } else try invokeVoid(engine, object, "enableModifyOtherKeys", &.{});
        return c.pi_js_bool(engine.context, 1);
    }
    if (!try truthy(engine, object, "_kittyProtocolActive")) try invokeVoid(engine, object, "enableModifyOtherKeys", &.{});
    return c.pi_js_bool(engine.context, 1);
}
fn terminalOp_readKeyboardProtocolNegotiationSequence(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (try truthy(engine, object, "keyboardProtocolNegotiationBuffer")) {
        const previous = try js.get(engine, object, "keyboardProtocolNegotiationBuffer");
        defer engine.freeValue(previous);
        const primitive_symbol = try js.get(engine, state, "primitiveSymbol");
        defer engine.freeValue(primitive_symbol);
        const combined = try arithmetic.add(engine, previous, first, primitive_symbol);
        defer engine.freeValue(combined);
        const parsed = try parseNegotiation(engine, combined);
        defer engine.freeValue(parsed);
        if (v.truthy(engine, parsed)) {
            try invokeVoid(engine, object, "clearKeyboardProtocolNegotiationBuffer", &.{});
            return parsedPair(engine, parsed, combined);
        }
        if (try prefix(engine, combined)) {
            try invokeVoid(engine, object, "setKeyboardProtocolNegotiationBuffer", &.{combined});
            return v.text(engine, "pending");
        }
        try invokeVoid(engine, object, "flushKeyboardProtocolNegotiationBufferAsInput", &.{});
    }
    const parsed = try parseNegotiation(engine, first);
    defer engine.freeValue(parsed);
    if (v.truthy(engine, parsed)) return parsedPair(engine, parsed, first);
    if (try prefix(engine, first)) {
        try invokeVoid(engine, object, "setKeyboardProtocolNegotiationBuffer", &.{first});
        return v.text(engine, "pending");
    }
    return c.pi_js_undefined();
}
fn terminalOp_setKeyboardProtocolNegotiationBuffer(engine: *js.Engine, object: c.JSValue, _: c.JSValue, method_value: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    try invokeVoid(engine, object, "clearKeyboardProtocolNegotiationBufferFlushTimer", &.{});
    try v.set(engine, object, "keyboardProtocolNegotiationBuffer", if (method_value == .setKeyboardProtocolNegotiationBuffer) c.JS_DupValue(engine.context, first) else try v.text(engine, ""));
    return c.pi_js_undefined();
}
fn terminalOp_flushKeyboardProtocolNegotiationBufferAsInput(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (!try truthy(engine, object, "keyboardProtocolNegotiationBuffer")) return c.pi_js_undefined();
    const sequence = try js.get(engine, object, "keyboardProtocolNegotiationBuffer");
    defer engine.freeValue(sequence);
    try invokeVoid(engine, object, "clearKeyboardProtocolNegotiationBuffer", &.{});
    try invokeVoid(engine, object, "forwardInputSequence", &.{sequence});
    return c.pi_js_undefined();
}
fn terminalOp_scheduleKeyboardProtocolNegotiationBufferFlush(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (!try truthy(engine, object, "keyboardProtocolNegotiationBuffer") or try truthy(engine, object, "keyboardProtocolBufferFlushTimer")) return c.pi_js_undefined();
    const timeout = try js.global(engine, "setTimeout");
    defer engine.freeValue(timeout);
    const timer_callback = try callback(engine, object, state, .flushTimer, "", 0);
    defer engine.freeValue(timer_callback);
    try v.set(engine, object, "keyboardProtocolBufferFlushTimer", try js.call(engine, timeout, c.pi_js_undefined(), &.{ timer_callback, c.JS_NewInt32(engine.context, 150) }));
    return c.pi_js_undefined();
}
fn terminalOp_clearKeyboardProtocolNegotiationBufferFlushTimer(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (!try truthy(engine, object, "keyboardProtocolBufferFlushTimer")) return c.pi_js_undefined();
    const timer = try js.get(engine, object, "keyboardProtocolBufferFlushTimer");
    defer engine.freeValue(timer);
    const clear = try js.global(engine, "clearTimeout");
    defer engine.freeValue(clear);
    const returned = try js.call(engine, clear, c.pi_js_undefined(), &.{timer});
    engine.freeValue(returned);
    try v.set(engine, object, "keyboardProtocolBufferFlushTimer", c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn terminalOp_forwardInputSequence(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (!try truthy(engine, object, "inputHandler")) return c.pi_js_undefined();
    var detect = false;
    if (try textEquals(engine, first, "\r")) {
        const process = try js.global(engine, "process");
        defer engine.freeValue(process);
        const platform = try js.get(engine, process, "platform");
        defer engine.freeValue(platform);
        if (try textEquals(engine, platform, "darwin")) {
            const environment = try js.get(engine, process, "env");
            defer engine.freeValue(environment);
            const program = try js.get(engine, environment, "TERM_PROGRAM");
            defer engine.freeValue(program);
            detect = try textEquals(engine, program, "Apple_Terminal");
        }
        if (!detect) {
            const again = try js.global(engine, "process");
            defer engine.freeValue(again);
            const current_platform = try js.get(engine, again, "platform");
            defer engine.freeValue(current_platform);
            detect = try textEquals(engine, current_platform, "win32");
        }
    }
    const shifted = if (detect) @import("native_process_streams.zig").isShiftPressed(engine) catch |err| blk: {
        if (err == error.JavaScriptException) clearException(engine);
        break :blk false;
    } else false;
    const normalized = if (detect and shifted) try v.text(engine, "\x1b[13;2u") else c.JS_DupValue(engine.context, first);
    defer engine.freeValue(normalized);
    const handler = try js.get(engine, object, "inputHandler");
    defer engine.freeValue(handler);
    const returned = try js.call(engine, handler, object, &.{normalized});
    engine.freeValue(returned);
    return c.pi_js_undefined();
}
fn terminalOp_enableModifyOtherKeys(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (try truthy(engine, object, "_kittyProtocolActive") or try truthy(engine, object, "_modifyOtherKeysActive")) return c.pi_js_undefined();
    try writeText(engine, "\x1b[>4;2m");
    try v.set(engine, object, "_modifyOtherKeysActive", c.pi_js_bool(engine.context, 1));
    return c.pi_js_undefined();
}
fn terminalOp_disableModifyOtherKeys(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (!try truthy(engine, object, "_modifyOtherKeysActive")) return c.pi_js_undefined();
    try writeText(engine, "\x1b[>4;0m");
    try v.set(engine, object, "_modifyOtherKeysActive", c.pi_js_bool(engine.context, 0));
    return c.pi_js_undefined();
}
fn terminalOp_enableWindowsVTInput(engine: *js.Engine, _: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const platform = try js.get(engine, process, "platform");
    defer engine.freeValue(platform);
    if (try textEquals(engine, platform, "win32")) _ = @import("native_process_streams.zig").enableVirtualTerminalInput(engine) catch |err| blk: {
        if (err == error.JavaScriptException) clearException(engine);
        break :blk false;
    };
    return c.pi_js_undefined();
}
fn terminalOp_stop(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    try stop(engine, object, state);
    return c.pi_js_undefined();
}
fn terminalOp_write(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    try stdout(engine, first);
    if (try truthy(engine, object, "writeLogPath")) appendLog(engine, object, first) catch |err| {
        if (err == error.JavaScriptException) clearException(engine);
    };
    return c.pi_js_undefined();
}
fn terminalOp_columns(engine: *js.Engine, _: c.JSValue, _: c.JSValue, method_value: Method, _: []const c.JSValue) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const output = try js.get(engine, process, "stdout");
    defer engine.freeValue(output);
    const value = try js.get(engine, output, if (method_value == .columns) "columns" else "rows");
    if (v.truthy(engine, value)) return value;
    engine.freeValue(value);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const configured = try js.get(engine, environment, if (method_value == .columns) "COLUMNS" else "LINES");
    defer engine.freeValue(configured);
    const number_constructor = try js.global(engine, "Number");
    defer engine.freeValue(number_constructor);
    const converted = try js.call(engine, number_constructor, c.pi_js_undefined(), &.{configured});
    if (v.truthy(engine, converted)) return converted;
    engine.freeValue(converted);
    return c.JS_NewInt32(engine.context, if (method_value == .columns) 80 else 24);
}
fn terminalOp_moveBy(engine: *js.Engine, _: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    const down = try v.number(engine, first) > 0;
    const up = !down and try v.number(engine, first) < 0;
    if (down or up) {
        const start = try v.text(engine, "\x1b[");
        defer engine.freeValue(start);
        const end = try v.text(engine, if (down) "B" else "A");
        defer engine.freeValue(end);
        const distance = if (down) c.JS_DupValue(engine.context, first) else v.numeric(engine, -try v.number(engine, first));
        defer engine.freeValue(distance);
        const text = try v.concat(engine, &.{ start, distance, end });
        defer engine.freeValue(text);
        try stdout(engine, text);
    }
    return c.pi_js_undefined();
}
fn terminalOp_hideCursor(engine: *js.Engine, _: c.JSValue, _: c.JSValue, method_value: Method, _: []const c.JSValue) !c.JSValue {
    try writeText(engine, switch (method_value) {
        .hideCursor => "\x1b[?25l",
        .showCursor => "\x1b[?25h",
        .clearLine => "\x1b[K",
        .clearFromCursor => "\x1b[J",
        .clearScreen => "\x1b[2J\x1b[H",
        else => unreachable,
    });
    return c.pi_js_undefined();
}
fn terminalOp_setTitle(engine: *js.Engine, _: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    const start = try v.text(engine, "\x1b]0;");
    defer engine.freeValue(start);
    const end = try v.text(engine, "\x07");
    defer engine.freeValue(end);
    const text = try v.concat(engine, &.{ start, first, end });
    defer engine.freeValue(text);
    try stdout(engine, text);
    return c.pi_js_undefined();
}
fn terminalOp_setProgramStatus(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    const kind = try js.get(engine, first, "state");
    defer engine.freeValue(kind);
    try v.set(engine, object, "programStatus", if (try textEquals(engine, kind, "clear")) c.pi_js_undefined() else c.JS_DupValue(engine.context, first));
    if (try truthy(engine, object, "programStatusSupported")) try writeStatus(engine, state, first);
    return c.pi_js_undefined();
}
fn terminalOp_writeProgramStatus(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (try truthy(engine, object, "programStatusSupported") and try truthy(engine, object, "programStatus")) {
        const status = try js.get(engine, object, "programStatus");
        defer engine.freeValue(status);
        try writeStatus(engine, state, status);
    }
    return c.pi_js_undefined();
}
fn terminalOp_setProgress(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (v.truthy(engine, first)) {
        try writeText(engine, progress_active);
        if (!try truthy(engine, object, "progressInterval")) {
            const interval = try js.global(engine, "setInterval");
            defer engine.freeValue(interval);
            const tick = try callback(engine, c.pi_js_undefined(), state, .progressTimer, "", 0);
            defer engine.freeValue(tick);
            try v.set(engine, object, "progressInterval", try js.call(engine, interval, c.pi_js_undefined(), &.{ tick, c.JS_NewInt32(engine.context, 1000) }));
        }
    } else {
        try invokeVoid(engine, object, "clearProgressInterval", &.{});
        try writeText(engine, progress_clear);
    }
    return c.pi_js_undefined();
}
fn terminalOp_clearProgressInterval(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    if (!try truthy(engine, object, "progressInterval")) return c.pi_js_bool(engine.context, 0);
    const interval = try js.get(engine, object, "progressInterval");
    defer engine.freeValue(interval);
    const clear = try js.global(engine, "clearInterval");
    defer engine.freeValue(clear);
    const returned = try js.call(engine, clear, c.pi_js_undefined(), &.{interval});
    engine.freeValue(returned);
    try v.set(engine, object, "progressInterval", c.pi_js_undefined());
    return c.pi_js_bool(engine.context, 1);
}
fn terminalOp_stdinData(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (try testPattern(engine, first, "^\\x1b\\]7501;\\?[^\\x07\\x1b]*(?:\\x07|\\x1b\\\\)$")) {
        if (try truthy(engine, object, "programStatusQueryPending")) {
            try v.set(engine, object, "programStatusQueryPending", c.pi_js_bool(engine.context, 0));
            try v.set(engine, object, "programStatusSupported", c.pi_js_bool(engine.context, 1));
            try invokeVoid(engine, object, "writeProgramStatus", &.{});
        }
        return c.pi_js_undefined();
    }
    const negotiation = try js.invoke(engine, object, "readKeyboardProtocolNegotiationSequence", &.{first});
    defer engine.freeValue(negotiation);
    if (try textEquals(engine, negotiation, "pending")) {
        try invokeVoid(engine, object, "scheduleKeyboardProtocolNegotiationBufferFlush", &.{});
        return c.pi_js_undefined();
    }
    if (v.truthy(engine, negotiation)) {
        const parsed = try js.get(engine, negotiation, "parsed");
        defer engine.freeValue(parsed);
        const handled = try js.invoke(engine, object, "handleKeyboardProtocolNegotiationSequence", &.{parsed});
        defer engine.freeValue(handled);
        if (v.truthy(engine, handled)) return c.pi_js_undefined();
    }
    var sequence = if (c.JS_IsNull(negotiation) or c.JS_IsUndefined(negotiation)) c.pi_js_undefined() else try js.get(engine, negotiation, "sequence");
    defer engine.freeValue(sequence);
    if (c.JS_IsNull(sequence) or c.JS_IsUndefined(sequence)) {
        engine.freeValue(sequence);
        sequence = c.JS_DupValue(engine.context, first);
    }
    try invokeVoid(engine, object, "forwardInputSequence", &.{sequence});
    return c.pi_js_undefined();
}
fn terminalOp_stdinPaste(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (try truthy(engine, object, "inputHandler")) {
        const handler = try js.get(engine, object, "inputHandler");
        defer engine.freeValue(handler);
        const start = try v.text(engine, "\x1b[200~");
        defer engine.freeValue(start);
        const end = try v.text(engine, "\x1b[201~");
        defer engine.freeValue(end);
        const text = try v.concat(engine, &.{ start, first, end });
        defer engine.freeValue(text);
        const returned = try js.call(engine, handler, object, &.{text});
        engine.freeValue(returned);
    }
    return c.pi_js_undefined();
}
fn terminalOp_stdinRaw(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    const buffer = try js.get(engine, object, "stdinBuffer");
    defer engine.freeValue(buffer);
    try invokeVoid(engine, buffer, "process", &.{first});
    return c.pi_js_undefined();
}
fn terminalOp_flushTimer(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    try v.set(engine, object, "keyboardProtocolBufferFlushTimer", c.pi_js_undefined());
    try invokeVoid(engine, object, "flushKeyboardProtocolNegotiationBufferAsInput", &.{});
    return c.pi_js_undefined();
}
fn terminalOp_progressTimer(engine: *js.Engine, _: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    try writeText(engine, progress_active);
    return c.pi_js_undefined();
}
fn terminalOp_drainInput(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    return createDrain(engine, object, state, args);
}
fn terminalOp_drainContinue(engine: *js.Engine, object: c.JSValue, state: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    return continueDrain(engine, object, state);
}
fn terminalOp_drainError(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    return rejectDrain(engine, object, first);
}
fn terminalOp_drainData(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, _: []const c.JSValue) !c.JSValue {
    try v.set(engine, object, "lastDataTime", try dateNow(engine));
    return c.pi_js_undefined();
}
fn terminalOp_drainExecutor(engine: *js.Engine, object: c.JSValue, _: c.JSValue, _: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    const timeout = try js.global(engine, "setTimeout");
    defer engine.freeValue(timeout);
    const delay = try js.get(engine, object, "delay");
    defer engine.freeValue(delay);
    const returned = try js.call(engine, timeout, c.pi_js_undefined(), &.{ first, delay });
    engine.freeValue(returned);
    return c.pi_js_undefined();
}

fn writeStatus(engine: *js.Engine, state: c.JSValue, status: c.JSValue) !void {
    const formatter = try js.get(engine, state, "formatStatus");
    defer engine.freeValue(formatter);
    const text = try js.call(engine, formatter, c.pi_js_undefined(), &.{status});
    defer engine.freeValue(text);
    try stdout(engine, text);
}
fn processStream(engine: *js.Engine, name: [*:0]const u8) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    return js.get(engine, process, name);
}
fn refreshDimensions(engine: *js.Engine, process: c.JSValue) !void {
    const platform = try js.get(engine, process, "platform");
    defer engine.freeValue(platform);
    if (try textEquals(engine, platform, "win32")) return;
    const pid = try js.get(engine, process, "pid");
    defer engine.freeValue(pid);
    if (try v.number(engine, pid) <= 0) return;
    const signal = try v.text(engine, "SIGWINCH");
    defer engine.freeValue(signal);
    invokeVoid(engine, process, "kill", &.{ pid, signal }) catch |err| {
        if (err == error.JavaScriptException) clearException(engine) else if (err == error.OutOfMemory) return err;
    };
}
fn escapeTimeout(engine: *js.Engine) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const value = try js.get(engine, environment, "PI_TUI_ESC_TIMEOUT");
    defer engine.freeValue(value);
    const number = try js.global(engine, "Number");
    defer engine.freeValue(number);
    var configured = try js.call(engine, number, c.pi_js_undefined(), &.{value});
    errdefer engine.freeValue(configured);
    const finite = try js.invoke(engine, number, "isFinite", &.{configured});
    defer engine.freeValue(finite);
    if (v.truthy(engine, finite) and try v.number(engine, configured) > 0) return configured;
    engine.freeValue(configured);
    configured = c.pi_js_undefined();
    return c.JS_NewInt32(engine.context, if (try truthy(engine, environment, "SSH_CONNECTION") or try truthy(engine, environment, "SSH_TTY")) 100 else 10);
}
fn stop(engine: *js.Engine, object: c.JSValue, state: c.JSValue) !void {
    const progress = try js.invoke(engine, object, "clearProgressInterval", &.{});
    defer engine.freeValue(progress);
    if (v.truthy(engine, progress)) try writeText(engine, progress_clear);
    if (try truthy(engine, object, "programStatusSupported") and try truthy(engine, object, "programStatus")) {
        const status = try js.object(engine);
        defer engine.freeValue(status);
        try js.define(engine, status, "state", try v.text(engine, "clear"));
        try writeStatus(engine, state, status);
    }
    try v.set(engine, object, "programStatusSupported", c.pi_js_bool(engine.context, 0));
    try v.set(engine, object, "programStatusQueryPending", c.pi_js_bool(engine.context, 0));
    try writeText(engine, "\x1b[?2004l");
    const disable_kitty = try truthy(engine, object, "keyboardProtocolPushed") or try truthy(engine, object, "_kittyProtocolActive");
    try invokeVoid(engine, object, "clearKeyboardProtocolNegotiationBuffer", &.{});
    if (disable_kitty) {
        try writeText(engine, "\x1b[<u");
        try v.set(engine, object, "keyboardProtocolPushed", c.pi_js_bool(engine.context, 0));
        try v.set(engine, object, "_kittyProtocolActive", c.pi_js_bool(engine.context, 0));
        keys.setKittyProtocolActive(false);
    }
    try invokeVoid(engine, object, "disableModifyOtherKeys", &.{});
    if (try truthy(engine, object, "stdinBuffer")) {
        const buffer = try js.get(engine, object, "stdinBuffer");
        defer engine.freeValue(buffer);
        try invokeVoid(engine, buffer, "destroy", &.{});
        try v.set(engine, object, "stdinBuffer", c.pi_js_undefined());
    }
    if (try truthy(engine, object, "stdinDataHandler")) {
        const input = try processStream(engine, "stdin");
        defer engine.freeValue(input);
        const event = try v.text(engine, "data");
        defer engine.freeValue(event);
        const handler = try js.get(engine, object, "stdinDataHandler");
        defer engine.freeValue(handler);
        try invokeVoid(engine, input, "removeListener", &.{ event, handler });
        try v.set(engine, object, "stdinDataHandler", c.pi_js_undefined());
    }
    try v.set(engine, object, "inputHandler", c.pi_js_undefined());
    if (try truthy(engine, object, "resizeHandler")) {
        const output = try processStream(engine, "stdout");
        defer engine.freeValue(output);
        const event = try v.text(engine, "resize");
        defer engine.freeValue(event);
        const handler = try js.get(engine, object, "resizeHandler");
        defer engine.freeValue(handler);
        try invokeVoid(engine, output, "removeListener", &.{ event, handler });
        try v.set(engine, object, "resizeHandler", c.pi_js_undefined());
    }
    var input = try processStream(engine, "stdin");
    defer engine.freeValue(input);
    try invokeVoid(engine, input, "pause", &.{});
    engine.freeValue(input);
    input = try processStream(engine, "stdin");
    if (try truthy(engine, input, "setRawMode")) {
        engine.freeValue(input);
        input = try processStream(engine, "stdin");
        const was_raw = try js.get(engine, object, "wasRaw");
        defer engine.freeValue(was_raw);
        try invokeVoid(engine, input, "setRawMode", &.{was_raw});
    }
}
fn appendLog(engine: *js.Engine, object: c.JSValue, data: c.JSValue) !void {
    const value = try js.get(engine, object, "writeLogPath");
    defer engine.freeValue(value);
    const native_url = @import("native_url.zig");
    const path = if (native_url.isURL(engine, value)) try native_url.filePath(engine, value, @import("builtin").os.tag == .windows) else if (c.JS_IsString(value)) try engine.toString(value) else return;
    defer engine.gpa.free(path);
    const io = engine.native_io orelse return error.NativeProcessTerminalRequiresIO;
    const bytes = try @import("native_process_streams.zig").outputBytes(engine, data);
    defer engine.gpa.free(bytes);
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false });
    defer file.close(io);
    if (@import("builtin").os.tag == .windows) {
        // The shared native helper uses FILE_WRITE_TO_END_OF_FILE, avoiding
        // both metadata read permission and a seek/write race with appenders.
        try @import("../durable/filesystem.zig").appendWindows(file, bytes);
    } else {
        const flags = std.posix.system.fcntl(file.handle, std.posix.F.GETFL, @as(usize, 0));
        if (std.posix.errno(flags) != .SUCCESS) return error.AppendFlagsFailed;
        const mask: u32 = @bitCast(std.posix.O{ .APPEND = true });
        if (std.posix.errno(std.posix.system.fcntl(file.handle, std.posix.F.SETFL, @as(usize, @intCast(flags)) | mask)) != .SUCCESS) return error.AppendFlagsFailed;
        try file.writeStreamingAll(io, bytes);
    }
}
fn logPath(engine: *js.Engine, state: c.JSValue) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const configured = try js.get(engine, environment, "PI_TUI_WRITE_LOG");
    defer engine.freeValue(configured);
    if (!v.truthy(engine, configured)) return v.text(engine, "");
    if (!c.JS_IsString(configured)) return c.JS_DupValue(engine.context, configured);
    return directoryLogPath(engine, state, process, configured) catch |err| {
        if (err == error.JavaScriptException) clearException(engine);
        return c.JS_DupValue(engine.context, configured);
    };
}
fn directoryLogPath(engine: *js.Engine, state: c.JSValue, process: c.JSValue, configured: c.JSValue) !c.JSValue {
    const path = try engine.toString(configured);
    defer engine.gpa.free(path);
    const io = engine.native_io orelse return error.NativeProcessTerminalRequiresIO;
    if ((try std.Io.Dir.cwd().statFile(io, path, .{})).kind != .directory) return c.JS_DupValue(engine.context, configured);
    const date = try js.builtin(engine, "Date", &.{});
    defer engine.freeValue(date);
    const primitive_symbol = try js.get(engine, state, "primitiveSymbol");
    defer engine.freeValue(primitive_symbol);
    var values: [6]c.JSValue = undefined;
    var count: usize = 0;
    defer for (values[0..count]) |value| engine.freeValue(value);
    inline for (.{ "getFullYear", "getMonth", "getDate", "getHours", "getMinutes", "getSeconds" }, 0..) |method_name, index| {
        var value = try js.invoke(engine, date, method_name, &.{});
        defer engine.freeValue(value);
        if (comptime index == 1) {
            const added = try arithmetic.add(engine, value, c.JS_NewInt32(engine.context, 1), primitive_symbol);
            engine.freeValue(value);
            value = added;
        }
        if (comptime index == 0) {
            values[index] = try engine.checked(c.JS_ToString(engine.context, value));
        } else {
            const string = try js.global(engine, "String");
            defer engine.freeValue(string);
            const text = try js.call(engine, string, c.pi_js_undefined(), &.{value});
            defer engine.freeValue(text);
            const zero = try v.text(engine, "0");
            defer engine.freeValue(zero);
            values[index] = try js.invoke(engine, text, "padStart", &.{ c.JS_NewInt32(engine.context, 2), zero });
        }
        count += 1;
    }
    const dash = try v.text(engine, "-");
    defer engine.freeValue(dash);
    const underscore = try v.text(engine, "_");
    defer engine.freeValue(underscore);
    const start = try v.text(engine, "tui-");
    defer engine.freeValue(start);
    const suffix = try v.text(engine, ".log");
    defer engine.freeValue(suffix);
    const pid = try js.get(engine, process, "pid");
    defer engine.freeValue(pid);
    const name = try v.concat(engine, &.{ start, values[0], dash, values[1], dash, values[2], underscore, values[3], dash, values[4], dash, values[5], dash, pid, suffix });
    defer engine.freeValue(name);
    const filename = try engine.toString(name);
    defer engine.gpa.free(filename);
    const joined = try std.fs.path.join(engine.gpa, &.{ path, filename });
    defer engine.gpa.free(joined);
    return v.text(engine, joined);
}
fn dateNow(engine: *js.Engine) !c.JSValue {
    const date = try js.global(engine, "Date");
    defer engine.freeValue(date);
    return js.invoke(engine, date, "now", &.{});
}
fn cleanupDrain(engine: *js.Engine, holder: c.JSValue) !void {
    try v.set(engine, holder, "cleanupStarted", c.pi_js_bool(engine.context, 1));
    const terminal = try js.get(engine, holder, "terminal");
    defer engine.freeValue(terminal);
    const input = try processStream(engine, "stdin");
    defer engine.freeValue(input);
    const event = try v.text(engine, "data");
    defer engine.freeValue(event);
    const listener = try js.get(engine, holder, "onData");
    defer engine.freeValue(listener);
    try invokeVoid(engine, input, "removeListener", &.{ event, listener });
    try v.set(engine, terminal, "inputHandler", try js.get(engine, holder, "previousHandler"));
}
fn rejectDrain(engine: *js.Engine, holder: c.JSValue, reason: c.JSValue) !c.JSValue {
    var failure = c.JS_DupValue(engine.context, reason);
    defer engine.freeValue(failure);
    if (!try truthy(engine, holder, "cleanupStarted")) cleanupDrain(engine, holder) catch |err| {
        if (err != error.JavaScriptException) return err;
        engine.freeValue(failure);
        failure = engine.captured_exception orelse return err;
        engine.captured_exception = null;
    };
    const reject = try js.get(engine, holder, "reject");
    defer engine.freeValue(reject);
    const returned = try js.call(engine, reject, c.pi_js_undefined(), &.{failure});
    engine.freeValue(returned);
    return c.pi_js_undefined();
}
fn finishDrain(engine: *js.Engine, holder: c.JSValue) !c.JSValue {
    try cleanupDrain(engine, holder);
    const resolve = try js.get(engine, holder, "resolve");
    defer engine.freeValue(resolve);
    const returned = try js.call(engine, resolve, c.pi_js_undefined(), &.{c.pi_js_undefined()});
    engine.freeValue(returned);
    return c.pi_js_undefined();
}
fn pollDrain(engine: *js.Engine, holder: c.JSValue, state: c.JSValue) !c.JSValue {
    const now = try dateNow(engine);
    defer engine.freeValue(now);
    const end = try js.get(engine, holder, "endTime");
    defer engine.freeValue(end);
    const left = v.numeric(engine, try v.number(engine, end) - try v.number(engine, now));
    if (try v.number(engine, left) <= 0) return finishDrain(engine, holder);
    const last = try js.get(engine, holder, "lastDataTime");
    defer engine.freeValue(last);
    const idle = try js.get(engine, holder, "idleMs");
    defer engine.freeValue(idle);
    if (try v.number(engine, now) - try v.number(engine, last) >= try v.number(engine, idle)) return finishDrain(engine, holder);
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    try v.set(engine, holder, "delay", try js.invoke(engine, math, "min", &.{ idle, left }));
    const executor = try callback(engine, holder, state, .drainExecutor, "", 1);
    defer engine.freeValue(executor);
    const awaited_value = try js.builtin(engine, "Promise", &.{executor});
    defer engine.freeValue(awaited_value);
    var awaited = c.JS_DupValue(engine.context, awaited_value);
    defer engine.freeValue(awaited);
    var use_original = false;
    if (c.JS_IsPromise(awaited_value)) {
        const constructor = try js.get(engine, awaited_value, "constructor");
        defer engine.freeValue(constructor);
        const intrinsic = try js.get(engine, state, "promiseConstructor");
        defer engine.freeValue(intrinsic);
        use_original = c.JS_IsStrictEqual(engine.context, constructor, intrinsic);
    }
    if (!use_original) {
        var capabilities: [2]c.JSValue = undefined;
        const adopted = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
        defer for (capabilities) |capability| engine.freeValue(capability);
        errdefer engine.freeValue(adopted);
        const returned = try js.call(engine, capabilities[0], c.pi_js_undefined(), &.{awaited_value});
        engine.freeValue(returned);
        engine.freeValue(awaited);
        awaited = adopted;
    }
    const next = try callback(engine, holder, state, .drainContinue, "", 1);
    defer engine.freeValue(next);
    const rejected = try callback(engine, holder, state, .drainError, "", 1);
    defer engine.freeValue(rejected);
    const linked = try engine.checked(c.JS_PromiseThen(engine.context, awaited, next, rejected));
    engine.freeValue(linked);
    return c.pi_js_undefined();
}
fn continueDrain(engine: *js.Engine, holder: c.JSValue, state: c.JSValue) !c.JSValue {
    return pollDrain(engine, holder, state) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return err;
        engine.captured_exception = null;
        defer engine.freeValue(reason);
        return rejectDrain(engine, holder, reason);
    };
}
fn setupDrain(engine: *js.Engine, holder: c.JSValue, terminal: c.JSValue, state: c.JSValue, args: []const c.JSValue) !void {
    const disable_kitty = try truthy(engine, terminal, "keyboardProtocolPushed") or try truthy(engine, terminal, "_kittyProtocolActive");
    try invokeVoid(engine, terminal, "clearKeyboardProtocolNegotiationBuffer", &.{});
    if (disable_kitty) {
        try writeText(engine, "\x1b[<u");
        try v.set(engine, terminal, "keyboardProtocolPushed", c.pi_js_bool(engine.context, 0));
        try v.set(engine, terminal, "_kittyProtocolActive", c.pi_js_bool(engine.context, 0));
        keys.setKittyProtocolActive(false);
    }
    try invokeVoid(engine, terminal, "disableModifyOtherKeys", &.{});
    try js.define(engine, holder, "previousHandler", try js.get(engine, terminal, "inputHandler"));
    try v.set(engine, terminal, "inputHandler", c.pi_js_undefined());
    try js.define(engine, holder, "lastDataTime", try dateNow(engine));
    const on_data = try callback(engine, holder, state, .drainData, "onData", 0);
    defer engine.freeValue(on_data);
    try js.define(engine, holder, "onData", c.JS_DupValue(engine.context, on_data));
    const input = try processStream(engine, "stdin");
    defer engine.freeValue(input);
    const event = try v.text(engine, "data");
    defer engine.freeValue(event);
    try invokeVoid(engine, input, "on", &.{ event, on_data });
    const now = try dateNow(engine);
    defer engine.freeValue(now);
    const primitive_symbol = try js.get(engine, state, "primitiveSymbol");
    defer engine.freeValue(primitive_symbol);
    const maximum = if (c.JS_IsUndefined(v.arg(args, 0))) c.JS_NewInt32(engine.context, 1000) else v.arg(args, 0);
    try js.define(engine, holder, "endTime", try arithmetic.add(engine, now, maximum, primitive_symbol));
    try js.define(engine, holder, "idleMs", c.JS_DupValue(engine.context, if (c.JS_IsUndefined(v.arg(args, 1))) c.JS_NewInt32(engine.context, 50) else args[1]));
    try js.define(engine, holder, "ready", c.pi_js_bool(engine.context, 1));
}
fn createDrain(engine: *js.Engine, terminal: c.JSValue, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var capabilities: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(promise);
    defer for (capabilities) |capability| engine.freeValue(capability);
    const holder = try js.object(engine);
    defer engine.freeValue(holder);
    try js.define(engine, holder, "terminal", c.JS_DupValue(engine.context, terminal));
    try js.define(engine, holder, "resolve", c.JS_DupValue(engine.context, capabilities[0]));
    try js.define(engine, holder, "reject", c.JS_DupValue(engine.context, capabilities[1]));
    setupDrain(engine, holder, terminal, state, args) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return err;
        engine.captured_exception = null;
        defer engine.freeValue(reason);
        const returned = try js.call(engine, capabilities[1], c.pi_js_undefined(), &.{reason});
        engine.freeValue(returned);
        return promise;
    };
    const started = try continueDrain(engine, holder, state);
    engine.freeValue(started);
    return promise;
}
fn construct(engine: *js.Engine, target: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    inline for (.{ "wasRaw", "inputHandler", "resizeHandler", "_kittyProtocolActive", "_modifyOtherKeysActive", "keyboardProtocolPushed", "pendingKeyboardProtocolDeviceAttributes", "keyboardProtocolNegotiationBuffer", "keyboardProtocolBufferFlushTimer", "stdinBuffer", "stdinDataHandler", "progressInterval", "programStatus", "programStatusSupported", "programStatusQueryPending" }) |name| {
        const value = if (comptime std.mem.eql(u8, name, "keyboardProtocolNegotiationBuffer")) try v.text(engine, "") else if (comptime std.mem.eql(u8, name, "pendingKeyboardProtocolDeviceAttributes")) c.JS_NewInt32(engine.context, 0) else if (comptime std.mem.eql(u8, name, "wasRaw") or std.mem.eql(u8, name, "_kittyProtocolActive") or std.mem.eql(u8, name, "_modifyOtherKeysActive") or std.mem.eql(u8, name, "keyboardProtocolPushed") or std.mem.eql(u8, name, "programStatusSupported") or std.mem.eql(u8, name, "programStatusQueryPending")) c.pi_js_bool(engine.context, 0) else c.pi_js_undefined();
        try js.define(engine, object, name, value);
    }
    try js.define(engine, object, "writeLogPath", try logPath(engine, values[0]));
    return object;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const state = try js.object(engine);
    defer engine.freeValue(state);
    try js.define(engine, state, "stdinConstructor", try js.get(engine, exports, "StdinBuffer"));
    try js.define(engine, state, "formatStatus", try js.get(engine, exports, "formatProgramStatus"));
    try js.define(engine, state, "promiseConstructor", try js.global(engine, "Promise"));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, state, "primitiveSymbol", try js.get(engine, symbol, "toPrimitive"));
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "kittyProtocolActive", Method.kittyProtocolActive, 0 }, .{ "modifyOtherKeysActive", Method.modifyOtherKeysActive, 0 }, .{ "start", Method.start, 2 }, .{ "setupStdinBuffer", Method.setupStdinBuffer, 0 }, .{ "queryAndEnableKittyProtocol", Method.queryAndEnableKittyProtocol, 0 }, .{ "handleKeyboardProtocolNegotiationSequence", Method.handleKeyboardProtocolNegotiationSequence, 1 }, .{ "readKeyboardProtocolNegotiationSequence", Method.readKeyboardProtocolNegotiationSequence, 1 }, .{ "setKeyboardProtocolNegotiationBuffer", Method.setKeyboardProtocolNegotiationBuffer, 1 }, .{ "clearKeyboardProtocolNegotiationBuffer", Method.clearKeyboardProtocolNegotiationBuffer, 0 }, .{ "flushKeyboardProtocolNegotiationBufferAsInput", Method.flushKeyboardProtocolNegotiationBufferAsInput, 0 }, .{ "scheduleKeyboardProtocolNegotiationBufferFlush", Method.scheduleKeyboardProtocolNegotiationBufferFlush, 0 }, .{ "clearKeyboardProtocolNegotiationBufferFlushTimer", Method.clearKeyboardProtocolNegotiationBufferFlushTimer, 0 }, .{ "forwardInputSequence", Method.forwardInputSequence, 1 }, .{ "enableModifyOtherKeys", Method.enableModifyOtherKeys, 0 }, .{ "disableModifyOtherKeys", Method.disableModifyOtherKeys, 0 }, .{ "enableWindowsVTInput", Method.enableWindowsVTInput, 0 }, .{ "drainInput", Method.drainInput, 0 }, .{ "stop", Method.stop, 0 }, .{ "write", Method.write, 1 }, .{ "columns", Method.columns, 0 }, .{ "rows", Method.rows, 0 }, .{ "moveBy", Method.moveBy, 1 }, .{ "hideCursor", Method.hideCursor, 0 }, .{ "showCursor", Method.showCursor, 0 }, .{ "clearLine", Method.clearLine, 0 }, .{ "clearFromCursor", Method.clearFromCursor, 0 }, .{ "clearScreen", Method.clearScreen, 0 }, .{ "setTitle", Method.setTitle, 1 }, .{ "setProgramStatus", Method.setProgramStatus, 1 }, .{ "writeProgramStatus", Method.writeProgramStatus, 0 }, .{ "setProgress", Method.setProgress, 1 }, .{ "clearProgressInterval", Method.clearProgressInterval, 0 } }) |entry| {
        const getter = comptime entry[1] == .kittyProtocolActive or entry[1] == .modifyOtherKeysActive or entry[1] == .columns or entry[1] == .rows;
        const value = try callback(engine, c.pi_js_undefined(), state, entry[1], if (getter) "get " ++ entry[0] else entry[0], entry[2]);
        if (getter) {
            const atom = c.JS_NewAtom(engine.context, entry[0]);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, value, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "ProcessTerminal", try @import("native_class.zig").constructor(engine, "ProcessTerminal", 0, prototype, construct, &.{state}));
}
