//! Native schema evaluation for the durable tool workflow. Not yet installed as
//! a public module: coercion, cache and format integration qualify separately.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const references = @import("native_schema_refs.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Failure = struct { path: []const u8, message: []const u8, required_properties: []const []const u8 = &.{}, required_base: []const u8 = "" };
pub const Result = struct {
    arena: *std.heap.ArenaAllocator,
    valid: bool,
    failures: []const Failure,
    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        self.arena.deinit();
        gpa.destroy(self.arena);
    }
};
const Pair = struct { schema: c.JSValue, value: c.JSValue };
const Evaluated = struct {
    keys: std.StringHashMapUnmanaged(void) = .empty,
    items: std.AutoHashMapUnmanaged(usize, void) = .empty,
    fn merge(self: *Evaluated, a: std.mem.Allocator, other: Evaluated) !void {
        var keys = other.keys.keyIterator();
        while (keys.next()) |key| try self.keys.put(a, key.*, {});
        var items = other.items.keyIterator();
        while (items.next()) |index| try self.items.put(a, index.*, {});
    }
};
const BranchResult = struct { valid: bool, failures: []const Failure, evaluated: Evaluated };
pub fn evaluate(engine: *Engine, schema: c.JSValue, value: c.JSValue) !Result {
    const generation = engine.native_allocation_generation;
    return evaluateOwned(engine, schema, value) catch |err| return engine.nativeAllocationError(err, generation);
}
fn evaluateOwned(engine: *Engine, schema: c.JSValue, value: c.JSValue) !Result {
    const arena = try engine.gpa.create(std.heap.ArenaAllocator);
    errdefer engine.gpa.destroy(arena);
    arena.* = .init(engine.gpa);
    errdefer arena.deinit();
    var context: Context = .{ .engine = engine, .a = arena.allocator(), .root = schema };
    var evaluated: Evaluated = .{};
    const valid = try context.walk(schema, value, "", &evaluated);
    return .{ .arena = arena, .valid = valid, .failures = context.failures.items };
}
pub fn check(engine: *Engine, schema: c.JSValue, value: c.JSValue) !bool {
    return checkMode(engine, schema, value, false);
}
pub fn checkWithContext(engine: *Engine, definitions: c.JSValue, schema: c.JSValue, value: c.JSValue) !bool {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    var context: Context = .{ .engine = engine, .a = arena.allocator(), .root = schema, .check_only = true, .use_unevaluated = true, .refs = .{ .engine = engine, .a = arena.allocator(), .root = schema, .context = definitions } };
    var evaluated: Evaluated = .{};
    return context.walk(schema, value, "", &evaluated) catch |err| {
        if (err == error.CheckFailed) return false;
        return err;
    };
}
pub fn checkCompiled(engine: *Engine, schema: c.JSValue, value: c.JSValue) !bool {
    return checkMode(engine, schema, value, true);
}
fn checkMode(engine: *Engine, schema: c.JSValue, value: c.JSValue, compiled: bool) !bool {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const marker = if (compiled and c.JS_IsObject(schema)) try vm.get(engine, schema, "~nativeUnevaluated") else c.pi_js_undefined();
    defer engine.freeValue(marker);
    var context: Context = .{ .engine = engine, .a = arena.allocator(), .root = schema, .check_only = true, .compiled = compiled, .use_unevaluated = if (c.JS_IsBool(marker)) c.JS_ToBool(engine.context, marker) != 0 else true };
    var evaluated: Evaluated = .{};
    return context.walk(schema, value, "", &evaluated) catch |err| {
        if (err == error.CheckFailed) return false;
        return err;
    };
}
pub fn usesUnevaluated(engine: *Engine, schema: c.JSValue) !bool {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    var context: Context = .{ .engine = engine, .a = arena.allocator(), .root = schema };
    return context.findUnevaluated(schema);
}
const Context = struct {
    engine: *Engine,
    a: std.mem.Allocator,
    root: c.JSValue,
    failures: std.ArrayList(Failure) = .empty,
    active: std.ArrayList(Pair) = .empty,
    equal_active: std.ArrayList(Pair) = .empty,
    check_only: bool = false,
    compiled: bool = false,
    use_unevaluated: bool = false,
    refs: ?references.Stack = null,
    fn findUnevaluated(self: *Context, value: c.JSValue) anyerror!bool {
        if (!c.JS_IsObject(value) or c.JS_IsFunction(self.engine.context, value)) return false;
        for (self.active.items) |pair| if (c.JS_IsStrictEqual(self.engine.context, pair.schema, value)) {
            _ = try self.engine.checked(c.JS_ThrowRangeError(self.engine.context, "Maximum call stack size exceeded"));
            unreachable;
        };
        try self.active.append(self.a, .{ .schema = value, .value = c.pi_js_undefined() });
        defer _ = self.active.pop();
        if (!c.JS_IsArray(value)) {
            for ([_][:0]const u8{ "unevaluatedItems", "unevaluatedProperties" }) |key| {
                const rule = try self.get(value, key);
                defer self.engine.freeValue(rule);
                if (c.JS_IsBool(rule) or (c.JS_IsObject(rule) and !c.JS_IsArray(rule) and !c.JS_IsFunction(self.engine.context, rule))) return true;
            }
            for (try self.keys(value, false)) |key| {
                const child = try self.property(value, key);
                defer self.engine.freeValue(child);
                if (try self.findUnevaluated(child)) return true;
            }
        } else for (0..try vm.length(self.engine, value)) |index| {
            const child = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
            defer self.engine.freeValue(child);
            if (try self.findUnevaluated(child)) return true;
        }
        return false;
    }
    fn add(self: *Context, path: []const u8, message: []const u8) !void {
        if (self.check_only) return error.CheckFailed;
        if (self.failures.items.len >= 8) return;
        try self.failures.append(self.a, .{ .path = try self.a.dupe(u8, if (path.len == 0) "root" else path), .message = try self.a.dupe(u8, message) });
    }
    fn childPath(self: *Context, path: []const u8, key: []const u8) ![]const u8 {
        const joined = try std.fmt.allocPrint(self.a, "{s}{s}{s}", .{ path, if (path.len == 0) "" else ".", key });
        for (joined) |*byte| if (byte.* == '/') {
            byte.* = '.';
        };
        return joined;
    }
    fn textValue(self: *Context, value: c.JSValue) ![]const u8 {
        const temporary = try self.engine.toString(value);
        defer self.engine.gpa.free(temporary);
        return self.a.dupe(u8, temporary);
    }
    fn get(self: *Context, value: c.JSValue, name: [:0]const u8) !c.JSValue {
        if (self.compiled) return vm.get(self.engine, value, name);
        return @import("native_schema_guards.zig").read(self.engine, value, name);
    }
    fn number(self: *Context, value: c.JSValue) !?f64 {
        if (!c.JS_IsNumber(value)) return null;
        var output: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &output, value) < 0) return error.JavaScriptException;
        return if (std.math.isFinite(output)) output else null;
    }
    fn has(self: *Context, object: c.JSValue, key: []const u8) !bool {
        const atom = c.JS_NewAtomLen(self.engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        if (std.mem.eql(u8, key, "__proto__") or std.mem.eql(u8, key, "constructor") or std.mem.eql(u8, key, "prototype")) {
            var descriptor: c.JSPropertyDescriptor = undefined;
            const found = c.JS_GetOwnProperty(self.engine.context, &descriptor, object, atom);
            if (found < 0) return error.JavaScriptException;
            if (found > 0) {
                self.engine.freeValue(descriptor.value);
                self.engine.freeValue(descriptor.getter);
                self.engine.freeValue(descriptor.setter);
            }
            return found > 0;
        }
        const found = c.JS_HasProperty(self.engine.context, object, atom);
        if (found < 0) return error.JavaScriptException;
        return found > 0;
    }
    fn property(self: *Context, object: c.JSValue, key: []const u8) !c.JSValue {
        const atom = c.JS_NewAtomLen(self.engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        return self.engine.checked(c.JS_GetProperty(self.engine.context, object, atom));
    }
    fn keys(self: *Context, value: c.JSValue, enumerable: bool) ![]const []const u8 {
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(self.engine.context, &names, &count, value, c.JS_GPN_STRING_MASK | if (enumerable) c.JS_GPN_ENUM_ONLY else @as(c_int, 0)) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(self.engine.context, names, count);
        const result = try self.a.alloc([]const u8, count);
        for (result, 0..) |*name, index| {
            const string = try self.engine.checked(c.JS_AtomToString(self.engine.context, names[index].atom));
            defer self.engine.freeValue(string);
            name.* = try self.textValue(string);
        }
        return result;
    }
    fn matches(self: *Context, pattern: []const u8, text: []const u8, unicode: bool) !bool {
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const constructor = try self.get(global, "RegExp");
        defer self.engine.freeValue(constructor);
        const expression = try self.engine.checked(c.JS_NewStringLen(self.engine.context, pattern.ptr, pattern.len));
        defer self.engine.freeValue(expression);
        const flags = try self.engine.checked(c.JS_NewString(self.engine.context, if (unicode) "u" else ""));
        defer self.engine.freeValue(flags);
        var args = [_]c.JSValue{ expression, flags };
        const regexp = try self.engine.checked(c.JS_CallConstructor(self.engine.context, constructor, args.len, &args));
        defer self.engine.freeValue(regexp);
        const subject = try self.engine.checked(c.JS_NewStringLen(self.engine.context, text.ptr, text.len));
        defer self.engine.freeValue(subject);
        const result = try vm.invoke(self.engine, regexp, "test", &.{subject});
        defer self.engine.freeValue(result);
        return c.JS_ToBool(self.engine.context, result) != 0;
    }
    fn matchesProperty(self: *Context, schema: c.JSValue, pattern: []const u8, text: []const u8) !bool {
        const compiled = if (self.check_only) try vm.get(self.engine, schema, "~nativePatternProperties") else c.pi_js_undefined();
        defer self.engine.freeValue(compiled);
        if (!c.JS_IsUndefined(compiled)) {
            const regexp = try self.property(compiled, pattern);
            defer self.engine.freeValue(regexp);
            const input = try self.engine.checked(c.JS_NewStringLen(self.engine.context, text.ptr, text.len));
            defer self.engine.freeValue(input);
            const matched = try vm.invoke(self.engine, regexp, "test", &.{input});
            defer self.engine.freeValue(matched);
            return c.JS_ToBool(self.engine.context, matched) != 0;
        }
        return self.matches(pattern, text, true);
    }
    fn typeMatches(self: *Context, name: []const u8, value: c.JSValue) !bool {
        if (std.mem.eql(u8, name, "object")) return c.JS_IsObject(value) and !c.JS_IsFunction(self.engine.context, value) and !c.JS_IsArray(value);
        if (std.mem.eql(u8, name, "array")) return c.JS_IsArray(value);
        if (std.mem.eql(u8, name, "boolean")) return c.JS_IsBool(value);
        if (std.mem.eql(u8, name, "number")) return try self.number(value) != null;
        if (std.mem.eql(u8, name, "integer")) {
            const n = try self.number(value) orelse return false;
            return n == @trunc(n);
        }
        if (std.mem.eql(u8, name, "null")) return c.JS_IsNull(value);
        if (std.mem.eql(u8, name, "string")) return c.JS_IsString(value);
        if (std.mem.eql(u8, name, "undefined") or std.mem.eql(u8, name, "void")) return c.JS_IsUndefined(value);
        if (std.mem.eql(u8, name, "function") or std.mem.eql(u8, name, "constructor")) return c.JS_IsFunction(self.engine.context, value);
        if (std.mem.eql(u8, name, "symbol")) return c.JS_IsSymbol(value);
        if (std.mem.eql(u8, name, "bigint")) return c.JS_IsBigInt(value);
        return true;
    }
    fn branch(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !BranchResult {
        var child: Context = .{ .engine = self.engine, .a = self.a, .root = self.root, .active = self.active, .check_only = self.check_only, .compiled = self.compiled, .use_unevaluated = self.use_unevaluated, .refs = self.refs };
        var evaluated: Evaluated = .{};
        const valid = child.walk(schema, value, path, &evaluated) catch |err| blk: {
            if (err == error.CheckFailed) break :blk false;
            return err;
        };
        return .{ .valid = valid, .failures = child.failures.items, .evaluated = evaluated };
    }
    fn predicateBranch(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !BranchResult {
        var child = self.*;
        child.check_only = true;
        return child.branch(schema, value, path);
    }
    fn mergeErrors(self: *Context, failures: []const Failure) !void {
        if (self.check_only) return error.CheckFailed;
        for (failures) |failure| {
            const before = self.failures.items.len;
            try self.add(failure.path, failure.message);
            if (self.failures.items.len > before) {
                self.failures.items[before].required_properties = failure.required_properties;
                self.failures.items[before].required_base = failure.required_base;
            }
        }
    }
    fn equal(self: *Context, left: c.JSValue, right: c.JSValue) anyerror!bool {
        if (!c.JS_IsObject(left) or c.JS_IsFunction(self.engine.context, left)) return c.JS_IsStrictEqual(self.engine.context, left, right);
        if (!c.JS_IsObject(right) or c.JS_IsFunction(self.engine.context, right)) return false;
        for (self.equal_active.items) |pair| if (c.JS_IsStrictEqual(self.engine.context, pair.schema, left) and c.JS_IsStrictEqual(self.engine.context, pair.value, right)) {
            _ = try self.engine.checked(c.JS_ThrowRangeError(self.engine.context, "Maximum call stack size exceeded"));
            unreachable;
        };
        try self.equal_active.append(self.a, .{ .schema = left, .value = right });
        defer _ = self.equal_active.pop();
        if (c.JS_IsArray(left)) {
            if (!c.JS_IsArray(right) or try vm.length(self.engine, left) != try vm.length(self.engine, right)) return false;
            for (0..try vm.length(self.engine, left)) |index| {
                const atom = c.JS_NewAtomUInt32(self.engine.context, @intCast(index));
                defer c.JS_FreeAtom(self.engine.context, atom);
                const present = c.JS_HasProperty(self.engine.context, left, atom);
                if (present < 0) return error.JavaScriptException;
                if (present == 0) continue;
                const l = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, left, @intCast(index)));
                defer self.engine.freeValue(l);
                const r = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, right, @intCast(index)));
                defer self.engine.freeValue(r);
                if (!try self.equal(l, r)) return false;
            }
            return true;
        }
        const lhs = try self.keys(left, false);
        const rhs = try self.keys(right, false);
        if (lhs.len != rhs.len) return false;
        for (lhs) |key| {
            const l = try self.property(left, key);
            defer self.engine.freeValue(l);
            const r = try self.property(right, key);
            defer self.engine.freeValue(r);
            if (!try self.equal(l, r)) return false;
        }
        return true;
    }
    fn resolve(self: *Context, reference: []const u8) !c.JSValue {
        if (reference.len == 0 or std.mem.eql(u8, reference, "#")) return c.JS_DupValue(self.engine.context, self.root);
        if (!std.mem.startsWith(u8, reference, "#/")) return c.pi_js_bool(self.engine.context, 0);
        var result = c.JS_DupValue(self.engine.context, self.root);
        errdefer self.engine.freeValue(result);
        var segments = std.mem.splitScalar(u8, reference[2..], '/');
        while (segments.next()) |segment| {
            var decoded: std.ArrayList(u8) = .empty;
            var index: usize = 0;
            while (index < segment.len) : (index += 1) {
                if (segment[index] == '~' and index + 1 < segment.len) {
                    index += 1;
                    try decoded.append(self.a, if (segment[index] == '1') '/' else if (segment[index] == '0') '~' else segment[index]);
                } else try decoded.append(self.a, segment[index]);
            }
            if (!c.JS_IsObject(result)) {
                self.engine.freeValue(result);
                return c.pi_js_bool(self.engine.context, 0);
            }
            const next = try self.property(result, decoded.items);
            self.engine.freeValue(result);
            result = next;
        }
        if (c.JS_IsUndefined(result)) {
            self.engine.freeValue(result);
            return c.pi_js_bool(self.engine.context, 0);
        }
        return result;
    }
    fn walk(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated) anyerror!bool {
        try @import("native_schema_guards.zig").assertRoot(self.engine, schema);
        if (self.failures.items.len >= 8) return false;
        for (self.active.items) |pair| if (c.JS_IsStrictEqual(self.engine.context, pair.schema, schema) and c.JS_IsStrictEqual(self.engine.context, pair.value, value)) {
            _ = try self.engine.checked(c.JS_ThrowRangeError(self.engine.context, "Maximum call stack size exceeded"));
            unreachable;
        };
        try self.active.append(self.a, .{ .schema = schema, .value = value });
        defer _ = self.active.pop();
        var mark: ?references.Mark = null;
        if (!self.compiled) {
            if (self.refs == null) self.refs = .{ .engine = self.engine, .a = self.a, .root = self.root };
            mark = try self.refs.?.push(schema);
        }
        defer if (mark) |saved| self.refs.?.pop(saved);
        const before = self.failures.items.len;
        if (c.JS_IsBool(schema)) {
            if (c.JS_ToBool(self.engine.context, schema) == 0) try self.add(path, "schema is false");
            return before == self.failures.items.len;
        }
        if (!c.JS_IsObject(schema)) return true;
        const schema_type = try self.get(schema, "type");
        defer self.engine.freeValue(schema_type);
        if (c.JS_IsString(schema_type)) {
            const label = try self.textValue(schema_type);
            if (!try self.typeMatches(label, value)) try self.add(path, try std.fmt.allocPrint(self.a, "must be {s}", .{label}));
        } else if (c.JS_IsArray(schema_type)) {
            var matched = false;
            var names: std.ArrayList([]const u8) = .empty;
            for (0..try vm.length(self.engine, schema_type)) |index| {
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, schema_type, @intCast(index)));
                defer self.engine.freeValue(item);
                const label = try self.textValue(item);
                try names.append(self.a, label);
                matched = matched or try self.typeMatches(label, value);
            }
            if (!matched) try self.add(path, try std.fmt.allocPrint(self.a, "must be either {s}", .{try std.mem.join(self.a, " or ", names.items)}));
        }
        if (c.JS_IsObject(value) and !c.JS_IsFunction(self.engine.context, value) and !c.JS_IsArray(value)) try self.objectRules(schema, value, path, evaluated);
        if (c.JS_IsArray(value)) try self.arrayRules(schema, value, path, evaluated);
        if (c.JS_IsString(value)) try self.stringRules(schema, value, path);
        if (c.JS_IsBigInt(value) or (try self.number(value)) != null) try self.numberRules(schema, value, path);
        const resolved = if (self.check_only) try self.get(schema, "~nativeReferences") else c.pi_js_undefined();
        defer self.engine.freeValue(resolved);
        if (c.JS_IsArray(resolved)) {
            for (0..try vm.length(self.engine, resolved)) |index| {
                const target = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, resolved, @intCast(index)));
                defer self.engine.freeValue(target);
                const result = try self.branch(target, value, path);
                if (result.valid) try evaluated.merge(self.a, result.evaluated) else try self.mergeErrors(result.failures);
            }
        } else for ([_][:0]const u8{ "$ref", "$recursiveRef", "$dynamicRef" }) |keyword| {
            const reference = try self.get(schema, keyword);
            defer self.engine.freeValue(reference);
            if (c.JS_IsString(reference)) {
                const resolution = try self.refs.?.resolve(keyword, try self.textValue(reference));
                defer resolution.deinit(self.engine);
                self.refs.?.entry = resolution;
                defer self.refs.?.entry = null;
                const branch_result = try self.branch(resolution.schema, value, path);
                if (branch_result.valid) try evaluated.merge(self.a, branch_result.evaluated) else try self.mergeErrors(branch_result.failures);
            }
        }
        const constant = try self.get(schema, "const");
        defer self.engine.freeValue(constant);
        if (try self.has(schema, "const") and !try self.equal(value, constant)) try self.add(path, "must be equal to constant");
        const enumeration = try self.get(schema, "enum");
        defer self.engine.freeValue(enumeration);
        if (c.JS_IsArray(enumeration)) {
            var matched = false;
            for (0..try vm.length(self.engine, enumeration)) |index| {
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, enumeration, @intCast(index)));
                defer self.engine.freeValue(item);
                matched = matched or try self.equal(value, item);
            }
            if (!matched) try self.add(path, "must be equal to one of the allowed values");
        }
        try self.logicalRules(schema, value, path, evaluated);
        try self.unevaluatedRules(schema, value, path, evaluated);
        if (before == self.failures.items.len) try self.refinements(schema, value, path);
        return before == self.failures.items.len;
    }
    fn refinements(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !void {
        const refinements_value = try self.get(schema, "~refine");
        defer self.engine.freeValue(refinements_value);
        if (!c.JS_IsArray(refinements_value)) return;
        const length = try vm.length(self.engine, refinements_value);
        // TypeBox's keyword guard requires all refinement entries to have
        // callable check/error properties before applying any refinement.
        if (!self.compiled) for (0..length) |index| {
            const entry = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, refinements_value, @intCast(index)));
            defer self.engine.freeValue(entry);
            if (!c.JS_IsObject(entry)) return;
            const checker = try self.get(entry, "check");
            defer self.engine.freeValue(checker);
            const formatter = try self.get(entry, "error");
            defer self.engine.freeValue(formatter);
            if (!c.JS_IsFunction(self.engine.context, checker) or !c.JS_IsFunction(self.engine.context, formatter)) return;
        };
        for (0..length) |index| {
            const entry = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, refinements_value, @intCast(index)));
            defer self.engine.freeValue(entry);
            const accepted = try vm.invoke(self.engine, entry, "check", &.{value});
            defer self.engine.freeValue(accepted);
            if (c.JS_ToBool(self.engine.context, accepted) != 0) continue;
            if (self.check_only) return error.CheckFailed;
            const message = try vm.invoke(self.engine, entry, "error", &.{value});
            defer self.engine.freeValue(message);
            try self.add(path, try self.textValue(message));
        }
    }
    fn objectRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated) anyerror!void {
        const required = try self.get(schema, "required");
        defer self.engine.freeValue(required);
        var missing: std.ArrayList([]const u8) = .empty;
        var required_names: std.StringHashMapUnmanaged(void) = .empty;
        if (c.JS_IsArray(required)) for (0..try vm.length(self.engine, required)) |index| {
            const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, required, @intCast(index)));
            defer self.engine.freeValue(item);
            const key = try self.textValue(item);
            try required_names.put(self.a, key, {});
            if (!try self.has(value, key)) try missing.append(self.a, key);
        };
        if (missing.items.len != 0) {
            const before = self.failures.items.len;
            try self.add(if (missing.items[0].len == 0) path else try std.fmt.allocPrint(self.a, "{s}{s}{s}", .{ path, if (path.len == 0) "" else ".", missing.items[0] }), try std.fmt.allocPrint(self.a, "must have required properties {s}", .{try std.mem.join(self.a, ", ", missing.items)}));
            if (self.failures.items.len > before) {
                self.failures.items[before].required_properties = missing.items;
                self.failures.items[before].required_base = path;
            }
        }
        const properties = try self.get(schema, "properties");
        defer self.engine.freeValue(properties);
        const patterns = try self.get(schema, "patternProperties");
        defer self.engine.freeValue(patterns);
        const actual = try self.keys(value, false);
        const additional = try self.get(schema, "additionalProperties");
        defer self.engine.freeValue(additional);
        if (!c.JS_IsUndefined(additional)) {
            var valid = true;
            for (actual) |key| {
                var covered = c.JS_IsObject(properties) and try self.has(properties, key);
                if (c.JS_IsObject(patterns)) for (try self.keys(patterns, false)) |pattern| {
                    covered = covered or try self.matchesProperty(schema, pattern, key);
                };
                if (covered) continue;
                const child = try self.property(value, key);
                defer self.engine.freeValue(child);
                const result = try self.branch(additional, child, try self.childPath(path, key));
                if (result.valid) try evaluated.keys.put(self.a, key, {}) else {
                    valid = false;
                    try self.mergeErrors(result.failures);
                }
            }
            if (!valid) try self.add(path, "must not have additional properties");
        }
        for ([_][:0]const u8{ "dependencies", "dependentRequired", "dependentSchemas" }) |keyword| {
            const dependencies = try self.get(schema, keyword);
            defer self.engine.freeValue(dependencies);
            if (!c.JS_IsObject(dependencies) or c.JS_IsArray(dependencies)) continue;
            for (try self.keys(dependencies, false)) |key| {
                if (!try self.has(value, key)) continue;
                const dependency = try self.property(dependencies, key);
                defer self.engine.freeValue(dependency);
                if (c.JS_IsArray(dependency)) {
                    var names: std.ArrayList([]const u8) = .empty;
                    var absent: usize = 0;
                    for (0..try vm.length(self.engine, dependency)) |index| {
                        const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, dependency, @intCast(index)));
                        defer self.engine.freeValue(item);
                        const name = try self.textValue(item);
                        try names.append(self.a, name);
                        if (!try self.has(value, name)) absent += 1;
                    }
                    for (0..absent) |_| try self.add(path, try std.fmt.allocPrint(self.a, "must have properties {s} when property {s} is present", .{ try std.mem.join(self.a, ", ", names.items), key }));
                } else {
                    const result = try self.branch(dependency, value, path);
                    if (result.valid) try evaluated.merge(self.a, result.evaluated) else try self.mergeErrors(result.failures);
                }
            }
        }
        if (c.JS_IsObject(patterns)) for (try self.keys(patterns, false)) |pattern| {
            const rule = try self.property(patterns, pattern);
            defer self.engine.freeValue(rule);
            for (actual) |key| if (try self.matchesProperty(schema, pattern, key)) {
                const child = try self.property(value, key);
                defer self.engine.freeValue(child);
                const result = try self.branch(rule, child, try self.childPath(path, key));
                if (result.valid) try evaluated.keys.put(self.a, key, {}) else try self.mergeErrors(result.failures);
            };
        };
        if (c.JS_IsObject(properties)) for (try self.keys(properties, false)) |key| {
            if (!try self.has(value, key)) continue;
            const child = try self.property(value, key);
            defer self.engine.freeValue(child);
            if (c.JS_IsUndefined(child) and !required_names.contains(key)) continue;
            const rule = try self.property(properties, key);
            defer self.engine.freeValue(rule);
            const result = try self.branch(rule, child, try self.childPath(path, key));
            if (result.valid) try evaluated.keys.put(self.a, key, {}) else try self.mergeErrors(result.failures);
        };
        const property_names = try self.get(schema, "propertyNames");
        defer self.engine.freeValue(property_names);
        if (!c.JS_IsUndefined(property_names)) {
            var invalid: std.ArrayList([]const u8) = .empty;
            for (actual) |key| {
                const string = try self.engine.checked(c.JS_NewStringLen(self.engine.context, key.ptr, key.len));
                defer self.engine.freeValue(string);
                const result = try self.branch(property_names, string, try self.childPath(path, key));
                if (!result.valid) {
                    try invalid.append(self.a, key);
                    try self.mergeErrors(result.failures);
                }
            }
            if (invalid.items.len != 0) try self.add(path, try std.fmt.allocPrint(self.a, "property names {s} are invalid", .{try std.mem.join(self.a, ", ", invalid.items)}));
        }
        inline for (.{ "minProperties", "maxProperties" }, .{ "must not have fewer than", "must not have more than" }) |keyword, phrase| {
            const limit_value = try self.get(schema, keyword);
            defer self.engine.freeValue(limit_value);
            if (try self.number(limit_value)) |limit| if (if (comptime std.mem.eql(u8, keyword, "minProperties")) @as(f64, @floatFromInt(actual.len)) < limit else @as(f64, @floatFromInt(actual.len)) > limit) try self.add(path, try std.fmt.allocPrint(self.a, "{s} {s} properties", .{ phrase, try self.textValue(limit_value) }));
        }
    }
    fn numberRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !void {
        inline for (.{ "exclusiveMaximum", "exclusiveMinimum", "maximum", "minimum", "multipleOf" }, .{ "<", ">", "<=", ">=", "multiple of" }, 0..) |keyword, comparison, operation| {
            const limit_value = try self.get(schema, keyword);
            defer self.engine.freeValue(limit_value);
            if (c.JS_IsBigInt(limit_value) or (try self.number(limit_value)) != null) {
                const valid = if (operation == 4) try @import("native_schema_numeric.zig").multiple(self.engine, value, limit_value) else blk: {
                    const order = try @import("native_schema_numeric.zig").compare(self.engine, value, limit_value);
                    break :blk switch (operation) {
                        0 => order == .lt,
                        1 => order == .gt,
                        2 => order != .gt,
                        3 => order != .lt,
                        else => unreachable,
                    };
                };
                if (!valid) try self.add(path, try std.fmt.allocPrint(self.a, "must be {s} {s}", .{ comparison, try self.textValue(limit_value) }));
            }
        }
    }
    fn arrayItem(self: *Context, rule: c.JSValue, value: c.JSValue, index: usize, path: []const u8, evaluated: *Evaluated) !void {
        if (!try self.arrayPresent(value, index)) return;
        const child = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
        defer self.engine.freeValue(child);
        const result = try self.branch(rule, child, try self.childPath(path, try std.fmt.allocPrint(self.a, "{d}", .{index})));
        if (result.valid) try evaluated.items.put(self.a, index, {}) else try self.mergeErrors(result.failures);
    }
    fn arrayPresent(self: *Context, value: c.JSValue, index: usize) !bool {
        const atom = c.JS_NewAtomUInt32(self.engine.context, @intCast(index));
        defer c.JS_FreeAtom(self.engine.context, atom);
        const present = c.JS_HasProperty(self.engine.context, value, atom);
        if (present < 0) return error.JavaScriptException;
        return present != 0;
    }
    fn countContains(self: *Context, rule: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated, add_indices: bool, first_only: bool) !usize {
        var count: usize = 0;
        for (0..try vm.length(self.engine, value)) |index| {
            if (!try self.arrayPresent(value, index)) continue;
            const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
            defer self.engine.freeValue(item);
            const result = try self.predicateBranch(rule, item, path);
            if (result.valid) {
                count += 1;
                if (add_indices) try evaluated.items.put(self.a, index, {});
                if (first_only) break;
            }
        }
        return count;
    }
    fn arrayRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated) !void {
        const length = try vm.length(self.engine, value);
        const items = try self.get(schema, "items");
        defer self.engine.freeValue(items);
        const prefix = try self.get(schema, "prefixItems");
        defer self.engine.freeValue(prefix);
        const additional = try self.get(schema, "additionalItems");
        defer self.engine.freeValue(additional);
        if (c.JS_IsArray(items) and !c.JS_IsUndefined(additional)) for (@min(length, try vm.length(self.engine, items))..length) |index| {
            const before = self.failures.items.len;
            try self.arrayItem(additional, value, index, path, evaluated);
            if (self.failures.items.len != before) break;
        };
        const contains = try self.get(schema, "contains");
        defer self.engine.freeValue(contains);
        if (!c.JS_IsUndefined(contains)) {
            const minimum_contains = try self.get(schema, "minContains");
            defer self.engine.freeValue(minimum_contains);
            const minimum_limit = try self.number(minimum_contains);
            if (minimum_limit == null or minimum_limit.? != 0) {
                const contained = try self.countContains(contains, value, path, evaluated, !self.compiled or self.use_unevaluated, self.compiled and !self.use_unevaluated);
                if (contained == 0) try self.add(path, "must contain at least 1 valid item");
            }
        }
        if (c.JS_IsArray(items)) {
            for (0..@min(length, try vm.length(self.engine, items))) |index| {
                const rule = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, items, @intCast(index)));
                defer self.engine.freeValue(rule);
                try self.arrayItem(rule, value, index, path, evaluated);
            }
        } else if (!c.JS_IsUndefined(items)) {
            const start = if (c.JS_IsArray(prefix)) @min(length, try vm.length(self.engine, prefix)) else 0;
            for (start..length) |index| try self.arrayItem(items, value, index, path, evaluated);
        }
        const maximum_contains = try self.get(schema, "maxContains");
        defer self.engine.freeValue(maximum_contains);
        if (!c.JS_IsUndefined(contains)) if (try self.number(maximum_contains)) |limit| {
            const contained = try self.countContains(contains, value, path, evaluated, false, false);
            if (@as(f64, @floatFromInt(contained)) > limit) try self.add(path, "must contain at least 1 valid item");
        };
        const maximum = try self.get(schema, "maxItems");
        defer self.engine.freeValue(maximum);
        if (try self.number(maximum)) |limit| if (@as(f64, @floatFromInt(length)) > limit) try self.add(path, try std.fmt.allocPrint(self.a, "must not have more than {s} items", .{try self.textValue(maximum)}));
        const minimum_contains = try self.get(schema, "minContains");
        defer self.engine.freeValue(minimum_contains);
        if (!c.JS_IsUndefined(contains)) if (try self.number(minimum_contains)) |limit| {
            const contained = try self.countContains(contains, value, path, evaluated, !self.compiled or self.use_unevaluated, false);
            if (@as(f64, @floatFromInt(contained)) < limit) try self.add(path, "must contain at least 1 valid item");
        };
        const minimum = try self.get(schema, "minItems");
        defer self.engine.freeValue(minimum);
        if (try self.number(minimum)) |limit| if (@as(f64, @floatFromInt(length)) < limit) try self.add(path, try std.fmt.allocPrint(self.a, "must not have fewer than {s} items", .{try self.textValue(minimum)}));
        if (c.JS_IsArray(prefix)) for (0..@min(length, try vm.length(self.engine, prefix))) |index| {
            const rule = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, prefix, @intCast(index)));
            defer self.engine.freeValue(rule);
            try self.arrayItem(rule, value, index, path, evaluated);
        };
        const unique = try self.get(schema, "uniqueItems");
        defer self.engine.freeValue(unique);
        if (c.JS_IsBool(unique) and c.JS_ToBool(self.engine.context, unique) != 0) {
            var duplicate = false;
            if (self.check_only) {
                const callback = try @import("native_schema_hashing.zig").createFunction(self.engine);
                defer self.engine.freeValue(callback);
                const mapped = try vm.invoke(self.engine, value, "map", &.{callback});
                defer self.engine.freeValue(mapped);
                const global = c.JS_GetGlobalObject(self.engine.context);
                defer self.engine.freeValue(global);
                const set = try self.get(global, "Set");
                defer self.engine.freeValue(set);
                var args = [_]c.JSValue{mapped};
                const unique_values = try self.engine.checked(c.JS_CallConstructor(self.engine.context, set, 1, &args));
                defer self.engine.freeValue(unique_values);
                const size = try self.get(unique_values, "size");
                defer self.engine.freeValue(size);
                duplicate = (try self.number(size) orelse 0) != @as(f64, @floatFromInt(length));
            } else {
                var hashes: std.AutoHashMapUnmanaged(u64, void) = .empty;
                for (0..length) |index| {
                    const atom = c.JS_NewAtomUInt32(self.engine.context, @intCast(index));
                    defer c.JS_FreeAtom(self.engine.context, atom);
                    const present = c.JS_HasProperty(self.engine.context, value, atom);
                    if (present < 0) return error.JavaScriptException;
                    if (present == 0) continue;
                    const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
                    defer self.engine.freeValue(item);
                    const code = try @import("native_schema_hashing.zig").hash(self.engine, item);
                    if (hashes.contains(code)) duplicate = true;
                    try hashes.put(self.a, code, {});
                }
            }
            if (duplicate) try self.add(path, "must not have duplicate items");
        }
    }
    fn stringRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !void {
        const text = try self.textValue(value);
        var points: std.ArrayList(u21) = .empty;
        var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |point| try points.append(self.a, point);
        var characters: usize = 0;
        var index: usize = 0;
        while (index < points.items.len) {
            const first = points.items[index];
            index += 1;
            while (index < points.items.len and modifier(points.items[index])) : (index += 1) {}
            while (index + 1 < points.items.len and points.items[index] == 0x200d) {
                index += 2;
                while (index < points.items.len and modifier(points.items[index])) : (index += 1) {}
            }
            if (first >= 0x1f1e6 and first <= 0x1f1ff and index < points.items.len and points.items[index] >= 0x1f1e6 and points.items[index] <= 0x1f1ff) index += 1;
            characters += 1;
        }
        inline for (.{ "maxLength", "minLength" }, .{ "more", "fewer" }) |keyword, phrase| {
            const size = try self.get(schema, keyword);
            defer self.engine.freeValue(size);
            if (try self.number(size)) |limit| if (if (comptime std.mem.eql(u8, keyword, "maxLength")) @as(f64, @floatFromInt(characters)) > limit else @as(f64, @floatFromInt(characters)) < limit) try self.add(path, try std.fmt.allocPrint(self.a, "must not have {s} than {s} characters", .{ phrase, try self.textValue(size) }));
        }
        const format = try self.get(schema, "format");
        defer self.engine.freeValue(format);
        if (c.JS_IsString(format)) {
            try @import("native_schema_formats.zig").install(self.engine);
            const exports = self.engine.native_module_values.get("typebox/format").?;
            const valid = try vm.invoke(self.engine, exports, "Test", &.{ format, value });
            defer self.engine.freeValue(valid);
            if (c.JS_ToBool(self.engine.context, valid) == 0) try self.add(path, try std.fmt.allocPrint(self.a, "must match format \"{s}\"", .{try self.textValue(format)}));
        }
        const pattern = try self.get(schema, "pattern");
        defer self.engine.freeValue(pattern);
        const cached = if (self.check_only) try vm.get(self.engine, schema, "~nativePattern") else c.pi_js_undefined();
        defer self.engine.freeValue(cached);
        if (!c.JS_IsUndefined(cached) or !c.JS_IsUndefined(pattern)) {
            const regexp = if (!c.JS_IsUndefined(cached)) c.JS_DupValue(self.engine.context, cached) else try @import("native_schema_guards.zig").compilePattern(self.engine, pattern);
            defer self.engine.freeValue(regexp);
            const matched = try vm.invoke(self.engine, regexp, "test", &.{value});
            defer self.engine.freeValue(matched);
            if (c.JS_ToBool(self.engine.context, matched) == 0) try self.add(path, try std.fmt.allocPrint(self.a, "must match pattern \"{s}\"", .{try self.textValue(pattern)}));
        }
    }
    fn modifier(point: u21) bool {
        return (point >= 0x0300 and point <= 0x036f) or (point >= 0x1ab0 and point <= 0x1aff) or (point >= 0x1dc0 and point <= 0x1dff) or (point >= 0xfe20 and point <= 0xfe2f) or (point >= 0xfe00 and point <= 0xfe0f);
    }
    fn logicalRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated) !void {
        const condition = try self.get(schema, "if");
        defer self.engine.freeValue(condition);
        if (!c.JS_IsUndefined(condition)) {
            const predicate = try self.branch(condition, value, path);
            const keyword: [:0]const u8 = if (predicate.valid) "then" else "else";
            const rule = try self.get(schema, keyword);
            defer self.engine.freeValue(rule);
            if (c.JS_IsUndefined(rule)) {
                if (predicate.valid) try evaluated.merge(self.a, predicate.evaluated);
            } else {
                const result = try self.branch(rule, value, path);
                if (result.valid) {
                    if (predicate.valid) try evaluated.merge(self.a, predicate.evaluated);
                    try evaluated.merge(self.a, result.evaluated);
                } else {
                    if (!predicate.valid) try self.mergeErrors(result.failures);
                    try self.add(path, try std.fmt.allocPrint(self.a, "must match \"{s}\" schema", .{keyword}));
                }
            }
        }
        const negative = try self.get(schema, "not");
        defer self.engine.freeValue(negative);
        if (!c.JS_IsUndefined(negative) and (try self.predicateBranch(negative, value, path)).valid) try self.add(path, "must not be valid");
        inline for (.{ "allOf", "anyOf", "oneOf" }, 0..) |keyword, operation| {
            const rules = try self.get(schema, keyword);
            defer self.engine.freeValue(rules);
            if (c.JS_IsArray(rules)) {
                var passed_count: usize = 0;
                var collected: std.ArrayList(Failure) = .empty;
                var passed: Evaluated = .{};
                const count = try vm.length(self.engine, rules);
                for (0..count) |index| {
                    const rule = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, rules, @intCast(index)));
                    defer self.engine.freeValue(rule);
                    const result = try self.branch(rule, value, path);
                    if (result.valid) {
                        passed_count += 1;
                        try passed.merge(self.a, result.evaluated);
                        if (self.check_only and self.compiled and !self.use_unevaluated and operation == 1) break;
                    } else try collected.appendSlice(self.a, result.failures);
                    if (self.check_only and self.compiled and operation == 0 and !result.valid) return error.CheckFailed;
                }
                const valid = switch (operation) {
                    0 => passed_count == count,
                    1 => passed_count > 0,
                    else => passed_count == 1,
                };
                if (valid) try evaluated.merge(self.a, passed) else {
                    if (operation == 0 or passed_count == 0) try self.mergeErrors(collected.items);
                    if (operation != 0) try self.add(path, if (operation == 1) "must match a schema in anyOf" else "must match exactly one schema in oneOf");
                }
            }
        }
    }
    fn unevaluatedRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated) !void {
        const array_rule = try self.get(schema, "unevaluatedItems");
        defer self.engine.freeValue(array_rule);
        if (c.JS_IsArray(value) and !c.JS_IsUndefined(array_rule)) {
            var valid = true;
            for (0..try vm.length(self.engine, value)) |index| {
                if (evaluated.items.contains(index)) continue;
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
                defer self.engine.freeValue(item);
                if (!(try self.branch(array_rule, item, path)).valid) {
                    valid = false;
                    break;
                }
            }
            if (!valid) try self.add(path, "must not have unevaluated items");
        }
        const object_rule = try self.get(schema, "unevaluatedProperties");
        defer self.engine.freeValue(object_rule);
        if (c.JS_IsObject(value) and !c.JS_IsArray(value) and !c.JS_IsUndefined(object_rule)) {
            var valid = true;
            for (try self.keys(value, false)) |key| {
                if (evaluated.keys.contains(key)) continue;
                const item = try self.property(value, key);
                defer self.engine.freeValue(item);
                if (!(try self.branch(object_rule, item, path)).valid) {
                    valid = false;
                    break;
                }
            }
            if (!valid) try self.add(path, "must not have unevaluated properties");
        }
    }
};

fn evaluatedCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return evaluatedOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Native validation: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn evaluatedOwned(engine: *Engine, schema: c.JSValue, value: c.JSValue) !c.JSValue {
    const valid = try check(engine, schema, value);
    var result: ?Result = null;
    defer if (result) |*errors| errors.deinit(engine.gpa);
    if (!try check(engine, schema, value)) result = try evaluate(engine, schema, value);
    const output = try vm.object(engine);
    errdefer engine.freeValue(output);
    try vm.put(engine, output, "valid", c.pi_js_bool(engine.context, @intFromBool(valid)));
    const failures = try vm.array(engine);
    defer engine.freeValue(failures);
    for (if (result) |errors| errors.failures else &.{}, 0..) |failure, index| {
        const entry = try vm.object(engine);
        var consumed = false;
        errdefer if (!consumed) engine.freeValue(entry);
        try vm.put(engine, entry, "path", try engine.checked(c.JS_NewStringLen(engine.context, failure.path.ptr, failure.path.len)));
        try vm.put(engine, entry, "message", try engine.checked(c.JS_NewStringLen(engine.context, failure.message.ptr, failure.message.len)));
        consumed = true;
        if (c.JS_SetPropertyUint32(engine.context, failures, @intCast(index), entry) < 0) return error.JavaScriptException;
    }
    try vm.put(engine, output, "failures", c.JS_DupValue(engine.context, failures));
    return output;
}
test "native durable VM private schema evaluator preserves original ordered errors refs logical branches Unicode and evaluated keys" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "nativeEvaluate", try engine.checked(c.JS_NewCFunction(engine.context, evaluatedCallback, "nativeEvaluate", 2)));
    errdefer std.debug.print("Schema evaluator VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const cases=[['required-additional',{type:'object',properties:{n:{type:'number'},s:{type:'string'}},required:['n','s'],additionalProperties:false},{extra:1}],['bounds',{type:'object',properties:{n:{type:'number',minimum:10,multipleOf:3},s:{type:'string',minLength:4,pattern:'^x'},a:{type:'array',minItems:2,uniqueItems:true,items:{type:'integer'}}},required:['n','s','a']},{n:5,s:'a',a:[1,1]}],['anyOf',{anyOf:[{type:'string',minLength:2},{type:'number',minimum:10}]},false],['oneOf-many',{oneOf:[{type:'number'},{type:'integer'}]},3],['ref',{$defs:{n:{type:'number'}},properties:{value:{$ref:'#/$defs/n'}},required:['value']},{value:'2'}],['ref-missing',{$ref:'#/$defs/missing'},{}],['conditional',{if:{required:['enabled']},then:{required:['value']}},{enabled:true}],['dependent',{dependentRequired:{a:['b','c']}},{a:1}],['contains',{contains:{type:'number',minimum:3},minContains:2,maxContains:3},[1,2]],['unevaluated',{allOf:[{properties:{a:{type:'number'}}}],unevaluatedProperties:false},{a:1,b:2}],['prefix',{prefixItems:[{type:'string'},{type:'integer'}],items:false},['a',2,3]],['unicode',{type:'string',minLength:2,pattern:'^\\p{L}+$'},'Ω'],['valid',{type:'object',properties:{n:{type:'number'}},required:['n']},{n:3}]];
        \\const output=cases.map(([name,schema,value])=>({name,...nativeEvaluate(schema,value)}));globalThis.result=JSON.stringify(output);
    , "native-tool-schema-evaluator-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-tool-schema-evaluator-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("[{\"name\":\"required-additional\",\"valid\":false,\"failures\":[{\"path\":\"n\",\"message\":\"must have required properties n, s\"},{\"path\":\"extra\",\"message\":\"schema is false\"},{\"path\":\"root\",\"message\":\"must not have additional properties\"}]},{\"name\":\"bounds\",\"valid\":false,\"failures\":[{\"path\":\"n\",\"message\":\"must be >= 10\"},{\"path\":\"n\",\"message\":\"must be multiple of 3\"},{\"path\":\"s\",\"message\":\"must not have fewer than 4 characters\"},{\"path\":\"s\",\"message\":\"must match pattern \\\"^x\\\"\"},{\"path\":\"a\",\"message\":\"must not have duplicate items\"}]},{\"name\":\"anyOf\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must be string\"},{\"path\":\"root\",\"message\":\"must be number\"},{\"path\":\"root\",\"message\":\"must match a schema in anyOf\"}]},{\"name\":\"oneOf-many\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must match exactly one schema in oneOf\"}]},{\"name\":\"ref\",\"valid\":false,\"failures\":[{\"path\":\"value\",\"message\":\"must be number\"}]},{\"name\":\"ref-missing\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"schema is false\"}]},{\"name\":\"conditional\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must match \\\"then\\\" schema\"}]},{\"name\":\"dependent\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must have properties b, c when property a is present\"},{\"path\":\"root\",\"message\":\"must have properties b, c when property a is present\"}]},{\"name\":\"contains\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must contain at least 1 valid item\"},{\"path\":\"root\",\"message\":\"must contain at least 1 valid item\"}]},{\"name\":\"unevaluated\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must not have unevaluated properties\"}]},{\"name\":\"prefix\",\"valid\":false,\"failures\":[{\"path\":\"2\",\"message\":\"schema is false\"}]},{\"name\":\"unicode\",\"valid\":false,\"failures\":[{\"path\":\"root\",\"message\":\"must not have fewer than 2 characters\"}]},{\"name\":\"valid\",\"valid\":true,\"failures\":[]}]", text);
}
fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const fixture = try engine.eval("({schema:{type:'object',properties:{n:{type:'number',minimum:10,multipleOf:3},s:{type:'string',minLength:4,pattern:'^x'},a:{type:'array',contains:{type:'integer'},minContains:2,uniqueItems:true}},required:['n','s','a'],additionalProperties:false,allOf:[{properties:{n:{type:'integer'}}}],unevaluatedProperties:false},value:{n:5,s:'a',a:[1,1],extra:true}})", "schema-evaluator-allocation-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    const schema = try vm.get(engine, fixture, "schema");
    defer engine.freeValue(schema);
    const value = try vm.get(engine, fixture, "value");
    defer engine.freeValue(value);
    var result = try evaluate(engine, schema, value);
    defer result.deinit(gpa);
}
test "native durable VM schema evaluation ordered errors logical contexts and regex resources unwind every GPA allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

test "native durable VM schema references preserve anchors resources encoded pointers dynamic recursive scopes and URI failures" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "nativeEvaluate", try engine.checked(c.JS_NewCFunction(engine.context, evaluatedCallback, "nativeEvaluate", 2)));
    errdefer std.debug.print("Schema reference VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const cases=[
        \\['anchor-valid',{$defs:{n:{$anchor:'n',type:'number'}},properties:{v:{$ref:'#n'}}},{v:2}],
        \\['anchor-invalid',{$defs:{n:{$anchor:'n',type:'number'}},properties:{v:{$ref:'#n'}}},{v:'2'}],
        \\['relative-resource',{$id:'/root',$defs:{n:{$id:'num',type:'number'}},properties:{v:{$ref:'num'}}},{v:2}],
        \\['absolute-resource',{$defs:{n:{$id:'https://example.com/number',type:'number'}},properties:{v:{$ref:'https://example.com/number'}}},{v:2}],
        \\['foreign-host-same-path',{$id:'https://one.example/root',type:'number',properties:{v:{$ref:'https://two.example/root'}}},{v:2}],
        \\['encoded-pointer',{$defs:{n:{type:'number'}},properties:{v:{$ref:'#/%24defs/n'}}},{v:2}],
        \\['escaped-pointer',{$defs:{'a/b~c':{type:'number'}},properties:{v:{$ref:'#/$defs/a~1b~0c'}}},{v:2}],
        \\['nested-id-pointer',{$id:'https://example.com/root',$defs:{inner:{$id:'inner',properties:{value:{$ref:'#/$defs/n'}},$defs:{n:{type:'number'}}}},$ref:'#/$defs/inner'},{value:2}],
        \\['middle-resource-pointer',{$id:'https://example.com/root',$defs:{inner:{$id:'inner',properties:{value:{$ref:'#/$defs/n'}},$defs:{n:{type:'number'}}}},$ref:'#/$defs/inner/properties/value'},2],
        \\['anchor-under-array',{$defs:{outer:{allOf:[{$anchor:'n',type:'number'}]}},properties:{v:{$ref:'#n'}}},{v:2}],
        \\['duplicate-anchor',{$defs:{a:{$anchor:'n',type:'number'},b:{$anchor:'n',type:'string'}},$ref:'#n'},'s'],
        \\['dynamic-anchor-valid',{$defs:{n:{$dynamicAnchor:'n',type:'number'}},properties:{v:{$dynamicRef:'#n'}}},{v:2}],
        \\['dynamic-anchor-invalid',{$defs:{n:{$dynamicAnchor:'n',type:'number'}},properties:{v:{$dynamicRef:'#n'}}},{v:'2'}],
        \\['dynamic-anchor-array',{$defs:{n:{allOf:[{$dynamicAnchor:'n',type:'number'}]}},properties:{v:{$dynamicRef:'#n'}}},{v:2}],
        \\['recursive-valid',{$recursiveAnchor:true,type:'object',properties:{n:{type:'number'},child:{$recursiveRef:'#'}}},{n:1,child:{n:2}}],
        \\['recursive-invalid',{$recursiveAnchor:true,type:'object',properties:{n:{type:'number'},child:{$recursiveRef:'#'}}},{n:1,child:{n:'2'}}],
        \\['dynamic-tree',{$id:'https://example.com/tree',$dynamicAnchor:'node',type:'object',properties:{n:{type:'number'},children:{type:'array',items:{$dynamicRef:'#node'}}}},{n:1,children:[{n:'bad'}]}],
        \\['missing-remote',{$ref:'https://missing.example/schema'},{}],
        \\['empty-ref',{$ref:''},3],
        \\['malformed-uri',{$ref:'http://['},3],
        \\['malformed-percent',{$defs:{n:{type:'number'}},$ref:'#/%ZZ'},3],
        \\];
        \\
        \\const output=[];for(const[name,schema,value]of cases){try{output.push({name,...nativeEvaluate(schema,value)})}catch(error){output.push({name,error:{name:error.name,message:error.message}})}}globalThis.result=JSON.stringify(output);
    , "native-schema-reference-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-schema-reference-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(@embedFile("../durable/fixtures/schema-reference-scopes-1ced.json"), text);
}

test "native durable VM schema graphemes constants undefined sparse unique hashes numeric error formatting and invalid keyword admission match source" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "nativeEvaluate", try engine.checked(c.JS_NewCFunction(engine.context, evaluatedCallback, "nativeEvaluate", 2)));
    errdefer std.debug.print("Schema edge VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\const cases=[['combining',{type:'string',maxLength:1},'e\u0301'],['zwj',{type:'string',maxLength:1},'👩‍👩‍👧‍👦'],['flag',{type:'string',maxLength:1},'🇬🇧'],['skin-tone',{type:'string',maxLength:1},'👋🏽'],['combining-leading',{type:'string',minLength:2},'\u0301a'],['variation',{type:'string',maxLength:1},'✈️'],['trailing-zwj',{type:'string',maxLength:1},'a\u200d'],['high-surrogate',{type:'string',maxLength:1},'\ud800'],['negative-zero-limit',{type:'number',minimum:-0},-1],['exponent-limit',{type:'number',minimum:1e21},1],['const-undefined',{const:undefined},1],['const-object-key-name',{const:{a:undefined}},{b:undefined}],['const-sparse',{const:Array(1)},[99]],['const-array-extra',{const:Object.assign([],{extra:1})},[]],['const-object-array',{const:{length:0}},[]],['unique-negative-zero',{type:'array',uniqueItems:true},[-0,0]],['unique-nan',{type:'array',uniqueItems:true},[NaN,NaN]],['unique-surrogates',{type:'array',uniqueItems:true},['\ud800','\udfff']],['unique-sparse',{type:'array',uniqueItems:true},Array(2)],['unique-bigint-wrap',{type:'array',uniqueItems:true},[0n,18446744073709551616n]],['empty-required',{type:'object',properties:{parent:{type:'object',required:['']}}},{parent:{}}],['invalid-required',{required:[3]},{n:1}],['invalid-property-map',{properties:{bad:null,n:{type:'number'}}},{n:'bad'}]];
        \\
        \\const output=cases.map(([name,schema,value])=>{try{return{name,...nativeEvaluate(schema,value)}}catch(error){return{name,error:{name:error.name,message:error.message}}}});globalThis.result=JSON.stringify(output);
    , "native-schema-grapheme-hash-source-corpus");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-schema-grapheme-hash-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(@embedFile("../durable/fixtures/schema-grapheme-constants-unique-1ced.json"), text);
}
