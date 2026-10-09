//! Native owner-VM reference/resource traversal for Pi's context-free Compile
//! call. Remote schemas are not fetched by the original validation API.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const default_base = "https://json-schema.org/";
pub const Frame = struct { root: c.JSValue, base: []const u8, id_depth: usize, resource_depth: usize };
pub const Resolution = struct {
    schema: c.JSValue,
    retrieved: ?Frame = null,
    resource: ?c.JSValue = null,
    pub fn deinit(self: Resolution, engine: *Engine) void {
        engine.freeValue(self.schema);
        if (self.retrieved) |frame| engine.freeValue(frame.root);
        if (self.resource) |resource| engine.freeValue(resource);
    }
};
pub const Mark = struct { ids: usize, resources: usize, dynamic: usize, recursive: usize, frames: usize, pending: bool };
pub const Stack = struct {
    engine: *Engine,
    a: std.mem.Allocator,
    root: c.JSValue,
    context: ?c.JSValue = null,
    ids: std.ArrayList(c.JSValue) = .empty,
    resources: std.ArrayList(c.JSValue) = .empty,
    dynamic: std.ArrayList(c.JSValue) = .empty,
    recursive: std.ArrayList(c.JSValue) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    pending: bool = true,
    entry: ?Resolution = null,
    searching: std.ArrayList(c.JSValue) = .empty,
    fn object(self: *Stack, value: c.JSValue) bool {
        return c.JS_IsObject(value) and !c.JS_IsArray(value) and !c.JS_IsFunction(self.engine.context, value);
    }
    fn text(self: *Stack, value: c.JSValue) ![]const u8 {
        const output = try self.engine.toString(value);
        defer self.engine.gpa.free(output);
        return self.a.dupe(u8, output);
    }
    fn property(self: *Stack, value: c.JSValue, key: []const u8) !c.JSValue {
        const atom = c.JS_NewAtomLen(self.engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        return self.engine.checked(c.JS_GetProperty(self.engine.context, value, atom));
    }
    fn names(self: *Stack, value: c.JSValue) ![]const []const u8 {
        var keys: [*c]c.JSPropertyEnum = null;
        var length: u32 = 0;
        if (c.JS_GetOwnPropertyNames(self.engine.context, &keys, &length, value, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(self.engine.context, keys, length);
        const result = try self.a.alloc([]const u8, length);
        for (result, 0..) |*key, index| {
            const label = try self.engine.checked(c.JS_AtomToString(self.engine.context, keys[index].atom));
            defer self.engine.freeValue(label);
            key.* = try self.text(label);
        }
        return result;
    }
    fn stringProperty(self: *Stack, value: c.JSValue, key: [:0]const u8) !?[]const u8 {
        if (!self.object(value)) return null;
        const field = try vm.get(self.engine, value, key);
        defer self.engine.freeValue(field);
        return if (c.JS_IsString(field)) try self.text(field) else null;
    }
    fn flag(self: *Stack, value: c.JSValue, key: [:0]const u8) !bool {
        if (!self.object(value)) return false;
        const field = try vm.get(self.engine, value, key);
        defer self.engine.freeValue(field);
        return c.JS_IsBool(field) and c.JS_ToBool(self.engine.context, field) != 0;
    }
    fn url(self: *Stack, value: []const u8, base: []const u8) !c.JSValue {
        if (self.engine.url_class == 0) try @import("native_url.zig").install(self.engine);
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const constructor = try vm.get(self.engine, global, "URL");
        defer self.engine.freeValue(constructor);
        const reference = try self.engine.checked(c.JS_NewStringLen(self.engine.context, value.ptr, value.len));
        defer self.engine.freeValue(reference);
        const origin = try self.engine.checked(c.JS_NewStringLen(self.engine.context, base.ptr, base.len));
        defer self.engine.freeValue(origin);
        var args = [_]c.JSValue{ reference, origin };
        const result = c.JS_CallConstructor(self.engine.context, constructor, args.len, &args);
        if (c.JS_IsException(result) and self.engine.native_url_constructor != null and c.JS_IsStrictEqual(self.engine.context, constructor, self.engine.native_url_constructor.?)) {
            const failure = c.JS_GetException(self.engine.context);
            defer self.engine.freeValue(failure);
            const name = try vm.get(self.engine, failure, "name");
            defer self.engine.freeValue(name);
            if (c.JS_IsString(name) and std.mem.eql(u8, try self.text(name), "TypeError")) {
                if (c.JS_DefinePropertyValueStr(self.engine.context, failure, "message", c.JS_NewString(self.engine.context, "Invalid URL"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
                try vm.put(self.engine, failure, "code", try self.engine.checked(c.JS_NewString(self.engine.context, "ERR_INVALID_URL")));
                try vm.put(self.engine, failure, "input", c.JS_DupValue(self.engine.context, reference));
                try vm.put(self.engine, failure, "base", c.JS_DupValue(self.engine.context, origin));
            }
            return self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, failure)));
        }
        return self.engine.checked(result);
    }
    fn href(self: *Stack, value: []const u8, base: []const u8) ![]const u8 {
        const parsed = try self.url(value, base);
        defer self.engine.freeValue(parsed);
        const output = try vm.get(self.engine, parsed, "href");
        defer self.engine.freeValue(output);
        return self.text(output);
    }
    fn buildBase(self: *Stack, resource: bool) ![]const u8 {
        const values = if (resource) self.resources.items else self.ids.items;
        const frame: ?Frame = if (self.frames.items.len != 0) self.frames.items[self.frames.items.len - 1] else null;
        var base = if (frame) |current| current.base else default_base;
        const start = if (frame) |current| if (resource) current.resource_depth else current.id_depth else 0;
        for (values[start..]) |schema| base = try self.href((try self.stringProperty(schema, "$id")).?, base);
        return base;
    }
    fn referenceBase(self: *Stack) ![]const u8 {
        if (self.frames.items.len == 0 and self.ids.items.len != 0) {
            const id = (try self.stringProperty(self.ids.items[self.ids.items.len - 1], "$id")).?;
            var index: usize = 0;
            if (id.len != 0 and std.ascii.isAlphabetic(id[0])) {
                index = 1;
                while (index < id.len and (std.ascii.isAlphanumeric(id[index]) or id[index] == '+' or id[index] == '.' or id[index] == '-')) : (index += 1) {}
            }
            if (index == 0 or index == id.len or id[index] != ':') return self.buildBase(false);
        }
        return self.buildBase(true);
    }
    fn lexical(self: *Stack) c.JSValue {
        if (self.frames.items.len != 0) {
            const frame = self.frames.items[self.frames.items.len - 1];
            return if (self.ids.items.len > frame.id_depth) self.ids.items[self.ids.items.len - 1] else frame.root;
        }
        return if (self.ids.items.len != 0) self.ids.items[self.ids.items.len - 1] else self.root;
    }
    fn searchEnter(self: *Stack, schema: c.JSValue) !void {
        for (self.searching.items) |current| if (c.JS_IsStrictEqual(self.engine.context, current, schema)) {
            _ = try self.engine.checked(c.JS_ThrowRangeError(self.engine.context, "Maximum call stack size exceeded"));
            unreachable;
        };
        try self.searching.append(self.a, schema);
    }
    fn registerAnchors(self: *Stack, schema: c.JSValue, root: bool) anyerror!void {
        if (!c.JS_IsObject(schema) or c.JS_IsFunction(self.engine.context, schema)) return;
        try self.searchEnter(schema);
        defer _ = self.searching.pop();
        if (c.JS_IsArray(schema)) {
            for (0..try vm.length(self.engine, schema)) |index| {
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, schema, @intCast(index)));
                defer self.engine.freeValue(item);
                try self.registerAnchors(item, false);
            }
        } else {
            if (!root and try self.stringProperty(schema, "$id") != null) return;
            if (!root and try self.stringProperty(schema, "$dynamicAnchor") != null) try self.dynamic.append(self.a, schema);
            for (try self.names(schema)) |key| {
                const child = try self.property(schema, key);
                defer self.engine.freeValue(child);
                try self.registerAnchors(child, false);
            }
        }
    }
    fn registerResource(self: *Stack, schema: c.JSValue) !void {
        try self.ids.append(self.a, schema);
        if (self.pending) try self.resources.append(self.a, schema);
        self.pending = false;
        try self.registerAnchors(schema, true);
    }
    pub fn push(self: *Stack, schema: c.JSValue) !Mark {
        const mark: Mark = .{ .ids = self.ids.items.len, .resources = self.resources.items.len, .dynamic = self.dynamic.items.len, .recursive = self.recursive.items.len, .frames = self.frames.items.len, .pending = self.pending };
        const entry = self.entry;
        self.entry = null;
        if (entry != null) self.pending = true;
        if (entry) |resolution| if (resolution.resource) |resource| try self.registerResource(resource);
        if (try self.stringProperty(schema, "$id") != null) try self.registerResource(schema);
        if (try self.stringProperty(schema, "$dynamicAnchor") != null) try self.dynamic.append(self.a, schema);
        if (try self.flag(schema, "$recursiveAnchor")) try self.recursive.append(self.a, schema);
        if (entry) |resolution| if (resolution.retrieved) |frame| try self.frames.append(self.a, .{ .root = frame.root, .base = frame.base, .id_depth = self.ids.items.len, .resource_depth = self.resources.items.len });
        return mark;
    }
    pub fn pop(self: *Stack, mark: Mark) void {
        self.ids.items.len = mark.ids;
        self.resources.items.len = mark.resources;
        self.dynamic.items.len = mark.dynamic;
        self.recursive.items.len = mark.recursive;
        self.frames.items.len = mark.frames;
        self.pending = mark.pending;
    }
    fn decode(self: *Stack, fragment: []const u8) ![]const u8 {
        const global = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(global);
        const callback = try vm.get(self.engine, global, "decodeURIComponent");
        defer self.engine.freeValue(callback);
        const value = try self.engine.checked(c.JS_NewStringLen(self.engine.context, fragment.ptr, fragment.len));
        defer self.engine.freeValue(value);
        var args = [_]c.JSValue{value};
        const result = c.JS_Call(self.engine.context, callback, c.pi_js_undefined(), 1, &args);
        if (c.JS_IsException(result) and c.JS_IsStrictEqual(self.engine.context, callback, self.engine.intrinsic_decode_uri_component)) {
            const failure = c.JS_GetException(self.engine.context);
            defer self.engine.freeValue(failure);
            const name = try vm.get(self.engine, failure, "name");
            defer self.engine.freeValue(name);
            if (c.JS_IsString(name) and std.mem.eql(u8, try self.text(name), "URIError")) {
                if (c.JS_DefinePropertyValueStr(self.engine.context, failure, "message", c.JS_NewString(self.engine.context, "URI malformed"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
            }
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, failure)));
            unreachable;
        }
        const decoded = try self.engine.checked(result);
        defer self.engine.freeValue(decoded);
        return self.text(decoded);
    }
    fn hashMatch(self: *Stack, schema: c.JSValue, reference: c.JSValue) !c.JSValue {
        const href_value = try vm.get(self.engine, reference, "href");
        defer self.engine.freeValue(href_value);
        const href_text = try self.text(href_value);
        if (std.mem.endsWith(u8, href_text, "#")) return c.JS_DupValue(self.engine.context, schema);
        const hash_value = try vm.get(self.engine, reference, "hash");
        defer self.engine.freeValue(hash_value);
        const hash = try self.text(hash_value);
        if (!std.mem.startsWith(u8, hash, "#")) return c.pi_js_undefined();
        const pointer = try self.decode(hash[1..]);
        if (!std.mem.startsWith(u8, pointer, "/")) return c.pi_js_undefined();
        var target = c.JS_DupValue(self.engine.context, schema);
        errdefer self.engine.freeValue(target);
        var segments = std.mem.splitScalar(u8, pointer[1..], '/');
        while (segments.next()) |segment| {
            if (!c.JS_IsObject(target)) {
                self.engine.freeValue(target);
                return c.pi_js_undefined();
            }
            var decoded: std.ArrayList(u8) = .empty;
            var index: usize = 0;
            while (index < segment.len) : (index += 1) {
                if (segment[index] == '~' and index + 1 < segment.len and (segment[index + 1] == '0' or segment[index + 1] == '1')) {
                    index += 1;
                    try decoded.append(self.a, if (segment[index] == '0') '~' else '/');
                } else try decoded.append(self.a, segment[index]);
            }
            const next = try self.property(target, decoded.items);
            self.engine.freeValue(target);
            target = next;
        }
        return target;
    }
    fn match(self: *Stack, schema: c.JSValue, base: []const u8, reference: c.JSValue) !c.JSValue {
        const ref_href_value = try vm.get(self.engine, reference, "href");
        defer self.engine.freeValue(ref_href_value);
        const ref_href = try self.text(ref_href_value);
        const hash_value = try vm.get(self.engine, reference, "hash");
        defer self.engine.freeValue(hash_value);
        const hash = try self.text(hash_value);
        if (try self.stringProperty(schema, "$id")) |id| {
            if (std.mem.eql(u8, id, hash)) return c.JS_DupValue(self.engine.context, schema);
            const base_url = try self.url(base, default_base);
            defer self.engine.freeValue(base_url);
            const ref_url = try self.url(ref_href, base);
            defer self.engine.freeValue(ref_url);
            const base_path = try vm.get(self.engine, base_url, "pathname");
            defer self.engine.freeValue(base_path);
            const ref_path = try vm.get(self.engine, ref_url, "pathname");
            defer self.engine.freeValue(ref_path);
            if (c.JS_IsStrictEqual(self.engine.context, base_path, ref_path)) {
                const target = if (std.mem.startsWith(u8, hash, "#")) try self.hashMatch(schema, reference) else c.JS_DupValue(self.engine.context, schema);
                if (!c.JS_IsUndefined(target)) return target;
                self.engine.freeValue(target);
            }
        }
        for ([_][:0]const u8{ "$anchor", "$dynamicAnchor" }) |keyword| if (try self.stringProperty(schema, keyword)) |anchor| {
            const fragment = try std.fmt.allocPrint(self.a, "#{s}", .{anchor});
            if (std.mem.eql(u8, try self.href(fragment, base), try self.href(ref_href, base))) return c.JS_DupValue(self.engine.context, schema);
        };
        return self.hashMatch(schema, reference);
    }
    fn fromValue(self: *Stack, schema: c.JSValue, base: []const u8, reference: c.JSValue) anyerror!c.JSValue {
        if (!c.JS_IsObject(schema) or c.JS_IsFunction(self.engine.context, schema)) return c.pi_js_undefined();
        try self.searchEnter(schema);
        defer _ = self.searching.pop();
        const next_base = if (try self.stringProperty(schema, "$id")) |id| try self.href(id, base) else base;
        if (self.object(schema)) {
            const target = try self.match(schema, next_base, reference);
            if (!c.JS_IsUndefined(target)) return target;
            self.engine.freeValue(target);
        }
        var result = c.pi_js_undefined();
        errdefer self.engine.freeValue(result);
        if (c.JS_IsArray(schema)) {
            for (0..try vm.length(self.engine, schema)) |index| {
                const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, schema, @intCast(index)));
                defer self.engine.freeValue(value);
                const target = try self.fromValue(value, next_base, reference);
                if (!c.JS_IsUndefined(target)) {
                    self.engine.freeValue(result);
                    result = target;
                } else self.engine.freeValue(target);
            }
        } else for (try self.names(schema)) |key| {
            if (std.mem.eql(u8, key, "const") or std.mem.eql(u8, key, "enum")) continue;
            const value = try self.property(schema, key);
            defer self.engine.freeValue(value);
            const target = try self.fromValue(value, next_base, reference);
            if (!c.JS_IsUndefined(target)) {
                self.engine.freeValue(result);
                result = target;
            } else self.engine.freeValue(target);
        }
        return result;
    }
    fn ref(self: *Stack, root: c.JSValue, base: []const u8, reference: []const u8) !c.JSValue {
        const parsed = try self.url(reference, base);
        defer self.engine.freeValue(parsed);
        const direct = try self.contextProperty(reference);
        if (!c.JS_IsUndefined(direct) and !c.JS_IsNull(direct)) return direct;
        self.engine.freeValue(direct);
        const local = try self.fromValue(root, base, parsed);
        if (!c.JS_IsUndefined(local) and !c.JS_IsNull(local)) return local;
        self.engine.freeValue(local);
        const href_value = try vm.get(self.engine, parsed, "href");
        defer self.engine.freeValue(href_value);
        const full = try self.text(href_value);
        const canonical = full[0 .. std.mem.indexOfScalar(u8, full, '#') orelse full.len];
        const base_full = try self.href(base, default_base);
        const base_canonical = base_full[0 .. std.mem.indexOfScalar(u8, base_full, '#') orelse base_full.len];
        if (std.mem.eql(u8, canonical, base_canonical)) return c.pi_js_undefined();
        const remote = try self.contextProperty(canonical);
        defer self.engine.freeValue(remote);
        if (c.JS_IsUndefined(remote)) return c.pi_js_undefined();
        const hash = try vm.get(self.engine, parsed, "hash");
        defer self.engine.freeValue(hash);
        if ((try self.text(hash)).len == 0) return c.JS_DupValue(self.engine.context, remote);
        const remote_base = if (try self.stringProperty(remote, "$id")) |id| try self.href(id, canonical) else canonical;
        return self.fromValue(remote, remote_base, parsed);
    }
    fn contextProperty(self: *Stack, name: []const u8) !c.JSValue {
        const context = self.context orelse return c.pi_js_undefined();
        if (!c.JS_IsObject(context)) return c.pi_js_undefined();
        const atom = c.JS_NewAtomLen(self.engine.context, name.ptr, name.len);
        defer c.JS_FreeAtom(self.engine.context, atom);
        if (std.mem.eql(u8, name, "__proto__") or std.mem.eql(u8, name, "constructor") or std.mem.eql(u8, name, "prototype")) {
            var descriptor: c.JSPropertyDescriptor = undefined;
            const present = c.JS_GetOwnProperty(self.engine.context, &descriptor, context, atom);
            if (present < 0) return error.JavaScriptException;
            if (present == 0) return c.pi_js_undefined();
            self.engine.freeValue(descriptor.value);
            self.engine.freeValue(descriptor.getter);
            self.engine.freeValue(descriptor.setter);
        } else {
            const present = c.JS_HasProperty(self.engine.context, context, atom);
            if (present < 0) return error.JavaScriptException;
            if (present == 0) return c.pi_js_undefined();
        }
        return self.engine.checked(c.JS_GetProperty(self.engine.context, context, atom));
    }
    fn findBase(self: *Stack, schema: c.JSValue, base: []const u8, target: c.JSValue) anyerror!?[]const u8 {
        if (c.JS_IsStrictEqual(self.engine.context, schema, target)) return base;
        if (!c.JS_IsObject(schema) or c.JS_IsFunction(self.engine.context, schema)) return null;
        try self.searchEnter(schema);
        defer _ = self.searching.pop();
        const next_base = if (try self.stringProperty(schema, "$id")) |id| try self.href(id, base) else base;
        if (c.JS_IsArray(schema)) {
            for (0..try vm.length(self.engine, schema)) |index| {
                const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, schema, @intCast(index)));
                defer self.engine.freeValue(value);
                if (try self.findBase(value, next_base, target)) |found| return found;
            }
        } else for (try self.names(schema)) |key| {
            const value = try self.property(schema, key);
            defer self.engine.freeValue(value);
            if (try self.findBase(value, next_base, target)) |found| return found;
        }
        return null;
    }
    fn dynamicAnchor(self: *Stack, schema: c.JSValue, name: []const u8) anyerror!c.JSValue {
        if (!self.object(schema)) return c.pi_js_undefined();
        if (try self.stringProperty(schema, "$dynamicAnchor")) |anchor| if (std.mem.eql(u8, anchor, name)) return c.JS_DupValue(self.engine.context, schema);
        try self.searchEnter(schema);
        defer _ = self.searching.pop();
        for (try self.names(schema)) |key| {
            const value = try self.property(schema, key);
            defer self.engine.freeValue(value);
            const found = try self.dynamicAnchor(value, name);
            if (!c.JS_IsUndefined(found)) return found;
            self.engine.freeValue(found);
        }
        return c.pi_js_undefined();
    }
    pub fn resolve(self: *Stack, keyword: [:0]const u8, reference: []const u8) !Resolution {
        const lexical_schema = self.lexical();
        const base = try self.referenceBase();
        const recursive = std.mem.eql(u8, keyword, "$recursiveRef");
        const dynamic = std.mem.eql(u8, keyword, "$dynamicRef");
        const fragment = std.mem.startsWith(u8, reference, "#");
        const ref_root = if (recursive) if (try self.flag(lexical_schema, "$recursiveAnchor") and self.recursive.items.len != 0) self.recursive.items[0] else lexical_schema else if (fragment) lexical_schema else if (self.frames.items.len != 0) lexical_schema else self.root;
        const reference_base = if (recursive or dynamic) try self.buildBase(false) else base;
        var target = try self.ref(ref_root, reference_base, reference);
        errdefer self.engine.freeValue(target);
        if (dynamic) {
            const parsed = try self.url(reference, reference_base);
            defer self.engine.freeValue(parsed);
            const hash_value = try vm.get(self.engine, parsed, "hash");
            defer self.engine.freeValue(hash_value);
            const hash = try self.text(hash_value);
            if (!std.mem.startsWith(u8, hash, "#/") and std.mem.startsWith(u8, hash, "#")) {
                const name = if (c.JS_IsUndefined(target)) try self.decode(hash[1..]) else (try self.stringProperty(target, "$dynamicAnchor")) orelse return .{ .schema = target };
                for (self.dynamic.items) |anchor| if (try self.stringProperty(anchor, "$dynamicAnchor")) |declared| if (std.mem.eql(u8, name, declared)) {
                    self.engine.freeValue(target);
                    target = c.JS_DupValue(self.engine.context, anchor);
                    return .{ .schema = target };
                };
                if (c.JS_IsUndefined(target)) {
                    self.engine.freeValue(target);
                    target = try self.dynamicAnchor(self.root, name);
                }
            }
        }
        if (c.JS_IsUndefined(target)) {
            self.engine.freeValue(target);
            return .{ .schema = c.pi_js_bool(self.engine.context, 0) };
        }
        var resolution: Resolution = .{ .schema = target };
        errdefer {
            if (resolution.retrieved) |frame| self.engine.freeValue(frame.root);
            if (resolution.resource) |resource| self.engine.freeValue(resource);
        }
        if (recursive or dynamic or !self.object(target)) return resolution;
        if (fragment) {
            const schema_keyword = try vm.get(self.engine, self.root, "$schema");
            defer self.engine.freeValue(schema_keyword);
            if (c.JS_IsUndefined(schema_keyword)) if (try self.findBase(lexical_schema, base, target)) |target_base| {
                if (!std.mem.eql(u8, target_base, base)) resolution.retrieved = .{ .root = c.JS_DupValue(self.engine.context, lexical_schema), .base = target_base, .id_depth = 0, .resource_depth = 0 };
            };
        }
        const canonical_href = try self.href(reference, base);
        const canonical = canonical_href[0 .. std.mem.indexOfScalar(u8, canonical_href, '#') orelse canonical_href.len];
        if (!std.mem.eql(u8, canonical, try self.buildBase(true))) {
            const remote = try self.contextProperty(canonical);
            defer self.engine.freeValue(remote);
            if (self.object(remote)) {
                if (resolution.retrieved) |frame| self.engine.freeValue(frame.root);
                resolution.retrieved = .{ .root = c.JS_DupValue(self.engine.context, remote), .base = canonical, .id_depth = 0, .resource_depth = 0 };
            }
        }
        if (try self.stringProperty(target, "$id") == null and !std.mem.eql(u8, canonical, try self.buildBase(true))) {
            const resource = try self.ref(self.root, base, canonical);
            defer self.engine.freeValue(resource);
            if (try self.stringProperty(resource, "$id") != null) {
                var active = false;
                for (self.ids.items) |id| active = active or c.JS_IsStrictEqual(self.engine.context, id, resource);
                if (!active) resolution.resource = c.JS_DupValue(self.engine.context, resource);
            }
        }
        return resolution;
    }
};
