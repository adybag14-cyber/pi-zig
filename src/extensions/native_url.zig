//! Branded native URL objects and atomic URL/URLSearchParams association.
const std = @import("std");
const engine_mod = @import("engine.zig");
const parser = @import("url_parser.zig");
const params = @import("url_search_params.zig");
const file_urls = @import("file_urls.zig");
const c = engine_mod.c;
pub const State = struct { engine: *engine_mod.Engine, record: parser.Record, search_params: ?c.JSValue = null };
const Attribute = enum(c_int) { href, origin, protocol, username, password, host, hostname, port, pathname, search, hash, searchParams };
pub fn isURL(engine: *engine_mod.Engine, value: c.JSValue) bool {
    return engine.url_class != 0 and c.JS_GetOpaque(value, engine.url_class) != null;
}
pub fn stateFor(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.url_class) orelse return error.IllegalURLReceiver));
    if (state.engine != engine) return error.IllegalURLReceiver;
    return state;
}
pub fn href(engine: *engine_mod.Engine, value: c.JSValue) ![]u8 {
    return parser.serialize(engine.gpa, (try stateFor(engine, value)).record);
}
pub fn visibleURL(engine: *engine_mod.Engine, value: c.JSValue) !bool {
    _ = try stateFor(engine, value);
    // Node's consumers observe these property reads. Keep the strong native
    // brand boundary while retaining real URL getter exceptions and reentry.
    const visible_href = try property(engine, value, "href");
    defer engine.freeValue(visible_href);
    if (c.JS_ToBool(engine.context, visible_href) == 0) return false;
    const first_protocol = try property(engine, value, "protocol");
    defer engine.freeValue(first_protocol);
    if (c.JS_ToBool(engine.context, first_protocol) == 0) return false;
    const auth = try property(engine, value, "auth");
    defer engine.freeValue(auth);
    if (!c.JS_IsUndefined(auth)) return false;
    const path_alias = try property(engine, value, "path");
    defer engine.freeValue(path_alias);
    return c.JS_IsUndefined(path_alias);
}
/// createRequire clones its validated input before converting the file URL.
pub fn clonedFilePath(engine: *engine_mod.Engine, value: c.JSValue, windows: bool) ![]u8 {
    const text = try params.usvString(engine, value);
    defer engine.gpa.free(text);
    var record = try parser.parse(engine.gpa, text, null);
    var transferred = false;
    defer if (!transferred) record.deinit(engine.gpa);
    const object = try create(engine, &record, null);
    transferred = true;
    defer engine.freeValue(object);
    return filePath(engine, object, windows);
}
pub fn filePath(engine: *engine_mod.Engine, value: c.JSValue, windows: bool) ![]u8 {
    if (!try visibleURL(engine, value)) return error.InvalidFileUrlArgument;
    const protocol = try property(engine, value, "protocol");
    defer engine.freeValue(protocol);
    if (!c.JS_IsString(protocol)) return error.InvalidFileUrlScheme;
    const scheme = try engine.toString(protocol);
    defer engine.gpa.free(scheme);
    if (!std.mem.eql(u8, scheme, "file:")) return error.InvalidFileUrlScheme;
    const host_value = try property(engine, value, "hostname");
    defer engine.freeValue(host_value);
    if (!c.JS_IsString(host_value)) return error.InvalidFileUrlHost;
    const host = try engine.toString(host_value);
    defer engine.gpa.free(host);
    const path_value = try property(engine, value, "pathname");
    defer engine.freeValue(path_value);
    if (!c.JS_IsString(path_value)) return error.InvalidFileUrlArgument;
    const path = try engine.toString(path_value);
    defer engine.gpa.free(path);
    const unicode_host = if (windows and host.len != 0) parser.domainUnicode(engine.gpa, host) catch |err| {
        if (err == error.OutOfMemory) return err;
        return error.InvalidFileUrlHost;
    } else null;
    defer if (unicode_host) |owned| engine.gpa.free(owned);
    return file_urls.toPathParts(engine.gpa, unicode_host orelse host, path, windows) catch |err| {
        if (err == error.InvalidFileUrlEncoding) if (engine.url_decode_uri_component) |decoder| {
            var argument = [_]c.JSValue{path_value};
            const checked = try engine.checked(c.JS_Call(engine.context, decoder, c.pi_js_undefined(), 1, &argument));
            engine.freeValue(checked);
        };
        return err;
    };
}
pub fn isFilePathError(err: anyerror) bool {
    return switch (err) {
        error.InvalidFileUrlArgument, error.InvalidFileUrlScheme, error.InvalidFileUrlHost, error.InvalidFileUrlDrive, error.InvalidFileUrlPath, error.InvalidFileUrlSeparator, error.InvalidFileUrlEncoding, error.InvalidFileUrl => true,
        else => false,
    };
}
/// Owned exception value for promise rejection; native OOM remains exceptional.
pub fn filePathErrorValue(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) {
        _ = engine.throwCaptured();
        return c.JS_GetException(engine.context);
    }
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    if (err == error.InvalidFileUrlEncoding) if (engine.url_decode_uri_component) |decoder| {
        var args = [_]c.JSValue{c.JS_NewString(engine.context, "%")};
        if (c.JS_IsException(args[0])) return args[0];
        defer engine.freeValue(args[0]);
        const result = c.JS_Call(engine.context, decoder, c.pi_js_undefined(), 1, &args);
        if (c.JS_IsException(result)) return c.JS_GetException(engine.context);
        engine.freeValue(result);
    };
    _ = c.JS_ThrowTypeError(engine.context, "Native file URL: %s", @as([*:0]const u8, @errorName(err)));
    const exception = c.JS_GetException(engine.context);
    if (!c.JS_IsError(exception)) return c.JS_Throw(engine.context, exception);
    const code: [*:0]const u8 = switch (err) {
        error.InvalidFileUrlArgument => "ERR_INVALID_ARG_TYPE",
        error.InvalidFileUrlScheme => "ERR_INVALID_URL_SCHEME",
        error.InvalidFileUrlHost => "ERR_INVALID_FILE_URL_HOST",
        else => "ERR_INVALID_FILE_URL_PATH",
    };
    if (c.JS_DefinePropertyValueStr(engine.context, exception, "code", c.JS_NewString(engine.context, code), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(exception);
        return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    return exception;
}
fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    _ = c.JS_ThrowTypeError(engine.context, "Native URL: %s", @as([*:0]const u8, @errorName(err)));
    const exception = c.JS_GetException(engine.context);
    if (!c.JS_IsError(exception)) return c.JS_Throw(engine.context, exception);
    const code: [*:0]const u8 = if (err == error.MissingURLInput) "ERR_MISSING_ARGS" else if (err == error.UnsupportedIDNContext) "ERR_URL_UNSUPPORTED_IDN_CONTEXT" else if (err == error.IllegalURLReceiver) "ERR_INVALID_THIS" else "ERR_INVALID_URL";
    if (c.JS_DefinePropertyValueStr(engine.context, exception, "code", c.JS_NewString(engine.context, code), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(exception);
        return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    return c.JS_Throw(engine.context, exception);
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (state.search_params) |query| c.JS_FreeValueRT(runtime, query);
    state.record.deinit(state.engine.gpa);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, mark_value: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (state.search_params) |query| c.JS_MarkValue(runtime, query, mark_value);
}
fn property(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
/// Consumes record only after successful allocation and attachment.
pub fn create(engine: *engine_mod.Engine, record: *parser.Record, prototype: ?c.JSValue) !c.JSValue {
    const object = try engine.checked(if (prototype) |value| c.JS_NewObjectProtoClass(engine.context, value, engine.url_class) else c.JS_NewObjectClass(engine.context, engine.url_class));
    errdefer engine.freeValue(object);
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .record = record.* };
    record.* = undefined;
    _ = c.JS_SetOpaque(object, state);
    return object;
}
fn parseValues(engine: *engine_mod.Engine, argc: c_int, argv: [*c]c.JSValue) !parser.Record {
    if (argc == 0) return error.MissingURLInput;
    const input = try params.usvString(engine, argv[0]);
    defer engine.gpa.free(input);
    var base: ?parser.Record = null;
    defer if (base) |*value| value.deinit(engine.gpa);
    if (argc > 1 and !c.JS_IsUndefined(argv[1])) {
        const text = try params.usvString(engine, argv[1]);
        defer engine.gpa.free(text);
        base = try parser.parse(engine.gpa, text, null);
    }
    return parser.parse(engine.gpa, input, if (base) |*value| value else null);
}
fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return constructValue(engine, target, argc, argv) catch |err| fail(engine, err);
}
fn constructValue(engine: *engine_mod.Engine, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    const prototype = try property(engine, target, "prototype");
    defer engine.freeValue(prototype);
    var record = try parseValues(engine, argc, argv);
    var transferred = false;
    defer if (!transferred) record.deinit(engine.gpa);
    const object = try create(engine, &record, if (c.JS_IsObject(prototype)) prototype else null);
    transferred = true;
    return object;
}
fn opaqueTail(gpa: std.mem.Allocator, record: *parser.Record) !void {
    if (!record.opaque_path or record.query != null or record.fragment != null or !std.mem.endsWith(u8, record.path, " ")) return;
    const end = std.mem.trimEnd(u8, record.path, " ").len;
    var value: std.ArrayList(u8) = .empty;
    defer value.deinit(gpa);
    try value.appendSlice(gpa, record.path[0..end]);
    for (end..record.path.len) |_| try value.appendSlice(gpa, "%20");
    parser.replace(gpa, &record.path, try value.toOwnedSlice(gpa));
}
fn associatedUpdate(context: *anyopaque, pairs: []const params.Pair) !void {
    const state: *State = @ptrCast(@alignCast(context));
    const gpa = state.engine.gpa;
    var record = try state.record.clone(gpa);
    defer record.deinit(gpa);
    const serialized = try params.serialize(gpa, pairs);
    if (record.query) |value| gpa.free(value);
    if (serialized.len == 0) {
        gpa.free(serialized);
        record.query = null;
    } else record.query = serialized;
    try opaqueTail(gpa, &record);
    std.mem.swap(parser.Record, &state.record, &record);
}
fn searchParams(engine: *engine_mod.Engine, this: c.JSValue, state: *State) !c.JSValue {
    if (state.search_params) |value| return c.JS_DupValue(engine.context, value);
    var pairs = try params.parse(engine.gpa, state.record.query orelse "");
    defer params.freePairs(engine.gpa, &pairs);
    const object = try params.create(engine, &pairs);
    errdefer engine.freeValue(object);
    try params.associate(engine, object, .{ .owner = this, .context = state, .update = associatedUpdate });
    state.search_params = c.JS_DupValue(engine.context, object);
    return object;
}
fn getter(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return getterValue(engine, this, @enumFromInt(magic)) catch |err| fail(engine, err);
}
fn getterValue(engine: *engine_mod.Engine, this: c.JSValue, attribute: Attribute) !c.JSValue {
    const state = try stateFor(engine, this);
    if (attribute == .searchParams) return searchParams(engine, this, state);
    const record = state.record;
    const owned: ?[]u8 = switch (attribute) {
        .href => try parser.serialize(engine.gpa, record),
        .origin => try parser.origin(engine.gpa, record),
        .protocol => try std.fmt.allocPrint(engine.gpa, "{s}:", .{record.scheme}),
        .host => if (record.host) |host| if (record.port) |port| try std.fmt.allocPrint(engine.gpa, "{s}:{d}", .{ host, port }) else null else null,
        .port => if (record.port) |port| try std.fmt.allocPrint(engine.gpa, "{d}", .{port}) else null,
        .search => if (record.query) |query| if (query.len == 0) null else try std.fmt.allocPrint(engine.gpa, "?{s}", .{query}) else null,
        .hash => if (record.fragment) |fragment| if (fragment.len == 0) null else try std.fmt.allocPrint(engine.gpa, "#{s}", .{fragment}) else null,
        else => null,
    };
    defer if (owned) |text| engine.gpa.free(text);
    const text = owned orelse switch (attribute) {
        .username => record.username,
        .password => record.password,
        .hostname, .host => record.host orelse "",
        .pathname => record.path,
        else => "",
    };
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}
fn stringify(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return getterValue(engine, this, .href) catch |err| fail(engine, err);
}
fn setter(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    setValue(engine, this, @enumFromInt(magic), if (argc == 0) c.pi_js_undefined() else argv[0]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn setterFailure(err: anyerror) !bool {
    if (err == error.OutOfMemory or err == error.UnsupportedIDNContext) return err;
    return false;
}
fn change(gpa: std.mem.Allocator, record: *parser.Record, attribute: Attribute, input: []const u8) !bool {
    const file = std.mem.eql(u8, record.scheme, "file");
    switch (attribute) {
        .protocol => {
            const end = std.mem.indexOfScalar(u8, input, ':') orelse input.len;
            if (end == 0 or !std.ascii.isAlphabetic(input[0])) return false;
            for (input[1..end]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '-' and byte != '.') return false;
            const scheme = try std.ascii.allocLowerString(gpa, input[0..end]);
            defer gpa.free(scheme);
            if (parser.special(record.scheme) != parser.special(scheme)) return false;
            if (std.mem.eql(u8, scheme, "file") and (record.username.len != 0 or record.password.len != 0 or record.port != null)) return false;
            if (file and record.host != null and record.host.?.len == 0) return false;
            parser.replace(gpa, &record.scheme, try gpa.dupe(u8, scheme));
            if (record.port == parser.defaultPort(record.scheme)) record.port = null;
        },
        .username, .password => {
            if (file or record.host == null or record.host.?.len == 0) return false;
            const value = try parser.encode(gpa, input, .userinfo);
            parser.replace(gpa, if (attribute == .username) &record.username else &record.password, value);
        },
        .host, .hostname => {
            if (record.opaque_path) return false;
            const end = std.mem.indexOfAny(u8, input, if (parser.special(record.scheme)) "/\\?#" else "/?#") orelse input.len;
            const text = input[0..end];
            if (std.mem.indexOfScalar(u8, text, '@') != null) return false;
            if (attribute == .hostname) {
                if (!std.mem.startsWith(u8, text, "[") and std.mem.indexOfScalar(u8, text, ':') != null) return false;
                const host = parser.parseHost(gpa, text, parser.special(record.scheme)) catch |err| return setterFailure(err);
                if (host.len == 0 and ((!file and parser.special(record.scheme)) or record.port != null or record.username.len != 0 or record.password.len != 0 or record.host == null)) {
                    gpa.free(host);
                    return false;
                }
                if (record.host) |old| gpa.free(old);
                record.host = host;
                if (file and std.ascii.eqlIgnoreCase(host, "localhost")) {
                    const empty = try gpa.dupe(u8, "");
                    gpa.free(host);
                    record.host = empty;
                }
            } else {
                var host_text = text;
                var port_text: ?[]const u8 = null;
                if (std.mem.startsWith(u8, text, "[")) {
                    const closing = std.mem.indexOfScalar(u8, text, ']') orelse return false;
                    host_text = text[0 .. closing + 1];
                    if (closing + 1 < text.len) {
                        if (text[closing + 1] != ':') return false;
                        port_text = text[closing + 2 ..];
                    }
                } else if (std.mem.lastIndexOfScalar(u8, text, ':')) |colon| {
                    host_text = text[0..colon];
                    port_text = text[colon + 1 ..];
                }
                if (file and port_text != null) return false;
                if (host_text.len == 0 and ((!file and parser.special(record.scheme)) or record.port != null or record.username.len != 0 or record.password.len != 0 or record.host == null)) return false;
                var host = parser.parseHost(gpa, host_text, parser.special(record.scheme)) catch |err| return setterFailure(err);
                errdefer gpa.free(host);
                if (file and std.ascii.eqlIgnoreCase(host, "localhost")) {
                    const empty_host = try gpa.dupe(u8, "");
                    gpa.free(host);
                    host = empty_host;
                }
                if (record.host) |old| gpa.free(old);
                record.host = host;
                // Host parsing commits before the port override. An invalid
                // or overflowing override retains the previous port.
                if (port_text) |text_port| {
                    var count: usize = 0;
                    while (count < text_port.len and std.ascii.isDigit(text_port[count])) : (count += 1) {}
                    if (count != 0) {
                        const port = std.fmt.parseInt(u16, text_port[0..count], 10) catch return true;
                        record.port = if (parser.defaultPort(record.scheme) == port) null else port;
                    }
                }
            }
        },
        .port => {
            if (file or record.host == null or record.host.?.len == 0) return false;
            if (input.len == 0) {
                record.port = null;
                return true;
            }
            var count: usize = 0;
            while (count < input.len and std.ascii.isDigit(input[count])) : (count += 1) {}
            if (count == 0) return false;
            const port = std.fmt.parseInt(u16, input[0..count], 10) catch return false;
            record.port = if (parser.defaultPort(record.scheme) == port) null else port;
        },
        .pathname => {
            if (record.opaque_path) return false;
            const text = try gpa.dupe(u8, input);
            defer gpa.free(text);
            if (parser.special(record.scheme)) for (text) |*byte| if (byte.* == '\\') {
                byte.* = '/';
            };
            parser.replace(gpa, &record.path, if (!parser.special(record.scheme) and record.host != null and text.len == 0) try gpa.dupe(u8, "") else try parser.normalizePath(gpa, text, file));
        },
        .search => {
            const value: ?[]u8 = if (input.len == 0) null else try parser.encode(gpa, if (input[0] == '?') input[1..] else input, if (parser.special(record.scheme)) .special_query else .query);
            if (record.query) |old| gpa.free(old);
            record.query = value;
            try opaqueTail(gpa, record);
        },
        .hash => {
            const value: ?[]u8 = if (input.len == 0) null else try parser.encode(gpa, if (input[0] == '#') input[1..] else input, .fragment);
            if (record.fragment) |old| gpa.free(old);
            record.fragment = value;
            try opaqueTail(gpa, record);
        },
        else => return false,
    }
    return true;
}
fn setValue(engine: *engine_mod.Engine, this: c.JSValue, attribute: Attribute, value: c.JSValue) !void {
    const state = try stateFor(engine, this);
    // User coercion may reenter and mutate this URL. Snapshot only afterward.
    const converted = try params.usvString(engine, value);
    defer engine.gpa.free(converted);
    var sanitized: std.ArrayList(u8) = .empty;
    defer sanitized.deinit(engine.gpa);
    const needs_sanitize = attribute != .username and attribute != .password and attribute != .href and std.mem.indexOfAny(u8, converted, "\t\r\n") != null;
    if (needs_sanitize) {
        for (converted) |byte| if (byte != '\t' and byte != '\r' and byte != '\n') try sanitized.append(engine.gpa, byte);
        // A nonempty search/hash assignment creates an empty suffix even when
        // every input character was removed by parser preprocessing.
        if (sanitized.items.len == 0 and (attribute == .search or attribute == .hash)) try sanitized.append(engine.gpa, if (attribute == .search) '?' else '#');
    }
    const input = if (needs_sanitize) sanitized.items else converted;
    var next = if (attribute == .href) try parser.parse(engine.gpa, input, null) else try state.record.clone(engine.gpa);
    defer next.deinit(engine.gpa);
    if (attribute != .href and !try change(engine.gpa, &next, attribute, input)) return;
    var next_pairs: std.ArrayList(params.Pair) = .empty;
    defer params.freePairs(engine.gpa, &next_pairs);
    const replace_params = state.search_params != null and (attribute == .href or attribute == .search);
    if (replace_params) next_pairs = try params.parse(engine.gpa, next.query orelse "");
    std.mem.swap(parser.Record, &state.record, &next);
    if (replace_params) params.replacePairs(try params.stateFor(engine, state.search_params.?), &next_pairs);
}
fn staticParse(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var record = parseValues(engine, argc, argv) catch |err| {
        if (err == error.JavaScriptException or err == error.OutOfMemory or err == error.MissingURLInput) return fail(engine, err);
        return if (magic == 0) c.pi_js_bool(context, 0) else c.pi_js_null();
    };
    var transferred = false;
    defer if (!transferred) record.deinit(engine.gpa);
    if (magic == 0) return c.pi_js_bool(context, 1);
    const object = create(engine, &record, null) catch |err| return fail(engine, err);
    transferred = true;
    return object;
}
pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.url_class != 0) return error.URLAlreadyInstalled;
    if (engine.url_search_params_class == 0) try params.install(engine);
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = "URL", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.URLClassFailed;
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "URL", 1, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, class_id, c.JS_DupValue(engine.context, prototype));
    inline for (std.meta.fields(Attribute)) |field| {
        const name: [:0]const u8 = field.name;
        const attribute: Attribute = @enumFromInt(field.value);
        const atom = c.JS_NewAtom(engine.context, name.ptr);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        const get_name: [:0]const u8 = "get " ++ field.name;
        const set_name: [:0]const u8 = "set " ++ field.name;
        const get = try engine.checked(c.pi_js_function_magic(engine.context, getter, get_name.ptr, 0, @intCast(field.value)));
        const set = if (attribute == .origin or attribute == .searchParams) c.pi_js_undefined() else try engine.checked(c.pi_js_function_magic(engine.context, setter, set_name.ptr, 1, @intCast(field.value)));
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, get, set, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    }
    inline for (.{ "toString", "toJSON" }) |name| if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_NewCFunction(engine.context, stringify, name, 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "canParse", c.pi_js_function_magic(engine.context, staticParse, "canParse", 1, 0), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0 or c.JS_DefinePropertyValueStr(engine.context, constructor, "parse", c.pi_js_function_magic(engine.context, staticParse, "parse", 1, 1), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const decoder = try property(engine, global, "decodeURIComponent");
    defer engine.freeValue(decoder);
    const symbol = try property(engine, global, "Symbol");
    defer engine.freeValue(symbol);
    const tag = try property(engine, symbol, "toStringTag");
    defer engine.freeValue(tag);
    const atom = c.JS_ValueToAtom(engine.context, tag);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_NewString(engine.context, "URL"), c.JS_PROP_CONFIGURABLE) < 0 or c.JS_DefinePropertyValueStr(engine.context, global, "URL", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.url_class = class_id;
    engine.url_decode_uri_component = c.JS_DupValue(engine.context, decoder);
    engine.native_url_constructor = c.JS_DupValue(engine.context, constructor);
}

test "native URL class serializes real records and links stable live search params through setters" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = engine.eval(
        \\const u=new URL('https://EXAMPLE.com:443/a/../b?x=hello%20world&tilde=~#f');if(u.href!=='https://example.com/b?x=hello%20world&tilde=~#f'||u.origin!=='https://example.com'||u.protocol!=='https:'||u.pathname!=='/b')throw Error('record');const p=u.searchParams;p.sort();if(u.href!=='https://example.com/b?tilde=%7E&x=hello+world#f')throw Error('linked serialization');u.search='?z=3';if(p!==u.searchParams||String(p)!=='z=3')throw Error('linked setter');p.append('z',4);if(u.search!=='?z=3&z=4')throw Error('linked append');u.href='file:///C:/a';if(p!==u.searchParams||p.size!==0||u.origin!=='null')throw Error('href reset');if(!URL.canParse('../x','https://host/a/')||URL.canParse('relative')||URL.parse('relative')!==null||!(URL.parse('https://host') instanceof URL))throw Error('static');class Child extends URL{}if(!(new Child('https://host') instanceof Child))throw Error('subclass');if(Object.prototype.toString.call(u)!=='[object URL]'||JSON.stringify(u)!=='"file:///C:/a"')throw Error('tag');
    , "native-url.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Native URL fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
}
test "native URL setter coercion reentrancy original exceptions brands and failed parses preserve state" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = engine.eval(
        \\const reason={},u=new URL('http://user:pw@a:123/x?q=1#old'),p=u.searchParams;u.host='b';u.port='42x';u.protocol='https:garbage';if(u.href!=='https://user:pw@b:42/x?q=1#old')throw Error('setters');const saved=u.href;u.hostname='bad:80';u.port='99999';if(u.href!==saved)throw Error('invalid changed');try{u.href='invalid';throw Error('invalid accepted')}catch(e){if(!(e instanceof TypeError)||e.code!=='ERR_INVALID_URL')throw e}if(u.href!==saved)throw Error('href rollback');u.search={toString(){u.hash='#inner';return'?next=2'}};if(u.hash!=='#inner'||String(p)!=='next=2')throw Error('reentrant state');for(const fn of [()=>new URL({toString(){throw reason}}),()=>new URL('https://host',{toString(){throw reason}}),()=>{u.hostname={toString(){throw reason}}},()=>URL.canParse({toString(){throw reason}})]){try{fn();throw Error('missing original')}catch(e){if(e!==reason)throw e}}for(const receiver of [{href:'https://fake'},new Proxy(u,{})]){let caught=false;try{URL.prototype.toString.call(receiver)}catch(e){caught=e instanceof TypeError}if(!caught)throw Error('brand')}const opaque=new URL('data:hello world ?x');opaque.search='';if(opaque.href!=='data:hello world%20')throw Error('opaque tail');
    , "native-url-errors.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Native URL errors: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
}

test "native URL Node24 captured properties setters and URLSearchParams foundations oracle" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const source = try std.fmt.allocPrint(engine.gpa, "globalThis.urlFoundation={s};globalThis.urlExpanded={s};", .{ @embedFile("fixtures/url_foundations_node24.json"), @embedFile("fixtures/url_expanded_node24.json") });
    defer engine.gpa.free(source);
    const loaded = try engine.eval(source, "url-node24-captured-data.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(loaded);
    const value = engine.eval(
        \\const snapshot=u=>Object.fromEntries(['href','origin','protocol','username','password','host','hostname','port','pathname','search','hash'].map(k=>[k,u[k]]));let urls=0,setters=0,params=0,differences=0;for(const f of [...urlFoundation.urlCases,...urlExpanded.urlCases]){let u,error;try{u=new URL(f.input,f.base)}catch(e){error=e.name}if(error!==f.error||(!error&&JSON.stringify(snapshot(u))!==JSON.stringify(f.result)))throw Error('URL oracle:'+JSON.stringify({f,actual:error||snapshot(u)}));urls++}for(const f of urlExpanded.setters){const u=new URL(f.base),p=u.searchParams;let error;try{u[f.key]=f.value}catch(e){error=e.name}if(f.base==='foo:/a?q#f'&&f.key==='pathname'&&f.value==='//a'){if(f.result.href!=='foo:/.//a'||f.result.search!==''||f.result.hash!==''||u.href!=='foo:/.//a?q#f'||String(p)!=='q=')throw Error('documented Node24 hostless pathname discrepancy changed');differences++}else if(error!==f.error||JSON.stringify(snapshot(u))!==JSON.stringify(f.result))throw Error('URL setter oracle:'+JSON.stringify({f,actual:error||snapshot(u)}));setters++}for(const f of urlFoundation.paramsCases){const p=new URLSearchParams(f.input),actual={text:String(p),size:p.size,entries:[...p],keys:[...p.keys()],values:[...p.values()]};if(JSON.stringify(actual)!==JSON.stringify(f.expected))throw Error('Params oracle:'+JSON.stringify({f,actual}));params++}if(urls!==124||setters!==285||params!==8||differences!==1)throw Error('oracle counts');
    , "url-node24-oracle.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Native URL Node24 oracle: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
}

test "native URL actual runtime allocation failure preserves lazy params and retries installation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    c.JS_SetMemoryLimit(engine.runtime, 1);
    try std.testing.expectError(error.SearchParamsClassFailed, install(engine));
    try std.testing.expectEqual(@as(c.JSClassID, 0), engine.url_class);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    engine.beginInvocation();
    try install(engine);
    var record = try parser.parse(engine.gpa, "https://host/a?x=1", null);
    var transferred = false;
    defer if (!transferred) record.deinit(engine.gpa);
    const object = try create(engine, &record, null);
    transferred = true;
    defer engine.freeValue(object);
    const state = try stateFor(engine, object);
    c.JS_SetMemoryLimit(engine.runtime, 1);
    try std.testing.expectError(error.JavaScriptException, searchParams(engine, object, state));
    try std.testing.expect(state.search_params == null);
    try std.testing.expectEqualStrings("x=1", state.record.query.?);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    engine.beginInvocation();
    const query = try searchParams(engine, object, state);
    defer engine.freeValue(query);
    const duplicate = try searchParams(engine, object, state);
    defer engine.freeValue(duplicate);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, query, duplicate));
    c.JS_RunGC(engine.runtime);
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    var record = try parser.parse(gpa, "https://user:pw@bücher.example/a/../b?x=hello%20world&tilde=~#f", null);
    var transferred = false;
    defer if (!transferred) record.deinit(gpa);
    const object = try create(engine, &record, null);
    transferred = true;
    defer engine.freeValue(object);
    const state = try stateFor(engine, object);
    const query = try searchParams(engine, object, state);
    defer engine.freeValue(query);
    const next = try engine.checked(c.JS_NewString(engine.context, "?a=1&a=2"));
    defer engine.freeValue(next);
    try setValue(engine, object, .search, next);
    const hostname = try engine.checked(c.JS_NewString(engine.context, "[2001:db8::1]"));
    defer engine.freeValue(hostname);
    try setValue(engine, object, .hostname, hostname);
    const encoded = try parser.serialize(gpa, state.record);
    defer gpa.free(encoded);
    try std.testing.expectEqualStrings("https://user:pw@[2001:db8::1]/b?a=1&a=2#f", encoded);
    const params_state = try params.stateFor(engine, query);
    try std.testing.expectEqual(@as(usize, 2), params_state.pairs.items.len);
    c.JS_RunGC(engine.runtime);
}
test "native URL every allocator failure releases parser setters live params and GC association cycles" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
