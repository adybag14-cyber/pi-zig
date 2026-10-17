//! get-tsconfig 4.14.0 config inheritance, path rewriting and compiler defaults.
const h = @import("native_tsconfig_values.zig");
const c = h.c;
const Scope = h.Scope;
const placeholder = "${configDir}";
const files_fields = .{ "files", "include", "exclude" };
const output_fields = .{ "outDir", "declarationDir" };
const MapMode = enum(u32) { slash, relative, absolute, inherited_path, inherited_pattern, interpolate, interpolate_relative, lower };
fn interpolate(s: *Scope, state: c.JSValue, value: c.JSValue, directory: c.JSValue) !c.JSValue {
    if (!try h.starts(s, value, placeholder)) return c.pi_js_undefined();
    const tail = try s.invoke(value, "slice", &.{h.n(s, placeholder.len)});
    return h.slash(s, try h.path(s, state, "join", &.{ directory, tail }));
}
fn rewriteInherited(s: *Scope, state: c.JSValue, from: c.JSValue, directory: c.JSValue, value: c.JSValue) !c.JSValue {
    if (try h.starts(s, value, placeholder)) return value;
    const absolute = try h.path(s, state, "join", &.{ directory, value });
    const relative = try h.slash(s, try h.path(s, state, "relative", &.{ from, absolute }));
    return if (s.truthy(relative)) relative else s.text("./");
}
fn mapped(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const value = h.arg(args, 0); const state = roots[0]; const from = roots[1]; const directory = roots[2];
    var tag: u32 = 0; if (c.JS_ToUint32(engine.context, &tag, roots[3]) < 0) return h.v.js.capture(engine);
    const result = switch (@as(MapMode, @enumFromInt(tag))) {
        .slash => try h.slash(&s, value),
        .relative => if (try h.starts(&s, value, placeholder)) value else try h.normalizeRelative(&s, state, value),
        .absolute => try h.slash(&s, try h.path(&s, state, "resolve", &.{ from, value })),
        .inherited_path => try rewriteInherited(&s, state, from, directory, value),
        .inherited_pattern => blk: {
            if (try h.starts(&s, value, placeholder)) break :blk value;
            const relative = try h.path(&s, state, "relative", &.{ from, directory });
            if (!s.truthy(relative)) break :blk value;
            const cleaned = if (try h.starts(&s, value, "./")) try s.invoke(value, "slice", &.{h.n(&s, 2)}) else value;
            break :blk try h.slash(&s, try s.concat(try s.concat(try s.stringify(relative), try s.text("/")), try s.stringify(cleaned)));
        },
        .interpolate, .interpolate_relative => blk: {
            const expanded = try interpolate(&s, state, value, from);
            break :blk if (!c.JS_IsUndefined(expanded)) (if (tag == @intFromEnum(MapMode.interpolate_relative)) try h.pathRelative(&s, state, from, expanded) else expanded) else if (tag == @intFromEnum(MapMode.interpolate_relative)) try h.normalizeRelative(&s, state, value) else value;
        },
        .lower => try s.invoke(value, "toLowerCase", &.{}),
    };
    return c.JS_DupValue(engine.context, result);
}
fn map(s: *Scope, state: c.JSValue, values: c.JSValue, from: c.JSValue, directory: c.JSValue, mode: MapMode) !c.JSValue {
    const method = try s.get(values, "map");
    const callback = try s.own(try h.functions.createArrow(s.engine, "", 1, h.Boundary(mapped).invoke, &.{ state, from, directory, c.JS_NewUint32(s.engine.context, @intFromEnum(mode)) }));
    return s.call(method, values, &.{callback});
}
fn setDefault(s: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue, undefined_only: bool) !void {
    const old = try s.get(object, name);
    if (c.JS_IsUndefined(old) or (!undefined_only and c.JS_IsNull(old))) try s.set(object, name, value);
}
fn oneOf(s: *Scope, value: c.JSValue, comptime names: anytype) !bool { inline for (names) |name| if (try h.eq(s, value, name)) return true; return false; }
fn lower(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try s.get(object, name); if (!s.truthy(value)) return value;
    const normalized = try s.invoke(value, "toLowerCase", &.{}); try s.set(object, name, normalized); return normalized;
}
fn defaults(s: *Scope, state: c.JSValue, options: c.JSValue) !void {
    const yes = c.pi_js_bool(s.engine.context, 1);
    if (s.truthy(try s.get(options, "strict"))) inline for (.{ "noImplicitAny", "noImplicitThis", "strictNullChecks", "strictFunctionTypes", "strictBindCallApply", "strictPropertyInitialization", "strictBuiltinIteratorReturn", "alwaysStrict", "useUnknownInCatchVariables" }) |name| try setDefault(s, options, name, yes, true);
    if (s.truthy(try s.get(options, "composite"))) { try setDefault(s, options, "declaration", yes, false); try setDefault(s, options, "incremental", yes, false); }
    var target = try lower(s, options, "target");
    if (try h.eq(s, target, "es2015")) { target = try s.text("es6"); try s.set(options, "target", target); }
    if (try h.eq(s, target, "esnext")) { try setDefault(s, options, "module", try s.text("es6"), false); try setDefault(s, options, "useDefineForClassFields", yes, false); }
    if (try oneOf(s, target, .{ "es6", "es2016", "es2017", "es2018", "es2019", "es2020", "es2021", "es2022", "es2023", "es2024" })) try setDefault(s, options, "module", try s.text("es6"), false);
    if (try oneOf(s, target, .{ "es2022", "es2023", "es2024" })) try setDefault(s, options, "useDefineForClassFields", yes, false);
    var module = try lower(s, options, "module");
    if (try h.eq(s, module, "es2015")) { module = try s.text("es6"); try s.set(options, "module", module); }
    if (try oneOf(s, module, .{ "es6", "es2020", "es2022", "esnext", "none", "system", "umd", "amd" })) try setDefault(s, options, "moduleResolution", try s.text("classic"), false);
    if (try h.eq(s, module, "system")) try setDefault(s, options, "allowSyntheticDefaultImports", yes, false);
    if (try oneOf(s, module, .{ "node16", "node18", "node20", "nodenext", "preserve" })) { try setDefault(s, options, "esModuleInterop", yes, false); try setDefault(s, options, "allowSyntheticDefaultImports", yes, false); }
    const node_module = try oneOf(s, module, .{ "node16", "node18", "node20", "nodenext" });
    if (node_module) try setDefault(s, options, "moduleDetection", try s.text("force"), false);
    if (try oneOf(s, module, .{ "node16", "node18" })) { try setDefault(s, options, "target", try s.text("es2022"), false); try setDefault(s, options, "moduleResolution", try s.text("node16"), false); }
    if (try h.eq(s, module, "node20")) { try setDefault(s, options, "target", try s.text("es2023"), false); try setDefault(s, options, "moduleResolution", try s.text("node16"), false); try setDefault(s, options, "resolveJsonModule", yes, false); }
    if (try h.eq(s, module, "nodenext")) { try setDefault(s, options, "target", try s.text("esnext"), false); try setDefault(s, options, "moduleResolution", try s.text("nodenext"), false); try setDefault(s, options, "resolveJsonModule", yes, false); }
    if (node_module and try oneOf(s, try s.get(options, "target"), .{ "es3", "es2022", "es2023", "es2024", "esnext" })) try setDefault(s, options, "useDefineForClassFields", yes, false);
    if (try h.eq(s, module, "preserve")) try setDefault(s, options, "moduleResolution", try s.text("bundler"), false);
    var resolution = try lower(s, options, "moduleResolution");
    if (try h.eq(s, resolution, "node")) { resolution = try s.text("node10"); try s.set(options, "moduleResolution", resolution); }
    if (try oneOf(s, resolution, .{ "node16", "nodenext", "bundler" })) { try setDefault(s, options, "resolvePackageJsonExports", yes, false); try setDefault(s, options, "resolvePackageJsonImports", yes, false); }
    if (try h.eq(s, resolution, "bundler")) { try setDefault(s, options, "allowSyntheticDefaultImports", yes, false); try setDefault(s, options, "resolveJsonModule", yes, false); }
    inline for (.{ "jsx", "moduleDetection", "importsNotUsedAsValues", "newLine" }) |name| _ = try lower(s, options, name);
    if (s.truthy(try s.get(options, "esModuleInterop"))) try setDefault(s, options, "allowSyntheticDefaultImports", yes, false);
    if (s.truthy(try s.get(options, "verbatimModuleSyntax"))) { try setDefault(s, options, "isolatedModules", yes, false); try setDefault(s, options, "preserveConstEnums", yes, false); }
    if (s.truthy(try s.get(options, "isolatedModules"))) try setDefault(s, options, "preserveConstEnums", yes, false);
    if (s.truthy(try s.get(options, "rewriteRelativeImportExtensions"))) try setDefault(s, options, "allowImportingTsExtensions", yes, false);
    const libraries = try s.get(options, "lib"); if (s.truthy(libraries)) try s.set(options, "lib", try map(s, state, libraries, c.pi_js_undefined(), c.pi_js_undefined(), .lower));
    if (s.truthy(try s.get(options, "checkJs"))) try setDefault(s, options, "allowJs", yes, false);
}
fn inherited(engine: *h.v.em.Engine, state: c.JSValue, requested: c.JSValue, from: c.JSValue, tracker: c.JSValue, cache: c.JSValue, depth: usize) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const resolved = try s.own(try @import("native_tsconfig_extends.zig").resolve(engine, state, requested, from, cache));
    if (!s.truthy(resolved)) return h.throw(&s, "Error", try s.concat(try s.concat(try s.text("File '"), try s.stringify(requested)), try s.text("' not found.")));
    if (s.truthy(try s.invoke(tracker, "has", &.{resolved}))) return h.throw(&s, "Error", try s.concat(try s.text("Circularity detected while resolving configuration: "), try s.stringify(resolved)));
    _ = try s.invoke(tracker, "add", &.{resolved});
    const directory = try h.path(&s, state, "dirname", &.{resolved});
    const config = try s.own(try parseInternal(engine, state, resolved, cache, tracker, depth + 1)); try h.remove(&s, config, "references");
    const options = try s.get(config, "compilerOptions");
    if (s.truthy(options)) {
        inline for (.{ "baseUrl", "outDir", "declarationDir", "rootDir" }) |name| { const value = try s.get(options, name); if (s.truthy(value) and !try h.starts(&s, value, placeholder)) try s.set(options, name, try rewriteInherited(&s, state, from, directory, value)); }
        inline for (.{ "rootDirs", "typeRoots" }) |name| { const value = try s.get(options, name); if (s.truthy(value)) try s.set(options, name, try map(&s, state, value, from, directory, .inherited_path)); }
    }
    inline for (files_fields) |name| { const value = try s.get(config, name); if (s.truthy(value)) try s.set(config, name, try map(&s, state, value, from, directory, .inherited_pattern)); }
    return c.JS_DupValue(engine.context, config);
}
fn merged(s: *Scope, base: c.JSValue, own: c.JSValue) !c.JSValue { const result = try s.own(try h.v.js.spread(s.engine, base)); try h.v.js.spreadInto(s.engine, result, own); return result; }
fn parseInternal(engine: *h.v.em.Engine, state: c.JSValue, file: c.JSValue, cache: c.JSValue, tracker: c.JSValue, depth: usize) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); if (depth > 128) return h.quota(&s, "Native tsconfig extends nesting quota exceeded");
    const generation = engine.native_allocation_generation;
    const parsed = h.read(&s, state, cache, file) catch |err| { try h.ordinary(engine, err, generation); return h.throw(&s, "Error", try s.concat(try s.text("Cannot resolve tsconfig at path: "), try s.stringify(file))); };
    var config = if (s.truthy(parsed)) parsed else try s.object();
    if (!c.JS_IsObject(config)) return h.throw(&s, "SyntaxError", try s.concat(try s.text("Failed to parse tsconfig at: "), try s.stringify(file)));
    const directory = try h.path(&s, state, "dirname", &.{file});
    const initial_options = try s.get(config, "compilerOptions");
    if (s.truthy(initial_options) and s.truthy(try s.get(initial_options, "paths")) and !s.truthy(try s.get(initial_options, "baseUrl"))) try h.v.js.setKey(engine, initial_options, try s.get(state, "implicitBaseUrl"), directory);
    const extended = try s.get(config, "extends");
    if (s.truthy(extended)) {
        const list = if (try h.v.array(&s, extended)) extended else try h.array(&s, &.{extended}); try h.remove(&s, config, "extends");
        const reversed = try s.invoke(list, "reverse", &.{});
        for (0..try h.length(&s, reversed)) |i| {
            var row: Scope = .{ .engine = engine }; defer row.deinit();
            const copied_tracker = try row.own(try h.v.js.builtin(engine, "Set", &.{tracker}));
            const parent = try row.own(try inherited(engine, state, try h.at(&row, reversed, @intCast(i)), directory, copied_tracker, cache, depth));
            const result = try merged(&row, parent, config);
            try row.set(result, "compilerOptions", try merged(&row, try row.get(parent, "compilerOptions"), try row.get(config, "compilerOptions")));
            const parent_watch = try row.get(parent, "watchOptions");
            if (row.truthy(parent_watch)) try row.set(result, "watchOptions", try merged(&row, parent_watch, try row.get(config, "watchOptions")));
            config = try s.own(c.JS_DupValue(engine.context, result));
        }
    }
    const options = try s.get(config, "compilerOptions");
    if (s.truthy(options)) {
        inline for (.{ "baseUrl", "rootDir" }) |name| { const value = try s.get(options, name); if (s.truthy(value) and !try h.starts(&s, value, placeholder)) try s.set(options, name, try h.pathRelative(&s, state, directory, try h.path(&s, state, "resolve", &.{ directory, value }))); }
        inline for (output_fields) |name| {
            const value = try s.get(options, name);
            if (s.truthy(value)) {
                if (!try h.v.array(&s, try s.get(config, "exclude"))) {
                    const exclusions = try s.array(); inline for (output_fields) |field| { const entry = try s.get(options, field); if (s.truthy(entry)) try h.push(&s, exclusions, entry); } try s.set(config, "exclude", exclusions);
                }
                try s.set(options, name, if (try h.starts(&s, value, placeholder)) value else try h.normalizeRelative(&s, state, value));
            }
        }
    } else try s.set(config, "compilerOptions", try s.object());
    const include = try s.get(config, "include"); if (s.truthy(include)) try s.set(config, "include", try map(&s, state, include, directory, directory, .slash));
    const files = try s.get(config, "files"); if (s.truthy(files)) try s.set(config, "files", try map(&s, state, files, directory, directory, .relative));
    const watch = try s.get(config, "watchOptions");
    if (s.truthy(watch)) {
        inline for (.{ "excludeDirectories", "excludeFiles" }) |name| { const value = try s.get(watch, name); if (s.truthy(value)) try s.set(watch, name, try map(&s, state, value, directory, directory, .absolute)); }
        inline for (.{ "watchFile", "watchDirectory", "fallbackPolling" }) |name| _ = try lower(&s, watch, name);
    }
    return c.JS_DupValue(engine.context, config);
}
pub fn parse(engine: *h.v.em.Engine, state: c.JSValue, file: c.JSValue, cache: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const resolved = try h.path(&s, state, "resolve", &.{file}); const tracker = try s.own(try h.v.js.builtin(engine, "Set", &.{}));
    const config = try s.own(try parseInternal(engine, state, resolved, cache, tracker, 0)); const directory = try h.path(&s, state, "dirname", &.{resolved});
    const options = try s.get(config, "compilerOptions");
    if (s.truthy(options)) {
        inline for (.{ "outDir", "declarationDir", "outFile", "rootDir", "baseUrl", "tsBuildInfoFile" }) |name| { const value = try s.get(options, name); if (s.truthy(value)) { const expanded = try interpolate(&s, state, value, directory); if (s.truthy(expanded)) try s.set(options, name, try h.pathRelative(&s, state, directory, expanded)); } }
        inline for (.{ "rootDirs", "typeRoots" }) |name| { const value = try s.get(options, name); if (s.truthy(value)) try s.set(options, name, try map(&s, state, value, directory, directory, .interpolate_relative)); }
        const paths = try s.get(options, "paths");
        if (s.truthy(paths)) {
            const names = try s.invoke(try s.global("Object"), "keys", &.{paths});
            for (0..try h.length(&s, names)) |i| { var row: Scope = .{ .engine = engine }; defer row.deinit(); const name = try h.at(&row, names, @intCast(i)); try h.v.js.setKey(engine, paths, name, try map(&row, state, try h.key(&row, paths, name), directory, directory, .interpolate)); }
        }
        try defaults(&s, state, options);
    }
    inline for (files_fields) |name| { const value = try s.get(config, name); if (s.truthy(value)) try s.set(config, name, try map(&s, state, value, directory, directory, .interpolate)); }
    return c.JS_DupValue(engine.context, config);
}
