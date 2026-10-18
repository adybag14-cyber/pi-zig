//! Native named minimatch export for Pi's PackageManager/model resolver.
//! This is a component factory, not a public package-loader registration.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_function.zig");
const glob = @import("native_minimatch.zig");

fn bytes16(engine: *v.em.Engine, value: c.JSValue) ![]u8 {
    var length: usize = 0;
    const units = c.JS_ToCStringLenUTF16(engine.context, &length, value);
    if (units == null) return v.js.capture(engine);
    defer c.JS_FreeCStringUTF16(engine.context, units);
    return glob.encodeUnits(engine.gpa, units[0..length]);
}
fn text16(engine: *v.em.Engine, bytes: []const u8) !c.JSValue {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const units = try glob.decodeUnits(arena.allocator(), bytes);
    return engine.checked(c.JS_NewStringUTF16(engine.context, units.values.ptr, units.values.len));
}

pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const exports = try s.object();
    try s.put(exports, "minimatch", try s.own(try functions.createArrow(engine, "minimatch", 2, minimatch, &.{})));
    return c.JS_DupValue(engine.context, exports);
}

fn checkOptions(engine: *v.em.Engine, value: c.JSValue) !void {
    if (c.JS_IsUndefined(value)) return;
    if (!c.JS_IsObject(value)) return error.MinimatchOptionsOutsidePiContract;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, value)));
    const ordinary = try scope.object();
    const ordinary_prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, ordinary)));
    if (!c.JS_IsNull(prototype) and !scope.equal(prototype, ordinary_prototype)) return error.MinimatchOptionsOutsidePiContract;
    if (!c.JS_IsNull(prototype)) {
        const atom = c.JS_NewAtom(engine.context, "nocase");
        if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
        defer c.JS_FreeAtom(engine.context, atom);
        var inherited: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &inherited, prototype, atom);
        if (present < 0) return v.js.capture(engine);
        if (present > 0) {
            engine.freeValue(inherited.value);
            engine.freeValue(inherited.getter);
            engine.freeValue(inherited.setter);
            return error.MinimatchOptionsOutsidePiContract;
        }
    }
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        const key = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
        defer engine.freeValue(key);
        if (!c.JS_IsString(key)) return error.MinimatchOptionUnsupported;
        const text = try engine.toString(key);
        defer engine.gpa.free(text);
        if (!std.mem.eql(u8, text, "nocase")) return error.MinimatchOptionUnsupported;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, value, entry.atom);
        if (present < 0) return v.js.capture(engine);
        if (present == 0) return error.MinimatchOptionsOutsidePiContract;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_GETSET != 0) return error.MinimatchOptionsOutsidePiContract;
    }
}

const Tests = struct {
    scope: *Scope,
    pattern: glob.Pattern,
    regexes: []const c.JSValue,
    pub fn @"test"(self: @This(), index: usize, bytes: []const u8) !bool {
        const specification = self.pattern[index].regex;
        if (specification.fast != .none) {
            const dot = bytes.len > 0 and bytes[0] == '.';
            switch (specification.fast) {
                .star => return bytes.len > 0 and !dot,
                .dot_star => return dot and !std.mem.eql(u8, bytes, ".") and !std.mem.eql(u8, bytes, ".."),
                .star_dot_star => return !dot and std.mem.indexOfScalar(u8, bytes, '.') != null,
                .suffix, .qmarks => {
                    if (dot or (specification.fast == .qmarks and glob.utf16Length(bytes) != specification.length)) return false;
                    if (!specification.nocase) return std.mem.endsWith(u8, bytes, specification.suffix);
                    var local: Scope = .{ .engine = self.scope.engine };
                    defer local.deinit();
                    const path = try local.invoke(try local.own(try text16(local.engine, bytes)), "toLowerCase", &.{});
                    const suffix = try local.invoke(try local.own(try text16(local.engine, specification.suffix)), "toLowerCase", &.{});
                    return local.truthy(try local.invoke(path, "endsWith", &.{suffix}));
                },
                .none => unreachable,
            }
        }
        if (specification.literal) |text| {
            if (c.JS_IsUndefined(self.regexes[index])) return std.mem.eql(u8, bytes, text);
        }
        // A fresh scope prevents a long globstar search from retaining every
        // transient VM string until the outer match completes.
        var local: Scope = .{ .engine = self.scope.engine };
        defer local.deinit();
        return local.truthy(try local.invoke(self.regexes[index], "test", &.{try local.own(try text16(local.engine, bytes))}));
    }
};

fn minimatch(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const input = if (args.len > 0) args[0] else c.pi_js_undefined();
    const pattern_value = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (!c.JS_IsString(pattern_value)) return v.js.typeError(engine, "invalid pattern");
    if (try v.length(&s, pattern_value) > 64 * 1024) return v.js.typeError(engine, "pattern is too long");
    const pattern = try bytes16(engine, pattern_value);
    defer engine.gpa.free(pattern);
    const options_value = if (args.len > 2) args[2] else c.pi_js_undefined();
    try checkOptions(engine, options_value);
    // Upstream comments and the empty pattern short-circuit before accessing
    // the test path. Keep these branches before string conversion.
    if (pattern.len > 0 and pattern[0] == '#') return c.JS_NewBool(engine.context, false);
    if (pattern.len == 0) {
        if (!c.JS_IsString(input)) return c.JS_NewBool(engine.context, false);
        return c.JS_NewBool(engine.context, try v.length(&s, input) == 0);
    }
    if (!c.JS_IsString(input)) return v.js.typeError(engine, "minimatch path must be a string");
    const nocase = if (v.nullish(options_value)) false else s.truthy(try s.get(options_value, "nocase"));
    const options: glob.Options = .{ .nocase = nocase, .windows = builtin.os.tag == .windows };
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const plan = try glob.compile(a, pattern, options);
    const original_path = try bytes16(engine, input);
    defer engine.gpa.free(original_path);
    const path = try a.dupe(u8, original_path);
    if (options.windows) {
        for (path) |*ch| { if (ch.* == '\\') ch.* = '/'; }
    }
    const path_parts = try glob.split(a, path, options.windows);
    for (plan.patterns) |parts| {
        var local: Scope = .{ .engine = engine };
        defer local.deinit();
        const regexes = try a.alloc(c.JSValue, parts.len);
        for (parts, regexes) |part, *slot| {
            slot.* = c.pi_js_undefined();
            if (part == .globstar) continue;
            const specification = part.regex;
            if (specification.fast != .none) continue;
            if (specification.literal) |text| {
                if (!specification.nocase) continue;
                // Minimatch keeps nonmagic strings literal when upper/lower
                // casing cannot change them. Use linked string primitives to
                // preserve Unicode behavior without a partial ASCII table.
                const value = try local.own(try text16(engine, text));
                const upper = try local.invoke(value, "toUpperCase", &.{});
                const lower = try local.invoke(value, "toLowerCase", &.{});
                if (local.equal(upper, lower)) continue;
            }
            const flags: []const u8 = if (specification.unicode) (if (specification.nocase) "iu" else "u") else (if (specification.nocase) "i" else "");
            var constructor_args = [_]c.JSValue{ try local.own(try text16(engine, specification.source)), try local.text(flags) };
            slot.* = try local.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, constructor_args.len, &constructor_args)));
        }
        const context: Tests = .{ .scope = &local, .pattern = parts, .regexes = regexes };
        if (try glob.match(context, parts, path_parts, options.windows)) return c.JS_NewBool(engine.context, !plan.negate);
    }
    return c.JS_NewBool(engine.context, plan.negate);
}
