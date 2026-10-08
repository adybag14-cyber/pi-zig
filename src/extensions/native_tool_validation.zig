//! Native schema evaluation for the durable tool workflow. Not yet installed as
//! a public module: coercion, cache and format integration qualify separately.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Failure = struct { path: []const u8, message: []const u8 };
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
pub fn evaluate(engine: *Engine, schema: c.JSValue, value: c.JSValue) !Result {
    const arena = try engine.gpa.create(std.heap.ArenaAllocator);
    errdefer engine.gpa.destroy(arena);
    arena.* = .init(engine.gpa);
    errdefer arena.deinit();
    var context: Context = .{ .engine = engine, .a = arena.allocator(), .root = schema };
    var evaluated: Evaluated = .{};
    const valid = try context.walk(schema, value, "", &evaluated);
    return .{ .arena = arena, .valid = valid, .failures = context.failures.items };
}
const Context = struct {
    engine: *Engine,
    a: std.mem.Allocator,
    root: c.JSValue,
    failures: std.ArrayList(Failure) = .empty,
    active: std.ArrayList(Pair) = .empty,
    fn add(self: *Context, path: []const u8, message: []const u8) !void {
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
        return vm.get(self.engine, value, name);
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
    fn branch(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !struct { valid: bool, failures: []const Failure, evaluated: Evaluated } {
        var child: Context = .{ .engine = self.engine, .a = self.a, .root = self.root, .active = self.active };
        var evaluated: Evaluated = .{};
        const valid = try child.walk(schema, value, path, &evaluated);
        return .{ .valid = valid, .failures = child.failures.items, .evaluated = evaluated };
    }
    fn mergeErrors(self: *Context, failures: []const Failure) !void {
        for (failures) |failure| try self.add(failure.path, failure.message);
    }
    fn equal(self: *Context, left: c.JSValue, right: c.JSValue) anyerror!bool {
        if (c.JS_IsStrictEqual(self.engine.context, left, right)) return true;
        if (!c.JS_IsObject(left) or !c.JS_IsObject(right) or c.JS_IsArray(left) != c.JS_IsArray(right)) return false;
        const lhs = try self.keys(left, false);
        const rhs = try self.keys(right, false);
        if (lhs.len != rhs.len) return false;
        for (lhs) |key| {
            if (!try self.has(right, key)) return false;
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
        if (self.failures.items.len >= 8) return false;
        for (self.active.items) |pair| if (c.JS_IsStrictEqual(self.engine.context, pair.schema, schema) and c.JS_IsStrictEqual(self.engine.context, pair.value, value)) {
            _ = try self.engine.checked(c.JS_ThrowRangeError(self.engine.context, "Maximum call stack size exceeded"));
            unreachable;
        };
        try self.active.append(self.a, .{ .schema = schema, .value = value });
        defer _ = self.active.pop();
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
        if (try self.number(value)) |scalar| try self.numberRules(schema, scalar, path);
        inline for (.{ "$ref", "$recursiveRef", "$dynamicRef" }) |keyword| {
            const reference = try self.get(schema, keyword);
            defer self.engine.freeValue(reference);
            if (c.JS_IsString(reference)) {
                const target = try self.resolve(try self.textValue(reference));
                defer self.engine.freeValue(target);
                const branch_result = try self.branch(target, value, path);
                if (branch_result.valid) try evaluated.merge(self.a, branch_result.evaluated) else try self.mergeErrors(branch_result.failures);
            }
        }
        const constant = try self.get(schema, "const");
        defer self.engine.freeValue(constant);
        if (try self.has(schema, "const") and !try self.equal(constant, value)) try self.add(path, "must be equal to constant");
        const enumeration = try self.get(schema, "enum");
        defer self.engine.freeValue(enumeration);
        if (c.JS_IsArray(enumeration)) {
            var matched = false;
            for (0..try vm.length(self.engine, enumeration)) |index| {
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, enumeration, @intCast(index)));
                defer self.engine.freeValue(item);
                matched = matched or try self.equal(item, value);
            }
            if (!matched) try self.add(path, "must be equal to one of the allowed values");
        }
        try self.logicalRules(schema, value, path, evaluated);
        try self.unevaluatedRules(schema, value, path, evaluated);
        return before == self.failures.items.len;
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
        if (missing.items.len != 0) try self.add(try self.childPath(path, missing.items[0]), try std.fmt.allocPrint(self.a, "must have required properties {s}", .{try std.mem.join(self.a, ", ", missing.items)}));
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
                    covered = covered or try self.matches(pattern, key, true);
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
            for (try self.keys(dependencies, true)) |key| {
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
        if (c.JS_IsObject(patterns)) for (try self.keys(patterns, true)) |pattern| {
            const rule = try self.property(patterns, pattern);
            defer self.engine.freeValue(rule);
            for (actual) |key| if (try self.matches(pattern, key, true)) {
                const child = try self.property(value, key);
                defer self.engine.freeValue(child);
                const result = try self.branch(rule, child, try self.childPath(path, key));
                if (result.valid) try evaluated.keys.put(self.a, key, {}) else try self.mergeErrors(result.failures);
            };
        };
        if (c.JS_IsObject(properties)) for (try self.keys(properties, true)) |key| {
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
                if (!(try self.branch(property_names, string, path)).valid) try invalid.append(self.a, key);
            }
            if (invalid.items.len != 0) try self.add(path, try std.fmt.allocPrint(self.a, "property names {s} are invalid", .{try std.mem.join(self.a, ", ", invalid.items)}));
        }
        inline for (.{ "minProperties", "maxProperties" }, .{ "must not have fewer than", "must not have more than" }) |keyword, phrase| {
            const limit_value = try self.get(schema, keyword);
            defer self.engine.freeValue(limit_value);
            if (try self.number(limit_value)) |limit| if (if (comptime std.mem.eql(u8, keyword, "minProperties")) @as(f64, @floatFromInt(actual.len)) < limit else @as(f64, @floatFromInt(actual.len)) > limit) try self.add(path, try std.fmt.allocPrint(self.a, "{s} {d} properties", .{ phrase, limit }));
        }
    }
    fn numberRules(self: *Context, schema: c.JSValue, value: f64, path: []const u8) !void {
        inline for (.{ "exclusiveMaximum", "exclusiveMinimum", "maximum", "minimum", "multipleOf" }, .{ "<", ">", "<=", ">=", "multiple of" }, 0..) |keyword, comparison, operation| {
            const limit_value = try self.get(schema, keyword);
            defer self.engine.freeValue(limit_value);
            if (try self.number(limit_value)) |limit| {
                const valid = switch (operation) {
                    0 => value < limit,
                    1 => value > limit,
                    2 => value <= limit,
                    3 => value >= limit,
                    else => blk: {
                        if (limit == 0) break :blk false;
                        const reciprocal = 1 / limit;
                        if (value == @trunc(value) and std.math.isFinite(reciprocal) and @rem(reciprocal, 1) == 0) break :blk true;
                        const remainder = @rem(value, limit);
                        break :blk @min(@abs(remainder), @min(@abs(remainder - limit), @abs(remainder + limit))) < 1e-10;
                    },
                };
                if (!valid) try self.add(path, try std.fmt.allocPrint(self.a, "must be {s} {d}", .{ comparison, limit }));
            }
        }
    }
    fn arrayItem(self: *Context, rule: c.JSValue, value: c.JSValue, index: usize, path: []const u8, evaluated: *Evaluated) !void {
        const child = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
        defer self.engine.freeValue(child);
        const result = try self.branch(rule, child, try self.childPath(path, try std.fmt.allocPrint(self.a, "{d}", .{index})));
        if (result.valid) try evaluated.items.put(self.a, index, {}) else try self.mergeErrors(result.failures);
    }
    fn arrayRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8, evaluated: *Evaluated) !void {
        const length = try vm.length(self.engine, value);
        const items = try self.get(schema, "items");
        defer self.engine.freeValue(items);
        const prefix = try self.get(schema, "prefixItems");
        defer self.engine.freeValue(prefix);
        const additional = try self.get(schema, "additionalItems");
        defer self.engine.freeValue(additional);
        if (c.JS_IsArray(items) and !c.JS_IsUndefined(additional)) for (@min(length, try vm.length(self.engine, items))..length) |index| try self.arrayItem(additional, value, index, path, evaluated);
        const contains = try self.get(schema, "contains");
        defer self.engine.freeValue(contains);
        var contained: usize = 0;
        if (!c.JS_IsUndefined(contains)) {
            for (0..length) |index| {
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
                defer self.engine.freeValue(item);
                if ((try self.branch(contains, item, path)).valid) {
                    contained += 1;
                    try evaluated.items.put(self.a, index, {});
                }
            }
            if (contained == 0) try self.add(path, "must contain at least 1 valid item");
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
        if (!c.JS_IsUndefined(contains)) if (try self.number(maximum_contains)) |limit| if (@as(f64, @floatFromInt(contained)) > limit) try self.add(path, "must contain at least 1 valid item");
        const maximum = try self.get(schema, "maxItems");
        defer self.engine.freeValue(maximum);
        if (try self.number(maximum)) |limit| if (@as(f64, @floatFromInt(length)) > limit) try self.add(path, try std.fmt.allocPrint(self.a, "must not have more than {d} items", .{limit}));
        const minimum_contains = try self.get(schema, "minContains");
        defer self.engine.freeValue(minimum_contains);
        if (!c.JS_IsUndefined(contains)) if (try self.number(minimum_contains)) |limit| if (@as(f64, @floatFromInt(contained)) < limit) try self.add(path, "must contain at least 1 valid item");
        const minimum = try self.get(schema, "minItems");
        defer self.engine.freeValue(minimum);
        if (try self.number(minimum)) |limit| if (@as(f64, @floatFromInt(length)) < limit) try self.add(path, try std.fmt.allocPrint(self.a, "must not have fewer than {d} items", .{limit}));
        if (c.JS_IsArray(prefix)) for (0..@min(length, try vm.length(self.engine, prefix))) |index| {
            const rule = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, prefix, @intCast(index)));
            defer self.engine.freeValue(rule);
            try self.arrayItem(rule, value, index, path, evaluated);
        };
        const unique = try self.get(schema, "uniqueItems");
        defer self.engine.freeValue(unique);
        if (c.JS_IsBool(unique) and c.JS_ToBool(self.engine.context, unique) != 0) {
            var duplicate = false;
            outer: for (0..length) |index| {
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(index)));
                defer self.engine.freeValue(item);
                for (0..index) |earlier| {
                    const prior = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, value, @intCast(earlier)));
                    defer self.engine.freeValue(prior);
                    if (try self.equal(prior, item)) {
                        duplicate = true;
                        break :outer;
                    }
                }
            }
            if (duplicate) try self.add(path, "must not have duplicate items");
        }
    }
    fn stringRules(self: *Context, schema: c.JSValue, value: c.JSValue, path: []const u8) !void {
        const text = try self.textValue(value);
        var characters: usize = 0;
        var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |_| characters += 1;
        inline for (.{ "maxLength", "minLength" }, .{ "more", "fewer" }) |keyword, phrase| {
            const size = try self.get(schema, keyword);
            defer self.engine.freeValue(size);
            if (try self.number(size)) |limit| if (if (comptime std.mem.eql(u8, keyword, "maxLength")) @as(f64, @floatFromInt(characters)) > limit else @as(f64, @floatFromInt(characters)) < limit) try self.add(path, try std.fmt.allocPrint(self.a, "must not have {s} than {d} characters", .{ phrase, limit }));
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
        if (c.JS_IsString(pattern)) {
            const expression = try self.textValue(pattern);
            if (!try self.matches(expression, text, true)) try self.add(path, try std.fmt.allocPrint(self.a, "must match pattern \"{s}\"", .{expression}));
        }
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
        if (!c.JS_IsUndefined(negative) and (try self.branch(negative, value, path)).valid) try self.add(path, "must not be valid");
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
                    } else try collected.appendSlice(self.a, result.failures);
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
    var result = try evaluate(engine, schema, value);
    defer result.deinit(engine.gpa);
    const output = try vm.object(engine);
    errdefer engine.freeValue(output);
    try vm.put(engine, output, "valid", c.pi_js_bool(engine.context, @intFromBool(result.valid)));
    const failures = try vm.array(engine);
    defer engine.freeValue(failures);
    for (result.failures, 0..) |failure, index| {
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
