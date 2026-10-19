// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Genuine internal/url isURL, toPathIfFileURL and fileURLToPath bodies.
//! Visible structural getters and Source expression/lexical lifetimes are kept;
//! native URL construction, private RegExp and domain parsing stay actual owners.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const regexes = @import("native_node_internal_regex.zig");
const publication = @import("native_node_fs_private_publication.zig");
const parser = @import("url_parser.zig");
const key = "pi-native:private/file-url-path-owner";
const FileFrame = a.frames.Frame(enum { path, options, windows });
const PathFrame = a.frames.Frame(enum { hostname, pathname, position, third, letter, separator });

fn sameField(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, expected: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(receiver, name), expected));
}
fn sameFieldText(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(receiver, name), try s.text(expected)));
}
fn isURLValue(engine: *a.v.em.Engine, value: c.JSValue) !bool {
    try engine.checkNativeEntry();
    if (a.v.nullish(value)) return false;
    if (!try a.condition(engine, a.fieldTruthy, .{value, @as([*:0]const u8, "href")})) return false;
    if (!try a.condition(engine, a.fieldTruthy, .{value, @as([*:0]const u8, "protocol")})) return false;
    if (!try a.condition(engine, sameField, .{value, @as([*:0]const u8, "auth"), c.pi_js_undefined()})) return false;
    return a.condition(engine, sameField, .{value, @as([*:0]const u8, "path"), c.pi_js_undefined()});
}
fn isURL(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try isURLValue(engine, a.arg(args, 0))));
}
fn optionalWindows(s: *Scope, options: c.JSValue) !c.JSValue {
    return if (a.v.nullish(options)) c.pi_js_undefined() else a.duplicate(s.engine, try s.get(options, "windows"));
}
fn constructURL(s: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.construct(try s.get(owner, "URL"), &.{path}));
}
fn invalidTypeReason(s: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    const errors = try s.get(owner, "errors");
    const constructor = try s.get(errors, "invalid_arg_type");
    const expected = try a.array(s);
    try a.index(s, expected, 0, try s.text("string"));
    try a.index(s, expected, 1, try s.text("URL"));
    return a.duplicate(s.engine, try s.construct(constructor, &.{try s.text("path"), expected, path}));
}
fn schemeReason(s: *Scope, owner: c.JSValue) !c.JSValue {
    const constructor = try s.get(try s.get(owner, "errors"), "invalid_url_scheme");
    return a.duplicate(s.engine, try s.construct(constructor, &.{try s.text("file")}));
}
fn pathReason(s: *Scope, owner: c.JSValue, reason: []const u8, url: c.JSValue) !c.JSValue {
    const constructor = try s.get(try s.get(owner, "errors"), "invalid_file_url_path");
    return a.duplicate(s.engine, try s.construct(constructor, &.{try s.text(reason), url}));
}
fn hostReason(s: *Scope, owner: c.JSValue) !c.JSValue {
    const constructor = try s.get(try s.get(owner, "errors"), "invalid_file_url_host");
    return a.duplicate(s.engine, try s.construct(constructor, &.{try s.get(owner, "platform")}));
}
fn fileURLToPath(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return fileValue(engine, roots[0], a.arg(args, 0), a.arg(args, 1));
}
pub fn fileValue(engine: *a.v.em.Engine, owner: c.JSValue, path: c.JSValue, options: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = FileFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, fileBody(&s, frame, owner, path, options));
}
fn fileBody(s: *Scope, frame: *FileFrame, owner: c.JSValue, path: c.JSValue, options: c.JSValue) !c.JSValue {
    try frame.copy(.path, path);
    try frame.copy(.options, if (c.JS_IsUndefined(options)) try s.get(owner, "empty") else options);
    try frame.take(.windows, a.expression(s.engine, optionalWindows, .{frame.get(.options)}));
    if (c.JS_IsString(frame.get(.path))) {
        try frame.take(.path, a.expression(s.engine, constructURL, .{owner, frame.get(.path)}));
    } else if (!try isURLValue(s.engine, frame.get(.path))) {
        return a.raise(s, try s.own(try a.expression(s.engine, invalidTypeReason, .{owner, frame.get(.path)})));
    }
    if (!try a.condition(s.engine, sameFieldText, .{frame.get(.path), @as([*:0]const u8, "protocol"), @as([]const u8, "file:")}))
        return a.raise(s, try s.own(try a.expression(s.engine, schemeReason, .{owner})));
    const windows = if (a.v.nullish(frame.get(.windows)))
        s.truthy(try s.get(owner, "is_windows"))
    else s.truthy(frame.get(.windows));
    return pathFromURL(s.engine, owner, frame.get(.path), windows);
}
fn toPathIfFileURL(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return toPathValue(engine, roots[0], a.arg(args, 0));
}
pub fn toPathValue(engine: *a.v.em.Engine, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!try isURLValue(engine, value)) return a.duplicate(engine, value);
    return fileValue(engine, owner, value, c.pi_js_undefined());
}
fn lessLength(s: *Scope, position: c.JSValue, path: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(4, position, try s.get(path, "length"))));
}
fn indexEqual(s: *Scope, path: c.JSValue, position: c.JSValue, offset: i32, expected: []const u8) !c.JSValue {
    const at = if (offset == 0) position else try s.binary(0, position, c.JS_NewInt32(s.engine.context, offset));
    return a.boolean(s, s.equal(try s.getKey(path, at), try s.text(expected)));
}
fn codePoint(s: *Scope, owner: c.JSValue, path: c.JSValue, position: c.JSValue, offset: i32) !c.JSValue {
    const function = try s.get(owner, "code_point_at");
    const at = if (offset == 0) position else try s.binary(0, position, c.JS_NewInt32(s.engine.context, offset));
    const point = try s.call(function, path, &.{at});
    return a.duplicate(s.engine, try s.binary(11, point, c.JS_NewInt32(s.engine.context, 0x20)));
}
fn increment(s: *Scope, value: c.JSValue) !c.JSValue {
    try s.pending();
    return a.duplicate(s.engine, try s.checked(c.JS_PiIncrement(s.engine.context, value)));
}
fn encodedSeparator(engine: *a.v.em.Engine, path: c.JSValue, position: c.JSValue, third: c.JSValue, windows: bool) !bool {
    if (try a.condition(engine, indexEqual, .{path, position, @as(i32, 1), @as([]const u8, "2")}) and
        c.JS_IsStrictEqual(engine.context, third, c.JS_NewInt32(engine.context, 102))) return true;
    return windows and try a.condition(engine, indexEqual, .{path, position, @as(i32, 1), @as([]const u8, "5")}) and
        c.JS_IsStrictEqual(engine.context, third, c.JS_NewInt32(engine.context, 99));
}
fn scan(s: *Scope, frame: *PathFrame, owner: c.JSValue, url: c.JSValue, windows: bool) !void {
    try frame.copy(.position, c.JS_NewInt32(s.engine.context, 0));
    var steps: usize = 0;
    while (try a.condition(s.engine, lessLength, .{frame.get(.position), frame.get(.pathname)})) {
        try @import("native_node_commonjs_interrupt.zig").step(s.engine, &steps);
        if (try a.condition(s.engine, indexEqual, .{frame.get(.pathname), frame.get(.position), @as(i32, 0), @as([]const u8, "%")})) {
            // The inner if's const survives other iterations; its next actual
            // scope entry clears it before the next initializer.
            try frame.clear(.third);
            try frame.take(.third, a.expression(s.engine, codePoint, .{owner, frame.get(.pathname), frame.get(.position), @as(i32, 2)}));
            if (try encodedSeparator(s.engine, frame.get(.pathname), frame.get(.position), frame.get(.third), windows)) {
                const message = if (windows) "must not include encoded \\ or / characters" else "must not include encoded / characters";
                return a.raise(s, try s.own(try a.expression(s.engine, pathReason, .{owner, @as([]const u8, message), url})));
            }
        }
        try frame.take(.position, a.expression(s.engine, increment, .{frame.get(.position)}));
    }
}
fn slashReplacement(s: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    const regex_owner = try s.get(owner, "regex_owner");
    const regex = try s.get(owner, "forward_slash");
    return regexes.replace(s.engine, regex_owner, regex, path, try s.text("\\"));
}
fn decode(s: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(owner, "decode"), c.pi_js_undefined(), &.{value}));
}
fn domainUnicode(s: *Scope, value: c.JSValue) !c.JSValue {
    // internal/url.domainToUnicode always receives one argument here. Its
    // template uses intrinsic ToString before the native binding sees bytes.
    const text = try s.toString(value);
    var length: usize = 0;
    const generation = try s.beforeAllocation();
    const bytes = c.JS_ToCStringLen(s.engine.context, &length, text);
    defer if (bytes != null) c.JS_FreeCString(s.engine.context, bytes);
    try s.boundary.checkPendingSince(generation);
    if (bytes == null) return error.MissingActualDomainStringReason;
    if (length == 0) return a.duplicate(s.engine, try s.text(""));
    const decoded = parser.domainUnicode(s.engine.gpa, bytes[0..length]) catch |err| switch (err) {
        error.InvalidURLHost => return a.duplicate(s.engine, try s.text("")),
        else => return err,
    };
    defer s.engine.gpa.free(decoded);
    return a.duplicate(s.engine, try s.text(decoded));
}
fn uncResult(s: *Scope, hostname: c.JSValue, pathname: c.JSValue) !c.JSValue {
    const host = try s.own(try a.expression(s.engine, domainUnicode, .{hostname}));
    const prefix = try a.add(s, try s.text("\\\\"), try s.toString(host));
    return a.duplicate(s.engine, try a.add(s, prefix, try s.toString(pathname)));
}
fn charAt(s: *Scope, owner: c.JSValue, path: c.JSValue, position: i32) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(owner, "char_at"), path, &.{c.JS_NewInt32(s.engine.context, position)}));
}
fn letterOutside(s: *Scope, letter: c.JSValue, upper: bool) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(if (upper) 6 else 4, letter, c.JS_NewInt32(s.engine.context, if (upper) 122 else 97))));
}
fn slicePath(s: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(owner, "slice"), path, &.{c.JS_NewInt32(s.engine.context, 1)}));
}
fn pathBody(s: *Scope, frame: *PathFrame, owner: c.JSValue, url: c.JSValue, windows: bool) !c.JSValue {
    if (windows) {
        try frame.take(.hostname, a.field(s.engine, url, "hostname"));
    } else if (!try a.condition(s.engine, sameFieldText, .{url, @as([*:0]const u8, "hostname"), @as([]const u8, "")})) {
        return a.raise(s, try s.own(try a.expression(s.engine, hostReason, .{owner})));
    }
    try frame.take(.pathname, a.field(s.engine, url, "pathname"));
    try scan(s, frame, owner, url, windows);
    if (!windows) return a.expression(s.engine, decode, .{owner, frame.get(.pathname)});
    try frame.take(.pathname, a.expression(s.engine, slashReplacement, .{owner, frame.get(.pathname)}));
    try frame.take(.pathname, a.expression(s.engine, decode, .{owner, frame.get(.pathname)}));
    const empty = try s.text("");
    if (!s.equal(frame.get(.hostname), empty))
        return a.expression(s.engine, uncResult, .{frame.get(.hostname), frame.get(.pathname)});
    try frame.take(.letter, a.expression(s.engine, codePoint, .{owner, frame.get(.pathname), c.JS_NewInt32(s.engine.context, 1), @as(i32, 0)}));
    try frame.take(.separator, a.expression(s.engine, charAt, .{owner, frame.get(.pathname), @as(i32, 2)}));
    if (try a.condition(s.engine, letterOutside, .{frame.get(.letter), false}) or
        try a.condition(s.engine, letterOutside, .{frame.get(.letter), true}) or !s.equal(frame.get(.separator), try s.text(":")))
        return a.raise(s, try s.own(try a.expression(s.engine, pathReason, .{owner, @as([]const u8, "must be absolute"), url})));
    return a.expression(s.engine, slicePath, .{owner, frame.get(.pathname)});
}
fn pathFromURL(engine: *a.v.em.Engine, owner: c.JSValue, url: c.JSValue, windows: bool) !c.JSValue {
    var s = Scope.init(engine);
    const frame = PathFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, pathBody(&s, frame, owner, url, windows));
}
fn createBody(s: *Scope) !c.JSValue {
    if (s.engine.native_url_constructor == null) try @import("native_url.zig").install(s.engine);
    const errors = try s.own(try @import("native_node_file_url_errors.zig").acquire(s.engine));
    const empty = try s.own(try @import("native_node_internal_empty_object.zig").acquire(s.engine));
    const regex_owner = try s.own(try regexes.acquire(s.engine));
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const strings = try s.get(try s.get(global, "String"), "prototype");
    const core = try s.own(a.duplicate(s.engine, try @import("native_node_stream.zig").owner(s.engine)));
    const platform = try s.get(try s.get(core, "process"), "platform");
    const record = try s.objectProto(c.pi_js_null());
    try s.put(record, "URL", s.engine.native_url_constructor.?);
    try s.put(record, "decode", s.engine.url_decode_uri_component orelse return error.ActualURLDecoderRequired);
    try s.put(record, "errors", errors);
    try s.put(record, "empty", empty);
    try s.put(record, "regex_owner", regex_owner);
    try s.put(record, "platform", platform);
    try s.put(record, "is_windows", a.boolean(s, s.equal(platform, try s.text("win32"))));
    try s.put(record, "code_point_at", try s.get(strings, "codePointAt"));
    try s.put(record, "char_at", try s.get(strings, "charAt"));
    try s.put(record, "slice", try s.get(strings, "slice"));
    // The original private /\//g literal. This original intrinsic constructor
    // is used only during the genuine bootstrap, before guest code can mutate it.
    try s.put(record, "forward_slash", try s.construct(try s.get(global, "RegExp"), &.{try s.text("/"), try s.text("g")}));
    try s.put(record, "isURL", try s.own(try functions.create(s.engine, "isURL", 1, true, isURL, &.{record})));
    try s.put(record, "fileURLToPath", try s.own(try functions.create(s.engine, "fileURLToPath", 1, true, fileURLToPath, &.{record})));
    try s.put(record, "toPathIfFileURL", try s.own(try functions.create(s.engine, "toPathIfFileURL", 1, true, toPathIfFileURL, &.{record})));
    return a.duplicate(s.engine, record);
}
/// The real process/Stream/internal-errors bootstrap must precede this call.
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
