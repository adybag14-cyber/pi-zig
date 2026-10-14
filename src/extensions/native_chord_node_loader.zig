//! Actual Source1692 nodeLoader: register every root first, propagate generations and import sequential fresh modules.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const files = @import("file_urls.zig");
const parameter = "chord2-reload";
fn url(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const constructor = try s.keep(try js.global(s.engine, "URL"));
    return s.keep(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr))));
}
fn physical(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return if (std.mem.startsWith(u8, name, "file:")) files.toPath(gpa, name, builtin.os.tag == .windows) else gpa.dupe(u8, name);
}
fn normalizeFs(raw: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8) anyerror![]u8 {
    const engine: *em.Engine = @ptrCast(@alignCast(raw.?));
    const io = engine.native_io orelse return error.NativeNodeLoaderIoUnavailable;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var resolver: @import("module_resolver.zig").Resolver = .{ .io = io, .native_modules = &engine.native_module_names };
    return gpa.dupe(u8, try resolver.resolve(arena.allocator(), base, specifier));
}
fn normalizeRequireFs(raw: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, specifier: []const u8) anyerror![]u8 {
    const engine: *em.Engine = @ptrCast(@alignCast(raw.?));
    const io = engine.native_io orelse return error.NativeNodeLoaderIoUnavailable;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var resolver: @import("module_resolver.zig").Resolver = .{ .io = io, .native_modules = &engine.native_module_names, .require_mode = true };
    return gpa.dupe(u8, try resolver.resolve(arena.allocator(), base, specifier));
}
fn loadFs(raw: ?*anyopaque, gpa: std.mem.Allocator, name: []const u8) anyerror![]u8 {
    const engine: *em.Engine = @ptrCast(@alignCast(raw.?));
    const io = engine.native_io orelse return error.NativeNodeLoaderIoUnavailable;
    const source = try std.Io.Dir.cwd().readFileAlloc(io, name, gpa, .limited(16 * 1024 * 1024));
    errdefer gpa.free(source);
    if (std.mem.endsWith(u8, name, ".ts") or std.mem.endsWith(u8, name, ".mts") or std.mem.endsWith(u8, name, ".cts")) {
        const transformed = try @import("typescript.zig").transform(gpa, source);
        gpa.free(source);
        return transformed;
    }
    return source;
}
fn inputFs(raw: ?*anyopaque, engine: *em.Engine, name: []const u8) anyerror!em.ModuleInput {
    const source = try loadFs(raw, engine.gpa, name);
    errdefer engine.gpa.free(source);
    const json = std.mem.endsWith(u8, name, ".json");
    var common = std.mem.endsWith(u8, name, ".cjs") or std.mem.endsWith(u8, name, ".cts");
    if (!common and std.mem.endsWith(u8, name, ".js")) {
        const io = engine.native_io orelse return error.NativeNodeLoaderIoUnavailable;
        var directory = std.fs.path.dirname(name) orelse ".";
        var package_type: ?[]u8 = null;
        defer if (package_type) |value| engine.gpa.free(value);
        while (true) {
            const path = try std.fs.path.join(engine.gpa, &.{ directory, "package.json" });
            defer engine.gpa.free(path);
            const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
                error.FileNotFound, error.NotDir => null,
                else => return err,
            };
            if (bytes) |value| {
                defer engine.gpa.free(value);
                const parsed = try std.json.parseFromSlice(std.json.Value, engine.gpa, value, .{});
                defer parsed.deinit();
                if (parsed.value != .object) return error.InvalidExtensionPackage;
                if (parsed.value.object.get("type")) |kind| {
                    if (kind != .string) return error.InvalidExtensionPackage;
                    package_type = try engine.gpa.dupe(u8, kind.string);
                }
                break;
            }
            if (std.mem.eql(u8, std.fs.path.basename(directory), "node_modules")) break;
            const parent = std.fs.path.dirname(directory) orelse break;
            if (std.mem.eql(u8, parent, directory)) break;
            directory = parent;
        }
        common = if (package_type) |kind| std.mem.eql(u8, kind, "commonjs") else !try @import("typescript.zig").hasModuleSyntax(source);
    }
    if (common or json) {
        const value = try @import("commonjs.zig").load(engine, source, name, json);
        engine.gpa.free(source);
        return .{ .exports = value };
    }
    return .{ .source = source };
}
fn normalizeHook(engine: *em.Engine, base: []const u8, specifier: []const u8) anyerror!?[]u8 {
    const path_like = std.mem.startsWith(u8, specifier, "file:") or std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../") or std.fs.path.isAbsolute(specifier);
    const has_suffix = path_like and std.mem.indexOfAny(u8, specifier, "?#") != null;
    if (!has_suffix and std.mem.indexOf(u8, base, parameter) == null) return null;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const base_path = try physical(engine.gpa, base);
    defer engine.gpa.free(base_path);
    var base_url = c.pi_js_undefined();
    if (std.mem.startsWith(u8, base, "file:")) {
        base_url = try url(&s, &.{try s.text(base)});
    } else if (std.fs.path.isAbsolute(base_path)) {
        const text = try files.fromPath(engine.gpa, base_path, builtin.os.tag == .windows);
        defer engine.gpa.free(text);
        base_url = try url(&s, &.{try s.text(text)});
    }
    const version = if (c.JS_IsUndefined(base_url)) c.pi_js_null() else try h.invoke(&s, try s.get(base_url, "searchParams"), "get", &.{try s.text(parameter)});
    if (!has_suffix and c.JS_IsNull(version)) return null;
    var explicit_url = c.pi_js_undefined();
    var physical_specifier: ?[]u8 = null;
    defer if (physical_specifier) |value| engine.gpa.free(value);
    if (path_like and (has_suffix or std.mem.startsWith(u8, specifier, "file:"))) {
        explicit_url = if (c.JS_IsUndefined(base_url)) try url(&s, &.{try s.text(specifier)}) else try url(&s, &.{ try s.text(specifier), base_url });
        const href = try engine.toString(try s.get(explicit_url, "href"));
        defer engine.gpa.free(href);
        physical_specifier = try physical(engine.gpa, href);
    }
    const selected = physical_specifier orelse specifier;
    const registered = engine.native_module_names.contains(selected);
    const schema_package = @import("module_resolver.zig").Resolver.preferExternal(selected);
    const resolved = if ((registered and !schema_package) or engine.modules.contains(selected)) try engine.gpa.dupe(u8, selected) else blk: {
        const loader = engine.source_loader.?;
        const resolution = if (loader.normalize) |resolver| resolver(loader.context, engine.gpa, base_path, selected) else normalizeFs(engine, engine.gpa, base_path, selected);
        break :blk resolution catch |err| {
            if (err == error.ExtensionModuleNotFound and registered) break :blk try engine.gpa.dupe(u8, selected);
            return err;
        };
    };
    if (!std.fs.path.isAbsolute(resolved) and !std.mem.startsWith(u8, resolved, "file:")) return resolved;
    defer engine.gpa.free(resolved);
    const canonical = if (std.mem.startsWith(u8, resolved, "file:")) try engine.gpa.dupe(u8, resolved) else try files.fromPath(engine.gpa, resolved, builtin.os.tag == .windows);
    defer engine.gpa.free(canonical);
    const target = try url(&s, &.{try s.text(canonical)});
    if (!c.JS_IsUndefined(explicit_url)) {
        try r.put(&s, target, "search", try s.get(explicit_url, "search"));
        try r.put(&s, target, "hash", try s.get(explicit_url, "hash"));
    }
    if (!c.JS_IsNull(version) and c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(target, "searchParams"), "has", &.{try s.text(parameter)})) == 0) {
        const roots = try h.snapshot(&s, try s.get(engine.native_chord_loader_state.?, "roots"));
        for (0..try h.length(&s, roots)) |index| {
            if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(target, "href"), "startsWith", &.{try s.at(roots, index)})) == 0) continue;
            _ = try h.invoke(&s, try s.get(target, "searchParams"), "set", &.{ try s.text(parameter), version });
            break;
        }
    }
    return try engine.toString(try s.get(target, "href"));
}
fn inputHook(engine: *em.Engine, name: []const u8) anyerror!?em.ModuleInput {
    if (!std.mem.startsWith(u8, name, "file:")) return null;
    const path = try physical(engine.gpa, name);
    defer engine.gpa.free(path);
    const loader = engine.source_loader.?;
    if (loader.input) |input| return try input(loader.context, engine, path);
    return @as(em.ModuleInput, .{ .source = try loader.load(loader.context, engine.gpa, path) });
}
fn selectUrl(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return toUrl(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn toUrl(engine: *em.Engine, state: c.JSValue, module: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const instance = c.JS_IsInstanceOf(engine.context, module, try s.keep(try js.global(engine, "URL")));
    if (instance < 0) return js.capture(engine);
    const value = if (instance != 0) try s.get(module, "href") else if (c.JS_ToBool(engine.context, try h.invoke(&s, module, "startsWith", &.{try s.text("file:")})) != 0) module else try s.get(try s.keep(try js.call(engine, try s.get(state, "pathToFileURL"), c.pi_js_undefined(), &.{module})), "href");
    const result = try url(&s, &.{value});
    try r.put(&s, result, "search", try s.text(""));
    return s.result(result);
}
fn load(engine: *em.Engine, state: c.JSValue, modules: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (!try h.flag(&s, state, "hooked")) {
        try h.field(&s, state, "hooked", c.pi_js_bool(engine.context, 1));
        if (engine.source_loader == null) {
            try @import("commonjs.zig").install(engine);
            engine.setSourceLoader(.{ .context = engine, .normalize = normalizeFs, .normalize_require = normalizeRequireFs, .load = loadFs, .input = inputFs });
        }
        engine.setChordModuleHooks(normalizeHook, inputHook);
    }
    const generation = try s.keep(try engine.checked(c.JS_PiIncrement(engine.context, try s.get(state, "generation"))));
    try h.field(&s, state, "generation", generation);
    const version = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "String")), c.pi_js_undefined(), &.{generation}));
    var captures = [_]c.JSValue{state};
    const mapper = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, selectUrl, "", 1, 0, 1, &captures)));
    const urls = try h.invoke(&s, modules, "map", &.{mapper});
    var roots = try r.iterate(&s, urls);
    defer roots.deinit();
    errdefer roots.closePreserving();
    while (try roots.next()) |entry| {
        defer engine.freeValue(entry);
        const directory = try url(&s, &.{ try s.text("."), entry });
        _ = try h.invoke(&s, try s.get(state, "roots"), "add", &.{try s.get(directory, "href")});
    }
    const task = try s.record();
    try h.field(&s, task, "urls", try h.invoke(&s, urls, "values", &.{}));
    try h.field(&s, task, "facets", try s.list());
    try h.field(&s, task, "version", version);
    return next(engine, task, c.pi_js_undefined(), false, 0);
}
fn next(engine: *em.Engine, task: c.JSValue, loaded: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, loaded);
    if (phase == 1) {
        const definition = try s.get(loaded, "default");
        if (c.JS_IsUndefined(definition) or !c.JS_IsFunction(engine.context, try s.get(definition, "setup"))) return h.typeError(&s, &.{ try s.get(task, "name"), try s.text(": default export must be a facet (defineFacet)") });
        const facet = try s.record();
        try h.field(&s, facet, "name", try s.get(task, "name"));
        try h.field(&s, facet, "setup", try s.get(definition, "setup"));
        try h.field(&s, facet, "uses", try s.get(definition, "uses"));
        try js.push(engine, try s.get(task, "facets"), facet);
    }
    const entry = try r.next(&s, try s.get(task, "urls")) orelse return js.get(engine, task, "facets");
    try h.field(&s, task, "name", try s.get(entry, "href"));
    _ = try h.invoke(&s, try s.get(entry, "searchParams"), "set", &.{ try s.text(parameter), try s.get(task, "version") });
    const href = try engine.toString(try s.get(entry, "href"));
    defer engine.gpa.free(href);
    const terminated = try engine.gpa.dupeZ(u8, href);
    defer engine.gpa.free(terminated);
    const imported = try s.keep(try engine.checked(c.JS_LoadModule(engine.context, "pi-native:chord-node-loader", terminated)));
    return h.wait(next, engine, task, imported, 1);
}
fn loadFunction(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    const pending = load(engine, captures[0], h.arg(args, 0)) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(pending);
    return @import("native_durable.zig").resolvedPromise(engine, pending);
}
fn loaderCallback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return loadFunction(engine, c.pi_js_undefined(), if (argc > 0) argv[0..@intCast(argc)] else &.{}, captures[0..1]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try @import("node_url.zig").install(engine);
    if (engine.native_chord_loader_state == null) {
        const state = try s.record();
        try h.field(&s, state, "roots", try h.set(&s));
        try h.field(&s, state, "generation", c.JS_NewInt32(engine.context, 0));
        try h.field(&s, state, "hooked", c.pi_js_bool(engine.context, 0));
        const node_url = try s.keep((try engine.requireBuiltin("node:url")).?);
        try h.field(&s, state, "pathToFileURL", try s.get(node_url, "pathToFileURL"));
        engine.native_chord_loader_state = s.result(state);
    }
    var captures = [_]c.JSValue{engine.native_chord_loader_state.?};
    const function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, loaderCallback, "nodeLoader", 1, 0, 1, &captures)));
    const prototype = try s.keep(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return js.capture(engine);
    return s.result(function);
}
