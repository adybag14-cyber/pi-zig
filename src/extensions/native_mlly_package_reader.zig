//! Actual import-meta-resolve4.2.0 package-json-reader cache/read/scope walk.
//! Ordinary Source catches transfer their raw reason; native failures bypass.
const m = @import("native_mlly_values.zig");
const errors = @import("native_mlly_errors.zig");
const c = m.c;
const Scope = m.Scope;

pub fn read(context: m.Context, s: *Scope, json_path: c.JSValue, base: c.JSValue, specifier: c.JSValue) anyerror!c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return readBody(context, s, json_path, base, specifier) catch |err| return m.exact(s.engine, err, generation);
}
fn readFile(context: m.Context, s: *Scope, json_path: c.JSValue) !c.JSValue {
    const fs = try context.get(s, "fs");
    const read_file = try s.get(fs, "readFileSync");
    const path = try context.get(s, "path");
    const native_path = try s.invoke(path, "toNamespacedPath", &.{json_path});
    return s.call(read_file, fs, &.{ native_path, try s.text("utf8") });
}
fn parse(s: *Scope, text: c.JSValue) !c.JSValue { return s.invoke(try s.global("JSON"), "parse", &.{text}); }
fn readBody(context: m.Context, s: *Scope, json_path: c.JSValue, base: c.JSValue, specifier: c.JSValue) anyerror!c.JSValue {
    const cache = try context.get(s, "packageCache");
    const existing = try s.invoke(cache, "get", &.{json_path});
    if (s.truthy(existing)) return existing;
    const generation = s.engine.native_allocation_generation;
    const string = readFile(context, s, json_path) catch |err| blk: {
        const exception = try m.caught(s, err, generation);
        if (!try m.equal(s, try s.get(exception, "code"), "ENOENT")) return m.throwReason(s.engine, exception);
        break :blk c.pi_js_undefined();
    };
    const result = try s.object();
    try m.define(s, result, "exists", c.pi_js_bool(s.engine.context, 0)); try m.define(s, result, "pjsonPath", json_path);
    try m.define(s, result, "main", c.pi_js_undefined()); try m.define(s, result, "name", c.pi_js_undefined());
    try m.define(s, result, "type", try s.text("none")); try m.define(s, result, "exports", c.pi_js_undefined()); try m.define(s, result, "imports", c.pi_js_undefined());
    if (!c.JS_IsUndefined(string)) {
        const parsed = parse(s, string) catch |err| {
            const cause = try m.caught(s, err, generation);
            const prefix = if (s.truthy(base)) try errors.template(s, &.{ try s.text("\""), specifier, try s.text("\" from ") }) else try s.text("");
            const imported_from = try s.concat(prefix, try context.file(s, if (s.truthy(base)) base else specifier));
            const message = try s.get(cause, "message");
            const exception = try errors.create(context, s, .ERR_INVALID_PACKAGE_CONFIG, &.{ json_path, imported_from, message });
            try s.set(exception, "cause", cause);
            return m.throwReason(s.engine, exception);
        };
        try s.set(result, "exists", c.pi_js_bool(s.engine.context, 1));
        inline for (.{ "name", "main" }) |name| {
            if (try context.own(s, parsed, try s.text(name))) {
                if (c.JS_IsString(try s.get(parsed, name))) try s.set(result, name, try s.get(parsed, name));
            }
        }
        inline for (.{ "exports", "imports" }) |name| if (try context.own(s, parsed, try s.text(name))) try s.set(result, name, try s.get(parsed, name));
        if (try context.own(s, parsed, try s.text("type"))) {
            if (try m.equal(s, try s.get(parsed, "type"), "commonjs") or try m.equal(s, try s.get(parsed, "type"), "module")) try s.set(result, "type", try s.get(parsed, "type"));
        }
    }
    _ = try s.invoke(cache, "set", &.{ json_path, result });
    return result;
}

pub fn getPackageScopeConfig(context: m.Context, s: *Scope, resolved: c.JSValue) anyerror!c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return scopeBody(context, s, resolved) catch |err| return m.exact(s.engine, err, generation);
}
fn scopeBody(context: m.Context, s: *Scope, resolved: c.JSValue) anyerror!c.JSValue {
    var url = c.JS_DupValue(s.engine.context, try context.url(s, try s.text("package.json"), resolved));
    defer s.engine.freeValue(url);
    var steps: usize = 0;
    while (true) {
        try m.budget(s.engine, &steps);
        var step: Scope = .{ .engine = s.engine }; defer step.deinit();
        const package_path = try step.get(url, "pathname");
        if (step.truthy(try step.invoke(package_path, "endsWith", &.{try step.text("node_modules/package.json")}))) break;
        const config = try read(context, &step, try context.file(&step, url), c.pi_js_undefined(), resolved);
        if (step.truthy(try step.get(config, "exists"))) return s.own(c.JS_DupValue(s.engine.context, config));
        const next = try context.url(&step, try step.text("../package.json"), url);
        const same = step.equal(try step.get(next, "pathname"), try step.get(url, "pathname"));
        const previous = url; url = c.JS_DupValue(s.engine.context, next); s.engine.freeValue(previous);
        if (same) break;
    }
    const path = try context.file(s, url);
    const result = try s.object();
    try m.define(s, result, "pjsonPath", path); try m.define(s, result, "exists", c.pi_js_bool(s.engine.context, 0)); try m.define(s, result, "type", try s.text("none"));
    return result;
}
