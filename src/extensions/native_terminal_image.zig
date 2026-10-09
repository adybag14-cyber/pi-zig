//! Source terminal capabilities/cache and admitted Main terminal snapshots.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const private_module = "#pi-native-terminal-image-state";
const Method = enum(c_int) { detectCapabilities, getCapabilities, getTerminalColorMode, resetCapabilitiesCache, setCapabilityOverrides, setCapabilities, getCellDimensions, setCellDimensions, isImageLine, hyperlink };
const Probe = union(enum) { native, function: c.JSValue, value: c.JSValue };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native terminal capabilities: %s", @as([*:0]const u8, @errorName(err)));
}
fn equals(engine: *Engine, value: c.JSValue, bytes: []const u8) !bool {
    const expected = try v.text(engine, bytes);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn testString(engine: *Engine, value: c.JSValue, method_name: [*:0]const u8, bytes: []const u8) !bool {
    const part = try v.text(engine, bytes);
    defer engine.freeValue(part);
    const result = try js.invoke(engine, value, method_name, &.{part});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn lower(engine: *Engine, environment: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try js.get(engine, environment, name);
    defer engine.freeValue(value);
    if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) return v.text(engine, "");
    const result = try js.invoke(engine, value, "toLowerCase", &.{});
    if (v.truthy(engine, result)) return result;
    engine.freeValue(result);
    return v.text(engine, "");
}
fn envTruthy(engine: *Engine, environment: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, environment, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn booleanOverride(engine: *Engine, value: c.JSValue) !?bool {
    if (try equals(engine, value, "1")) return true;
    if (try equals(engine, value, "0")) return false;
    return null;
}
fn capabilities(engine: *Engine, image: ?[]const u8, true_color: bool, hyperlinks: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "images", if (image) |protocol| try v.text(engine, protocol) else c.pi_js_null());
    try js.define(engine, result, "trueColor", c.pi_js_bool(engine.context, @intFromBool(true_color)));
    try js.define(engine, result, "hyperlinks", c.JS_DupValue(engine.context, hyperlinks));
    return result;
}
const ProbeTask = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    done: std.Io.Event = .unset,
    result: ?std.process.RunResult = null,
    failure: ?anyerror = null,
    fn run(self: *ProbeTask) void {
        const command = "tmux display-message -p '#{client_termfeatures}'";
        const argv: []const []const u8 = if (builtin.os.tag == .windows) &.{ "cmd.exe", "/d", "/s", "/c", command } else &.{ "/bin/sh", "-c", command };
        self.result = std.process.run(self.gpa, self.io, .{
            .argv = argv,
            .environ_map = self.environment,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .create_no_window = true,
        }) catch |err| failed: {
            self.failure = err;
            break :failed null;
        };
        self.done.set(self.io);
    }
};
fn nativeProbe(engine: *Engine, environment: c.JSValue) !bool {
    const io = engine.native_io orelse return false;
    var map: std.process.Environ.Map = .init(engine.gpa);
    defer map.deinit();
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, environment, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (properties[0..count]) |entry| {
        const key = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
        defer engine.freeValue(key);
        const value = try engine.checked(c.JS_GetProperty(engine.context, environment, entry.atom));
        defer engine.freeValue(value);
        if (c.JS_IsUndefined(value)) continue;
        const name = try engine.toString(key);
        defer engine.gpa.free(name);
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        try map.put(name, text);
    }
    var task: ProbeTask = .{ .gpa = engine.gpa, .io = io, .environment = &map };
    var future = io.concurrent(ProbeTask.run, .{&task}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    const deadline = std.Io.Timeout{ .deadline = .fromNow(io, .{ .raw = .fromMilliseconds(250), .clock = .awake }) };
    task.done.waitTimeout(io, deadline) catch {
        future.cancel(io);
        if (task.result) |result| {
            engine.gpa.free(result.stdout);
            engine.gpa.free(result.stderr);
        }
        return false;
    };
    future.await(io);
    if (task.failure) |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    }
    const result = task.result orelse return false;
    defer engine.gpa.free(result.stdout);
    defer engine.gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return false;
    return hasHyperlinkFeature(result.stdout);
}
fn hasHyperlinkFeature(output: []const u8) bool {
    var features = std.mem.splitScalar(u8, output, ',');
    while (features.next()) |feature| {
        const view = std.unicode.Utf8View.init(feature) catch continue;
        var iterator = view.iterator();
        var start: ?usize = null;
        var end: usize = 0;
        while (iterator.i < feature.len) {
            const at = iterator.i;
            const cp = iterator.nextCodepoint().?;
            if (cp > 0xffff or !@import("../tui/utf16_input.zig").State.whitespace(@intCast(cp))) {
                if (start == null) start = at;
                end = iterator.i;
            }
        }
        if (start) |at| if (std.mem.eql(u8, feature[at..end], "hyperlinks")) return true;
    }
    return false;
}
fn probeValue(engine: *Engine, probe: Probe, environment: c.JSValue) !c.JSValue {
    return switch (probe) {
        .native => c.pi_js_bool(engine.context, @intFromBool(try nativeProbe(engine, environment))),
        .function => |function| js.call(engine, function, c.pi_js_undefined(), &.{}),
        .value => |value| c.JS_DupValue(engine.context, value),
    };
}
fn detectBase(engine: *Engine, process: c.JSValue, environment: c.JSValue, probe: Probe) !c.JSValue {
    const term_program = try lower(engine, environment, "TERM_PROGRAM");
    defer engine.freeValue(term_program);
    const terminal_emulator = try lower(engine, environment, "TERMINAL_EMULATOR");
    defer engine.freeValue(terminal_emulator);
    const term = try lower(engine, environment, "TERM");
    defer engine.freeValue(term);
    const color_term = try lower(engine, environment, "COLORTERM");
    defer engine.freeValue(color_term);
    const true_color_hint = try equals(engine, color_term, "truecolor") or try equals(engine, color_term, "24bit") or try testString(engine, term, "endsWith", "-direct");
    const platform = try js.get(engine, process, "platform");
    defer engine.freeValue(platform);
    const windows_console = try equals(engine, platform, "win32");
    if (try envTruthy(engine, environment, "TMUX") or try testString(engine, term, "startsWith", "tmux")) {
        const hyperlink = try probeValue(engine, probe, environment);
        defer engine.freeValue(hyperlink);
        return capabilities(engine, null, true_color_hint, hyperlink);
    }
    if (try testString(engine, term, "startsWith", "screen")) return capabilities(engine, null, true_color_hint, c.pi_js_bool(engine.context, 0));
    if (try equals(engine, term_program, "herdr")) return capabilities(engine, null, true_color_hint, c.pi_js_bool(engine.context, 1));
    if (try envTruthy(engine, environment, "KITTY_WINDOW_ID") or try equals(engine, term_program, "kitty")) return capabilities(engine, "kitty", true, c.pi_js_bool(engine.context, 1));
    if (try equals(engine, term_program, "ghostty") or try testString(engine, term, "includes", "ghostty") or try envTruthy(engine, environment, "GHOSTTY_RESOURCES_DIR")) return capabilities(engine, "kitty", true, c.pi_js_bool(engine.context, 1));
    if (try envTruthy(engine, environment, "WEZTERM_PANE") or try equals(engine, term_program, "wezterm")) return capabilities(engine, "kitty", true, c.pi_js_bool(engine.context, 1));
    if (try equals(engine, term_program, "warpterminal") or try envTruthy(engine, environment, "WARP_SESSION_ID") or try envTruthy(engine, environment, "WARP_TERMINAL_SESSION_UUID")) return capabilities(engine, "kitty", true, c.pi_js_bool(engine.context, 1));
    if (try envTruthy(engine, environment, "ITERM_SESSION_ID") or try equals(engine, term_program, "iterm.app")) return capabilities(engine, "iterm2", true, c.pi_js_bool(engine.context, 1));
    if (try envTruthy(engine, environment, "WT_SESSION") or try equals(engine, term_program, "alacritty") or try equals(engine, term_program, "vscode") or try equals(engine, term_program, "zed")) return capabilities(engine, null, true, c.pi_js_bool(engine.context, 1));
    if (try equals(engine, terminal_emulator, "jetbrains-jediterm")) return capabilities(engine, null, true, c.pi_js_bool(engine.context, 0));
    return capabilities(engine, null, if (windows_console) true else true_color_hint, c.pi_js_bool(engine.context, 0));
}
fn detect(engine: *Engine, original_probe: Probe) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    if (!c.JS_IsObject(process)) return error.NativeTerminalProcessUnavailable;
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const hyperlink = try js.get(engine, environment, "PI_HYPERLINKS");
    defer engine.freeValue(hyperlink);
    const override = try booleanOverride(engine, hyperlink);
    const detected = try detectBase(engine, process, environment, if (override) |value| .{ .value = c.pi_js_bool(engine.context, @intFromBool(value)) } else original_probe);
    errdefer engine.freeValue(detected);
    const image = try lower(engine, environment, "PI_IMAGE_PROTOCOL");
    defer engine.freeValue(image);
    if (try equals(engine, image, "kitty") or try equals(engine, image, "iterm2")) try v.set(engine, detected, "images", c.JS_DupValue(engine.context, image)) else if (try equals(engine, image, "none") or try equals(engine, image, "0")) try v.set(engine, detected, "images", c.pi_js_null());
    const color = try js.get(engine, environment, "PI_TRUE_COLOR");
    defer engine.freeValue(color);
    if (try booleanOverride(engine, color)) |value| try v.set(engine, detected, "trueColor", c.pi_js_bool(engine.context, @intFromBool(value)));
    if (override) |value| try v.set(engine, detected, "hyperlinks", c.pi_js_bool(engine.context, @intFromBool(value)));
    return detected;
}
fn getCapabilities(engine: *Engine, state: c.JSValue) !c.JSValue {
    const cached = try js.get(engine, state, "cachedCapabilities");
    if (v.truthy(engine, cached)) return cached;
    engine.freeValue(cached);
    const overrides = try js.get(engine, state, "capabilityOverrides");
    defer engine.freeValue(overrides);
    const hyperlink = try js.get(engine, overrides, "hyperlinks");
    defer engine.freeValue(hyperlink);
    const detected = try detect(engine, if (c.JS_IsUndefined(hyperlink)) .native else .{ .value = hyperlink });
    defer engine.freeValue(detected);
    const merged = try js.spread(engine, detected);
    errdefer engine.freeValue(merged);
    try js.spreadInto(engine, merged, overrides);
    try v.set(engine, state, "cachedCapabilities", c.JS_DupValue(engine.context, merged));
    return merged;
}
fn methodCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, data[0], @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, state: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    switch (operation) {
        .detectCapabilities => return detect(engine, if (c.JS_IsUndefined(v.arg(args, 0))) .native else .{ .function = v.arg(args, 0) }),
        .getCapabilities => return getCapabilities(engine, state),
        .getTerminalColorMode => {
            const caps = if (c.JS_IsUndefined(v.arg(args, 0))) try getCapabilities(engine, state) else c.JS_DupValue(engine.context, v.arg(args, 0));
            defer engine.freeValue(caps);
            const color = try js.get(engine, caps, "trueColor");
            defer engine.freeValue(color);
            return v.text(engine, if (v.truthy(engine, color)) "truecolor" else "256color");
        },
        .resetCapabilitiesCache => try v.set(engine, state, "cachedCapabilities", c.pi_js_null()),
        .setCapabilities => try v.set(engine, state, "cachedCapabilities", c.JS_DupValue(engine.context, v.arg(args, 0))),
        .getCellDimensions => return js.get(engine, state, "cellDimensions"),
        .setCellDimensions => try v.set(engine, state, "cellDimensions", c.JS_DupValue(engine.context, v.arg(args, 0))),
        .setCapabilityOverrides => {
            const previous = try js.get(engine, state, "capabilityOverrides");
            defer engine.freeValue(previous);
            var equal = true;
            inline for (.{ "images", "trueColor", "hyperlinks" }) |name| if (equal) {
                const left = try js.get(engine, previous, name);
                defer engine.freeValue(left);
                const right = try js.get(engine, v.arg(args, 0), name);
                defer engine.freeValue(right);
                equal = c.JS_IsStrictEqual(engine.context, left, right);
            };
            if (!equal) {
                try v.set(engine, state, "capabilityOverrides", try js.spread(engine, v.arg(args, 0)));
                try v.set(engine, state, "cachedCapabilities", c.pi_js_null());
            }
        },
        .isImageLine => return c.pi_js_bool(engine.context, @intFromBool(try testString(engine, v.arg(args, 0), "startsWith", "\x1b_G") or try testString(engine, v.arg(args, 0), "startsWith", "\x1b]1337;File=") or try testString(engine, v.arg(args, 0), "includes", "\x1b_G") or try testString(engine, v.arg(args, 0), "includes", "\x1b]1337;File="))),
        .hyperlink => {
            const opening = try v.text(engine, "\x1b]8;;");
            defer engine.freeValue(opening);
            const separator = try v.text(engine, "\x1b\\");
            defer engine.freeValue(separator);
            const closing = try v.text(engine, "\x1b]8;;\x1b\\");
            defer engine.freeValue(closing);
            return v.concat(engine, &.{ opening, v.arg(args, 1), separator, v.arg(args, 0), closing });
        },
    }
    return c.pi_js_undefined();
}
fn stateFor(engine: *Engine) !c.JSValue {
    const state = engine.native_module_values.get(private_module) orelse return error.NativeTerminalCapabilitiesUnavailable;
    return c.JS_DupValue(engine.context, state);
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const state = try js.object(engine);
    defer engine.freeValue(state);
    try js.define(engine, state, "cachedCapabilities", c.pi_js_null());
    try js.define(engine, state, "capabilityOverrides", try js.object(engine));
    const dimensions = try js.object(engine);
    var transferred = false;
    defer if (!transferred) engine.freeValue(dimensions);
    try js.define(engine, dimensions, "widthPx", v.numeric(engine, 9));
    try js.define(engine, dimensions, "heightPx", v.numeric(engine, 18));
    transferred = true;
    try js.define(engine, state, "cellDimensions", dimensions);
    inline for (.{ "admittedCapabilitiesSignature", "admittedCellSignature" }) |name| try js.define(engine, state, name, c.pi_js_undefined());
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .setCapabilities, .setCapabilityOverrides, .setCellDimensions, .isImageLine => 1,
            .hyperlink => 2,
            else => 0,
        };
        var data = [_]c.JSValue{state};
        try js.define(engine, exports, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, length, @intCast(field.value), 1, &data)));
    }
    try engine.registerValueModule(private_module, state);
}
const Admission = struct {
    caps: c.JSValue,
    dims: c.JSValue,
    caps_signature: ?i32 = null,
    dims_signature: ?[32]u8 = null,
    fn deinit(self: Admission, engine: *Engine) void {
        engine.freeValue(self.caps);
        engine.freeValue(self.dims);
    }
};
fn parseAdmission(engine: *Engine, snapshot: c.JSValue) !Admission {
    const caps = try js.get(engine, snapshot, "terminalCapabilities");
    errdefer engine.freeValue(caps);
    const dims = try js.get(engine, snapshot, "cellDimensions");
    errdefer engine.freeValue(dims);
    var output: Admission = .{ .caps = caps, .dims = dims };
    if (!c.JS_IsUndefined(caps)) {
        if (!c.JS_IsObject(caps) or c.JS_IsArray(caps)) return error.InvalidExtensionContext;
        const image = try js.get(engine, caps, "images");
        defer engine.freeValue(image);
        var signature: i32 = if (c.JS_IsNull(image)) 0 else if (try equals(engine, image, "kitty")) 1 else if (try equals(engine, image, "iterm2")) 2 else return error.InvalidExtensionContext;
        inline for (.{ "trueColor", "hyperlinks" }, 0..) |name, index| {
            const value = try js.get(engine, caps, name);
            defer engine.freeValue(value);
            if (!c.JS_IsBool(value)) return error.InvalidExtensionContext;
            if (v.truthy(engine, value)) signature |= @as(i32, 4) << @intCast(index);
        }
        output.caps_signature = signature;
    }
    if (!c.JS_IsUndefined(dims)) {
        if (!c.JS_IsObject(dims) or c.JS_IsArray(dims)) return error.InvalidExtensionContext;
        var values: [2]f64 = undefined;
        inline for (.{ "widthPx", "heightPx" }, 0..) |name, index| {
            const value = try js.get(engine, dims, name);
            defer engine.freeValue(value);
            if (!c.JS_IsNumber(value)) return error.InvalidExtensionContext;
            values[index] = try v.number(engine, value);
            if (!std.math.isFinite(values[index]) or values[index] <= 0) return error.InvalidExtensionContext;
        }
        output.dims_signature = std.fmt.bytesToHex(std.mem.asBytes(&values).*, .lower);
    }
    return output;
}
pub fn validateAdmittedContext(engine: *Engine, snapshot: c.JSValue) !void {
    const admission = try parseAdmission(engine, snapshot);
    defer admission.deinit(engine);
}
/// Main-admitted snapshots only; no environment or terminal query occurs here.
pub fn hydrateAdmittedContext(engine: *Engine, snapshot: c.JSValue) !void {
    const admission = try parseAdmission(engine, snapshot);
    defer admission.deinit(engine);
    const state = try stateFor(engine);
    defer engine.freeValue(state);
    if (admission.caps_signature) |signature| {
        const previous = try js.get(engine, state, "admittedCapabilitiesSignature");
        defer engine.freeValue(previous);
        const encoded = c.JS_NewInt32(engine.context, signature);
        if (!c.JS_IsStrictEqual(engine.context, previous, encoded)) {
            try v.set(engine, state, "cachedCapabilities", c.JS_DupValue(engine.context, admission.caps));
            try v.set(engine, state, "admittedCapabilitiesSignature", encoded);
        }
    }
    if (admission.dims_signature) |signature| {
        const encoded = try v.text(engine, &signature);
        defer engine.freeValue(encoded);
        const previous = try js.get(engine, state, "admittedCellSignature");
        defer engine.freeValue(previous);
        if (!c.JS_IsStrictEqual(engine.context, previous, encoded)) {
            try v.set(engine, state, "cellDimensions", c.JS_DupValue(engine.context, admission.dims));
            try v.set(engine, state, "admittedCellSignature", c.JS_DupValue(engine.context, encoded));
        }
    }
}
test "Source6fb terminal capabilities original environment precedence probes Unicode case overrides identities and public shape" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("../tui/fixtures/terminal-capabilities-original-6fb.json");
    try js.define(engine, root, "terminalFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "terminal-capabilities-original-6fb.json")));
    const result = engine.evalModule(
        \\import * as api from'pi-tui';for(const[index,item]of terminalFixture.cases.entries()){globalThis.process={platform:item.platform,env:item.environment};let probeCalls=0;const result=api.detectCapabilities(()=>{probeCalls++;return item.probeValue}),actual={result,probeCalls},expected={result:item.result,probeCalls:item.probeCalls};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));}
        \\globalThis.process={platform:'win32',env:{}};for(const[index,item]of terminalFixture.structural.entries()){let actual;try{actual=new Function(...Object.keys(api),'"use strict";'+item.script)(...Object.values(api))}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}for(const[name,expected]of Object.entries(terminalFixture.shape)){const actual={name:api[name].name,length:api[name].length};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({name,actual,expected}));}for(const item of terminalFixture.hyperlinks)if(api.hyperlink(String.fromCharCode(...item.text),String.fromCharCode(...item.url))!==String.fromCharCode(...item.result))throw Error('hyperlink');for(const line of['\x1b_Gabc','prefix\x1b]1337;File=abc','plain'])if(api.isImageLine(line)!==(line!=='plain'))throw Error('image predicate');
    , "terminal-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Source terminal capabilities: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb terminal capabilities admitted context preserves explicit guest overrides until actual independent snapshot changes" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try @import("native_bindings.zig").Bindings.init(std.testing.allocator, engine);
    defer bindings.deinit();
    const initial = "{\"terminalCapabilities\":{\"images\":\"kitty\",\"trueColor\":true,\"hyperlinks\":false},\"cellDimensions\":{\"widthPx\":9,\"heightPx\":18}}";
    try bindings.setContext(initial);
    try bindings.loadFactory(
        \\import{getCapabilities,getCellDimensions}from'pi-tui';if(getCapabilities().images!=='kitty'||getCellDimensions().heightPx!==18)throw Error('module evaluated before terminal admission');export default pi=>{if(getCapabilities().hyperlinks||getCellDimensions().widthPx!==9)throw Error('factory evaluated before terminal admission');globalThis.terminalFactoryAdmitted=true};
    , "terminal-admitted-factory.mjs");
    const first = try engine.evalModule(
        \\import{getCapabilities,setCapabilities,getCellDimensions,setCellDimensions}from'pi-tui';if(!terminalFactoryAdmitted||getCapabilities().images!=='kitty'||getCapabilities().hyperlinks||getCellDimensions().widthPx!==9)throw Error('initial admission');globalThis.explicitCaps={images:'iterm2',trueColor:false,hyperlinks:true};globalThis.explicitDims={widthPx:11,heightPx:22};setCapabilities(explicitCaps);setCellDimensions(explicitDims);
    , "terminal-admitted-initial.mjs");
    engine.freeValue(first);
    try bindings.setContext(initial);
    const same = try engine.evalModule(
        \\import{getCapabilities,getCellDimensions}from'pi-tui';if(getCapabilities()!==explicitCaps||getCellDimensions()!==explicitDims)throw Error('identical admission erased override');
    , "terminal-admitted-same.mjs");
    engine.freeValue(same);
    try bindings.setContext("{\"terminalCapabilities\":{\"images\":null,\"trueColor\":false,\"hyperlinks\":false},\"cellDimensions\":{\"widthPx\":9,\"heightPx\":18}}");
    const changed = try engine.evalModule(
        \\import{getCapabilities,getCellDimensions}from'pi-tui';if(getCapabilities().images!==null||getCapabilities().trueColor||getCellDimensions()!==explicitDims)throw Error('independent capability admission');
    , "terminal-admitted-changed.mjs");
    engine.freeValue(changed);
    try bindings.setContext("{\"cellDimensions\":{\"widthPx\":10,\"heightPx\":20}}");
    const dimensions = try engine.evalModule(
        \\import{getCapabilities,getCellDimensions}from'pi-tui';if(getCapabilities().images!==null||getCellDimensions().widthPx!==10)throw Error('independent cell admission');
    , "terminal-admitted-dimensions.mjs");
    engine.freeValue(dimensions);
    for ([_][]const u8{
        "{\"terminalCapabilities\":null}",
        "{\"terminalCapabilities\":[]}",
        "{\"terminalCapabilities\":{\"images\":\"bad\",\"trueColor\":true,\"hyperlinks\":false}}",
        "{\"terminalCapabilities\":{\"images\":null,\"trueColor\":1,\"hyperlinks\":false}}",
        "{\"cellDimensions\":{\"widthPx\":0,\"heightPx\":18}}",
        "{\"cellDimensions\":{\"widthPx\":9,\"heightPx\":\"18\"}}",
    }) |invalid| try std.testing.expectError(error.InvalidExtensionContext, bindings.setContext(invalid));
    const preserved = try engine.evalModule(
        \\import{getCapabilities,getCellDimensions}from'pi-tui';if(getCapabilities().images!==null||getCellDimensions().widthPx!==10)throw Error('invalid admission changed cached state');
    , "terminal-admitted-invalid-preserved.mjs");
    engine.freeValue(preserved);
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const allocationError = @import("native_text_component.zig").allocationError;
    const bindings = @import("native_bindings.zig").Bindings.init(gpa, engine) catch |err| return allocationError(engine, err);
    defer bindings.deinit();
    const context = "{\"terminalCapabilities\":{\"images\":\"kitty\",\"trueColor\":true,\"hyperlinks\":false},\"cellDimensions\":{\"widthPx\":9,\"heightPx\":18}}";
    bindings.setContext(context) catch |err| return allocationError(engine, err);
    const result = engine.evalModule(
        \\import{getCapabilities,setCapabilities,getCellDimensions,setCellDimensions,setCapabilityOverrides,resetCapabilitiesCache,detectCapabilities,hyperlink}from'pi-tui';globalThis.process={platform:'win32',env:{TERM_PROGRAM:'Kitty'}};const initial=getCapabilities();if(initial.images!=='kitty')throw Error('admission');globalThis.explicitTerminalCaps={images:'iterm2',trueColor:false,hyperlinks:true};globalThis.explicitTerminalDims={widthPx:13,heightPx:26};setCapabilities(explicitTerminalCaps);setCellDimensions(explicitTerminalDims);hyperlink('界😀','https://example.invalid');const tmux=detectCapabilities(()=>true);if(tmux.images!=='kitty')throw Error('environment');
    , "terminal-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(result);
    bindings.setContext(context) catch |err| return allocationError(engine, err);
    c.JS_RunGC(engine.runtime);
    const retained = engine.evalModule(
        \\import{getCapabilities,getCellDimensions,setCapabilityOverrides,resetCapabilitiesCache}from'pi-tui';if(getCapabilities()!==explicitTerminalCaps||getCellDimensions()!==explicitTerminalDims)throw Error('override replaced');setCapabilityOverrides({hyperlinks:false,extra:{value:'retained'}});resetCapabilitiesCache();if(getCapabilities().images!=='kitty'||getCapabilities().hyperlinks)throw Error('cache rebuild');delete globalThis.explicitTerminalCaps;delete globalThis.explicitTerminalDims;
    , "terminal-allocation-retained.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb terminal capabilities all allocation failures release admitted snapshots cache overrides and retained module graphs" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "Source6fb terminal capabilities default probe parses Source ECMAScript whitespace and exact feature names" {
    try std.testing.expect(hasHyperlinkFeature("256, RGB, hyperlinks\n"));
    try std.testing.expect(hasHyperlinkFeature("foo,\xc2\xa0hyperlinks\xef\xbb\xbf,bar"));
    try std.testing.expect(hasHyperlinkFeature("bad\xff,hyperlinks"));
    try std.testing.expect(!hasHyperlinkFeature("Hyperlinks, nohyperlinks, hyperlinks-extra"));
    try std.testing.expect(!hasHyperlinkFeature("\xc2\x85hyperlinks"));
}
test "Source6fb terminal capabilities standalone default probe uses owned native IO and the supplied process environment" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const name = if (builtin.os.tag == .windows) "tmux.cmd" else "tmux";
    const script = if (builtin.os.tag == .windows) "@echo off\r\necho foo, hyperlinks, bar\r\n" else "#!/bin/sh\nprintf 'foo, hyperlinks, bar\\n'\n";
    const file = try temporary.dir.createFile(io, name, .{});
    try file.writeStreamingAll(io, script);
    if (builtin.os.tag != .windows) try file.setPermissions(io, .fromMode(0o755));
    file.close(io);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(io, &path_buffer);
    const directory = path_buffer[0..path_length];
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", directory);
    try environment.put("TMUX", "source-probe-fixture");
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("native_process.zig").install(engine, io, &environment, &.{"native-terminal-sdk"});
    try @import("native_tui.zig").install(engine);
    const result = engine.evalModule(
        \\import{detectCapabilities,getCapabilities,resetCapabilitiesCache}from'pi-tui';const first=detectCapabilities();if(first.images!==null||!first.hyperlinks)throw Error('default native tmux probe');resetCapabilitiesCache();const cached=getCapabilities();if(!cached.hyperlinks||cached!==getCapabilities())throw Error('default probe cache');
    , "terminal-default-native-probe.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Default native capability probe: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
