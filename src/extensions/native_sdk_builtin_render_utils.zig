//! Native bodies from original core/tools/render-utils.ts. Private composition.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
pub const Scope = temporary.Scope;
const c = em.c;
const paths = @import("node_path.zig");
const flavor: paths.Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
const State = enum { ansi, binary, carriage_return, tab, windows_path };

pub fn tui(scope: *Scope) !c.JSValue {
    try @import("native_tui.zig").install(scope.engine);
    return scope.engine.native_module_values.get("@earendil-works/pi-tui").?;
}
pub fn optional(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temporary.nullish(object)) c.pi_js_undefined() else scope.get(object, name);
}
pub fn str(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsString(value)) value else if (temporary.nullish(value)) scope.text("") else c.pi_js_null();
}
pub fn fg(scope: *Scope, theme: c.JSValue, token: []const u8, value: c.JSValue) !c.JSValue {
    return scope.invoke(theme, "fg", &.{ try scope.text(token), value });
}
pub fn title(scope: *Scope, theme: c.JSValue, value: []const u8) !c.JSValue {
    const color = try scope.get(theme, "fg");
    const token = try scope.text("toolTitle");
    const bold = try scope.invoke(theme, "bold", &.{try scope.text(value)});
    return scope.call(color, theme, &.{ token, bold });
}
pub fn surround(scope: *Scope, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    return scope.concat(try scope.concat(try scope.text(prefix), try scope.stringify(value)), try scope.text(suffix));
}
pub fn shortenPath(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(value)) return scope.text("");
    const home = try scope.own(try @import("native_home.zig").get(scope.engine));
    if (!scope.truthy(try scope.invoke(value, "startsWith", &.{home}))) return value;
    return scope.concat(try scope.text("~"), try scope.invoke(value, "slice", &.{try scope.get(home, "length")}));
}
pub fn normalizePath(scope: *Scope, input: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var value = input;
    if (builtin.os.tag == .windows) {
        if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("/")})) and !scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("//")})) and !scope.truthy(try scope.invoke(value, "includes", &.{try scope.text("\\")}))) {
            const matched = try scope.invoke(value, "match", &.{try regexp(scope, .windows_path)});
            if (scope.truthy(matched)) {
                const tail = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, matched, 2)));
                const suffix = if (temporary.nullish(tail)) c.pi_js_undefined() else try scope.invoke(tail, "replaceAll", &.{ try scope.text("/"), try scope.text("\\") });
                const drive = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, matched, 1)));
                value = try scope.concat(try scope.concat(try scope.invoke(drive, "toUpperCase", &.{}), try scope.text(":\\")), if (temporary.nullish(suffix)) try scope.text("") else suffix);
            }
        }
    }
    // Source evaluates the home default even when the input has no tilde.
    const home = try scope.own(try @import("native_home.zig").get(engine));
    if (scope.equal(value, try scope.text("~"))) return home;
    if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("~/")})) or (builtin.os.tag == .windows and scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("~\\")})))) {
        const base = try engine.toString(home);
        defer engine.gpa.free(base);
        const suffix = try engine.toString(try scope.invoke(value, "slice", &.{c.JS_NewInt32(engine.context, 2)}));
        defer engine.gpa.free(suffix);
        const joined = try paths.join(engine.gpa, &.{ base, suffix }, flavor);
        defer engine.gpa.free(joined);
        return scope.text(joined);
    }
    if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("file://")}))) {
        try @import("node_url.zig").install(engine);
        const exports = engine.native_module_values.get("node:url").?;
        return scope.call(try scope.get(exports, "fileURLToPath"), c.pi_js_undefined(), &.{value});
    }
    return value;
}
pub fn resolvePath(scope: *Scope, input: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const normalized = try normalizePath(scope, input);
    const base = try normalizePath(scope, cwd);
    const a = try scope.engine.toString(normalized);
    defer scope.engine.gpa.free(a);
    const b = try scope.engine.toString(base);
    defer scope.engine.gpa.free(b);
    const current = try sdk.cwd(scope.engine);
    defer scope.engine.gpa.free(current);
    const resolved = try paths.resolve(scope.engine.gpa, current, &.{ b, a }, flavor);
    defer scope.engine.gpa.free(resolved);
    return scope.text(resolved);
}
pub fn linkPath(scope: *Scope, styled: c.JSValue, path: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const exports = try tui(scope);
    const caps = try scope.call(try scope.get(exports, "getCapabilities"), c.pi_js_undefined(), &.{});
    if (!scope.truthy(try scope.get(caps, "hyperlinks"))) return styled;
    const absolute = try resolvePath(scope, path, cwd);
    const hyperlink = try scope.get(exports, "hyperlink");
    try @import("node_url.zig").install(scope.engine);
    const url_module = scope.engine.native_module_values.get("node:url").?;
    const url = try scope.call(try scope.get(url_module, "pathToFileURL"), c.pi_js_undefined(), &.{absolute});
    return scope.call(hyperlink, c.pi_js_undefined(), &.{ styled, try scope.get(url, "href") });
}
pub fn invalidArg(scope: *Scope, theme: c.JSValue) !c.JSValue {
    return fg(scope, theme, "error", try scope.text("[invalid arg]"));
}
pub fn renderToolPath(scope: *Scope, raw: c.JSValue, theme: c.JSValue, cwd: c.JSValue, fallback: c.JSValue) !c.JSValue {
    if (c.JS_IsNull(raw)) return invalidArg(scope, theme);
    const value = if (scope.truthy(raw)) raw else fallback;
    if (!scope.truthy(value)) return fg(scope, theme, "toolOutput", try scope.text("..."));
    const color = try scope.get(theme, "fg");
    const token = try scope.text("accent");
    const styled = try scope.call(color, theme, &.{ token, try shortenPath(scope, value) });
    return linkPath(scope, styled, value, cwd);
}
fn regexp(scope: *Scope, kind: State) !c.JSValue {
    const name = "pi-native:tool-render-regex";
    if (!scope.engine.native_module_values.contains(name)) {
        const exports = try scope.object();
        inline for (std.meta.fields(State)) |field| {
            const pattern = switch (@as(State, @enumFromInt(field.value))) {
                .ansi => "(?:\\u001B\\][\\s\\S]*?(?:\\u0007|\\u001B\\u005C|\\u009C))|[\\u001B\\u009B][[\\]()#;?]*(?:\\d{1,4}(?:[;:]\\d{0,4})*)?[\\dA-PR-TZcf-nq-uy=><~]",
                .binary => "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\uFFF9-\\uFFFB]",
                .carriage_return => "\\r",
                .tab => "\\t",
                .windows_path => "^/(?:mnt/|cygdrive/)?([a-z])(?:/(.*))?$",
            };
            var arguments = [_]c.JSValue{ try scope.text(pattern), try scope.text(if (@as(State, @enumFromInt(field.value)) == .windows_path) "i" else "g") };
            const compiled = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
            try scope.put(exports, field.name, compiled);
        }
        try scope.engine.registerValueModule(name, exports);
    }
    return scope.get(scope.engine.native_module_values.get(name).?, @tagName(kind));
}
fn replace(scope: *Scope, value: c.JSValue, kind: State, replacement: []const u8) !c.JSValue {
    const method = try scope.get(value, "replace");
    return scope.call(method, value, &.{ try regexp(scope, kind), try scope.text(replacement) });
}
pub fn replaceTabs(scope: *Scope, value: c.JSValue) !c.JSValue {
    return replace(scope, value, .tab, "   ");
}
pub fn normalizeDisplayText(scope: *Scope, value: c.JSValue) !c.JSValue {
    return replace(scope, value, .carriage_return, "");
}
fn stripAnsi(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(value)) {
        const type_name: [*:0]const u8 = if (c.JS_IsUndefined(value)) "undefined" else if (c.JS_IsBool(value)) "boolean" else if (c.JS_IsNumber(value)) "number" else if (c.JS_IsBigInt(value)) "bigint" else if (c.JS_IsSymbol(value)) "symbol" else if (c.JS_IsFunction(scope.engine.context, value)) "function" else "object";
        _ = try scope.engine.checked(c.JS_ThrowTypeError(scope.engine.context, "Expected a `string`, got `%s`", type_name));
        unreachable;
    }
    if (!scope.truthy(try scope.invoke(value, "includes", &.{try scope.text("\x1b")})) and !scope.truthy(try scope.invoke(value, "includes", &.{try scope.text("\xc2\x9b")}))) return value;
    return replace(scope, value, .ansi, "");
}
const Mapper = enum(c_int) { text_block, image_block, text_output, image_indicator, styled_line, key_combination, key_part };
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Mapper, value: c.JSValue, root: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = switch (kind) {
        .text_block, .image_block => c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "type"), try scope.text(if (kind == .text_block) "text" else "image")))),
        .text_output => text: {
            const raw = try scope.get(value, "text");
            const stripped = try stripAnsi(&scope, if (scope.truthy(raw)) raw else try scope.text(""));
            break :text try normalizeDisplayText(&scope, try replace(&scope, stripped, .binary, ""));
        },
        .image_indicator => image: {
            const mime = try scope.get(value, "mimeType");
            const mime_type = if (temporary.nullish(mime)) try scope.text("image/unknown") else mime;
            const data = try scope.get(value, "data");
            const dims = if (scope.truthy(data) and scope.truthy(try scope.get(value, "mimeType"))) dimensions: {
                const selected = try scope.call(try scope.get(try tui(&scope), "getImageDimensions"), c.pi_js_undefined(), &.{ try scope.get(value, "data"), try scope.get(value, "mimeType") });
                break :dimensions if (temporary.nullish(selected)) c.pi_js_undefined() else selected;
            } else c.pi_js_undefined();
            break :image try scope.call(try scope.get(try tui(&scope), "imageFallback"), c.pi_js_undefined(), &.{ mime_type, dims });
        },
        .styled_line => try fg(&scope, root, "toolOutput", value),
        .key_part => if (builtin.os.tag == .macos and scope.equal(try scope.invoke(value, "toLowerCase", &.{}), try scope.text("alt"))) try scope.text("option") else value,
        .key_combination => try scope.invoke(try map(&scope, try scope.invoke(value, "split", &.{try scope.text("+")}), "map", .key_part, c.pi_js_undefined()), "join", &.{try scope.text("+")}),
    };
    return c.JS_DupValue(engine.context, output);
}
pub fn map(scope: *Scope, array: c.JSValue, method_name: [*:0]const u8, kind: Mapper, root: c.JSValue) !c.JSValue {
    const method = try scope.get(array, method_name);
    var roots = [_]c.JSValue{root};
    const mapper = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), roots.len, &roots)));
    return scope.call(method, array, &.{mapper});
}
pub fn textOutput(scope: *Scope, result: c.JSValue, show_images: c.JSValue) !c.JSValue {
    if (!scope.truthy(result)) return scope.text("");
    const text_blocks = try map(scope, try scope.get(result, "content"), "filter", .text_block, c.pi_js_undefined());
    const image_blocks = try map(scope, try scope.get(result, "content"), "filter", .image_block, c.pi_js_undefined());
    var output = try scope.invoke(try map(scope, text_blocks, "map", .text_output, c.pi_js_undefined()), "join", &.{try scope.text("\n")});
    const caps = try scope.call(try scope.get(try tui(scope), "getCapabilities"), c.pi_js_undefined(), &.{});
    if (try scope.positive(try scope.get(image_blocks, "length")) and (!scope.truthy(try scope.get(caps, "images")) or !scope.truthy(show_images))) {
        const indicators = try scope.invoke(try map(scope, image_blocks, "map", .image_indicator, c.pi_js_undefined()), "join", &.{try scope.text("\n")});
        output = if (scope.truthy(output)) try scope.concat(try scope.concat(output, try scope.text("\n")), indicators) else indicators;
    }
    return output;
}
pub fn keyText(scope: *Scope, binding: []const u8) !c.JSValue {
    const manager = try scope.own(try @import("native_keybindings.zig").getGlobal(scope.engine));
    const keys = try scope.invoke(manager, "getKeys", &.{try scope.text(binding)});
    if (scope.equal(try scope.get(keys, "length"), c.JS_NewInt32(scope.engine.context, 0))) return scope.text("");
    const raw = try scope.invoke(keys, "join", &.{try scope.text("/")});
    const combinations = try scope.invoke(raw, "split", &.{try scope.text("/")});
    return scope.invoke(try map(scope, combinations, "map", .key_combination, c.pi_js_undefined()), "join", &.{try scope.text("/")});
}
pub fn keyHint(scope: *Scope, binding: []const u8, description: []const u8) !c.JSValue {
    const exports = scope.engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeModuleUnavailable;
    const theme = try scope.get(exports, "theme");
    const method = try scope.get(theme, "fg");
    const token = try scope.text("dim");
    const key = try keyText(scope, binding);
    const first = try scope.call(method, theme, &.{ token, key });
    return scope.concat(first, try fg(scope, theme, "muted", try scope.concat(try scope.text(" "), try scope.text(description))));
}
pub fn formatSize(scope: *Scope, bytes: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const below_kb = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, bytes, c.JS_NewInt32(engine.context, 1024))));
    if (scope.truthy(below_kb)) return surround(scope, "", bytes, "B");
    const below_mb = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, bytes, c.JS_NewInt32(engine.context, 1024 * 1024))));
    const divisor = c.JS_NewInt32(engine.context, if (scope.truthy(below_mb)) 1024 else 1024 * 1024);
    const size = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 3, bytes, divisor)));
    return scope.concat(try scope.invoke(size, "toFixed", &.{c.JS_NewInt32(engine.context, 1)}), try scope.text(if (scope.truthy(below_mb)) "KB" else "MB"));
}
fn arithmetic(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn floor(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("Math"), "floor", &.{value});
}
fn remainder(scope: *Scope, value: c.JSValue) !c.JSValue {
    // These operands are the original Math.floor results and literal number60.
    const numeric = try @import("native_select_list.zig").number(scope.engine, value);
    return c.JS_NewFloat64(scope.engine.context, @rem(numeric, 60));
}
pub fn formatDuration(scope: *Scope, milliseconds: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const seconds = try arithmetic(scope, 3, milliseconds, c.JS_NewInt32(engine.context, 1000));
    if (scope.truthy(try arithmetic(scope, 4, seconds, c.JS_NewInt32(engine.context, 60)))) {
        return surround(scope, "", try scope.invoke(seconds, "toFixed", &.{c.JS_NewInt32(engine.context, 1)}), "s");
    }
    const total_seconds = try floor(scope, seconds);
    const minutes = try floor(scope, try arithmetic(scope, 3, total_seconds, c.JS_NewInt32(engine.context, 60)));
    const rest = try remainder(scope, total_seconds);
    if (scope.truthy(try arithmetic(scope, 4, minutes, c.JS_NewInt32(engine.context, 60)))) {
        return scope.concat(try surround(scope, "", minutes, "m "), try surround(scope, "", rest, "s"));
    }
    const hours = try floor(scope, try arithmetic(scope, 3, minutes, c.JS_NewInt32(engine.context, 60)));
    const head = try surround(scope, "", hours, "h ");
    return scope.concat(try scope.concat(head, try surround(scope, "", try remainder(scope, minutes), "m ")), try surround(scope, "", rest, "s"));
}
fn dateNow(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Date"), "now", &.{});
}
pub fn startTimer(scope: *Scope, context: c.JSValue) !void {
    const state = try scope.get(context, "state");
    if (scope.truthy(try scope.get(context, "executionStarted")) and c.JS_IsUndefined(try scope.get(state, "startedAt"))) {
        try scope.set(state, "startedAt", try dateNow(scope));
        try scope.set(state, "endedAt", c.pi_js_undefined());
    }
}
fn invalidateTimer(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.invoke(engine, roots[0], "invalidate", &.{}) catch |err| sdk.fail(engine, err);
}
pub fn timerText(scope: *Scope, context: c.JSValue, partial: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const state = try scope.get(context, "state");
    if (!c.JS_IsUndefined(try scope.get(state, "startedAt")) and scope.truthy(partial) and !scope.truthy(try scope.get(state, "interval"))) {
        const set_interval = try scope.global("setInterval");
        var roots = [_]c.JSValue{context};
        const callback_value = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, invalidateTimer, "", 0, 0, roots.len, &roots)));
        try scope.set(state, "interval", try scope.call(set_interval, c.pi_js_undefined(), &.{ callback_value, c.JS_NewInt32(engine.context, 1000) }));
    }
    if (!scope.truthy(partial) or scope.truthy(try scope.get(context, "isError"))) {
        if (temporary.nullish(try scope.get(state, "endedAt"))) try scope.set(state, "endedAt", try dateNow(scope));
        if (scope.truthy(try scope.get(state, "interval"))) {
            const clear_interval = try scope.global("clearInterval");
            _ = try scope.call(clear_interval, c.pi_js_undefined(), &.{try scope.get(state, "interval")});
            try scope.set(state, "interval", c.pi_js_undefined());
        }
    }
    if (!scope.truthy(partial) and !c.JS_IsUndefined(try scope.get(context, "durationMs"))) {
        return surround(scope, "Took ", try formatDuration(scope, try scope.get(context, "durationMs")), "");
    }
    if (c.JS_IsUndefined(try scope.get(state, "startedAt"))) return c.pi_js_undefined();
    const ended = try scope.get(state, "endedAt");
    const end_time = if (temporary.nullish(ended)) try dateNow(scope) else ended;
    const elapsed = try arithmetic(scope, 1, end_time, try scope.get(state, "startedAt"));
    return surround(scope, if (scope.truthy(partial)) "Elapsed " else "Took ", try formatDuration(scope, elapsed), "");
}
