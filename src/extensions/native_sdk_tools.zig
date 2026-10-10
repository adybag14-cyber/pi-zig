//! Source builtin metadata and module-constant TypeBox schemas. The schema
//! owner is the Engine; selecting metadata never selects a session or its I/O.
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const vm = @import("native_values.zig");
pub const names = [_][]const u8{ "read", "bash", "powershell", "edit", "write", "grep", "find", "ls" };
const State = struct {
    source: std.json.Parsed(std.json.Value),
    parameters: [names.len]?c.JSValue = .{null} ** names.len,
    outputs: [names.len]?c.JSValue = .{null} ** names.len,

    fn destroy(self: *State, engine: *Engine) void {
        for (self.parameters) |value| if (value) |owned| engine.freeValue(owned);
        for (self.outputs) |value| if (value) |owned| engine.freeValue(owned);
        self.source.deinit();
        engine.gpa.destroy(self);
    }
};

pub fn deinit(engine: *Engine) void {
    engine.native_sdk_tools_cleanup = null;
    if (engine.native_sdk_tools_state) |opaque_state| {
        engine.native_sdk_tools_state = null;
        const state: *State = @ptrCast(@alignCast(opaque_state));
        state.destroy(engine);
    }
}

fn stateFor(engine: *Engine) !*State {
    if (engine.native_sdk_tools_state) |opaque_state| return @ptrCast(@alignCast(opaque_state));
    const state = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(state);
    state.* = .{ .source = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("native_sdk_builtin_templates_source.json"), .{}) };
    errdefer {
        for (state.parameters) |value| if (value) |owned| engine.freeValue(owned);
        for (state.outputs) |value| if (value) |owned| engine.freeValue(owned);
        state.source.deinit();
    }
    const types = try @import("typebox.zig").create(engine);
    defer engine.freeValue(types);
    for (state.source.value.array.items, 0..) |entry, index| {
        const metadata = entry.object.get("metadata").?;
        state.parameters[index] = try schema(engine, types, metadata.object.get("parameters").?);
        if (metadata.object.get("outputSchema")) |output| state.outputs[index] = try schema(engine, types, output);
    }
    engine.native_sdk_tools_state = state;
    engine.native_sdk_tools_cleanup = deinit;
    return state;
}

fn indexFor(name: []const u8) !usize {
    for (names, 0..) |candidate, index| if (std.mem.eql(u8, name, candidate)) return index;
    return error.UnknownBuiltinTool;
}

/// Returns an owned reference to the genuine shared module constant.
pub fn getParameters(engine: *Engine, name: []const u8) !c.JSValue {
    const index = try indexFor(name);
    return c.JS_DupValue(engine.context, (try stateFor(engine)).parameters[index].?);
}

pub fn getOutputSchema(engine: *Engine, name: []const u8) !c.JSValue {
    const index = try indexFor(name);
    return if ((try stateFor(engine)).outputs[index]) |value| c.JS_DupValue(engine.context, value) else c.pi_js_undefined();
}

/// Fresh factory metadata, with shared parameter/output schemas. Execution is
/// installed separately by the actual factory that retains its CWD and I/O.
pub fn getTemplate(engine: *Engine, name: []const u8) !c.JSValue {
    const index = try indexFor(name);
    const state = try stateFor(engine);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    var fields = state.source.value.array.items[index].object.get("metadata").?.object.iterator();
    while (fields.next()) |field| {
        const value = if (std.mem.eql(u8, field.key_ptr.*, "parameters"))
            c.JS_DupValue(engine.context, state.parameters[index].?)
        else if (std.mem.eql(u8, field.key_ptr.*, "outputSchema"))
            c.JS_DupValue(engine.context, state.outputs[index].?)
        else
            try engine.fromJsonValue(field.value_ptr.*);
        try putName(engine, result, field.key_ptr.*, value);
    }
    return result;
}

fn putName(engine: *Engine, target: c.JSValue, name: []const u8, value: c.JSValue) !void {
    const terminated = engine.gpa.dupeZ(u8, name) catch |err| {
        engine.freeValue(value);
        return err;
    };
    defer engine.gpa.free(terminated);
    try vm.put(engine, target, terminated, value);
}

fn requiredProperty(value: std.json.Value, name: []const u8) bool {
    const required = value.object.get("required") orelse return false;
    for (required.array.items) |entry| if (std.mem.eql(u8, entry.string, name)) return true;
    return false;
}

// Trusted Source-derived templates contain only these constructors. Calling
// native TypeBox preserves its hidden kind and optional markers recursively.
fn schema(engine: *Engine, types: c.JSValue, value: std.json.Value) anyerror!c.JSValue {
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    var fields = value.object.iterator();
    while (fields.next()) |field| {
        var structural = false;
        for ([_][]const u8{ "type", "required", "properties", "items", "anyOf", "const" }) |key| if (std.mem.eql(u8, key, field.key_ptr.*)) {
            structural = true;
            break;
        };
        if (!structural) try putName(engine, options, field.key_ptr.*, try engine.fromJsonValue(field.value_ptr.*));
    }
    if (value.object.get("const")) |literal| {
        const data = try engine.fromJsonValue(literal);
        defer engine.freeValue(data);
        return vm.invoke(engine, types, "Literal", &.{ data, options });
    }
    if (value.object.get("anyOf")) |alternatives| {
        const array = try vm.array(engine);
        defer engine.freeValue(array);
        for (alternatives.array.items, 0..) |alternative, index| {
            if (c.JS_SetPropertyUint32(engine.context, array, @intCast(index), try schema(engine, types, alternative)) < 0) return error.JavaScriptException;
        }
        return vm.invoke(engine, types, "Union", &.{ array, options });
    }
    const kind = value.object.get("type").?.string;
    if (std.mem.eql(u8, kind, "object")) {
        const properties = try vm.object(engine);
        defer engine.freeValue(properties);
        var children = value.object.get("properties").?.object.iterator();
        while (children.next()) |child| {
            const built = try schema(engine, types, child.value_ptr.*);
            defer engine.freeValue(built);
            const property = if (requiredProperty(value, child.key_ptr.*)) c.JS_DupValue(engine.context, built) else try vm.invoke(engine, types, "Optional", &.{built});
            try putName(engine, properties, child.key_ptr.*, property);
        }
        return vm.invoke(engine, types, "Object", &.{ properties, options });
    }
    if (std.mem.eql(u8, kind, "array")) {
        const items = try schema(engine, types, value.object.get("items").?);
        defer engine.freeValue(items);
        return vm.invoke(engine, types, "Array", &.{ items, options });
    }
    inline for (.{ .{ "string", "String" }, .{ "number", "Number" }, .{ "boolean", "Boolean" } }) |pair| {
        if (std.mem.eql(u8, kind, pair[0])) return vm.invoke(engine, types, pair[1], &.{options});
    }
    return error.UnsupportedBuiltinSchema;
}

test "canonical builtin schemas reproduce eight Source factory metadata templates and share genuine TypeBox constants" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const source = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("../durable/fixtures/sdk-builtin-templates-1ced.json"), .{});
    defer source.deinit();
    for (names, 0..) |name, index| {
        const template = try getTemplate(engine, name);
        defer engine.freeValue(template);
        const other = try getTemplate(engine, name);
        defer engine.freeValue(other);
        try std.testing.expect(!c.JS_IsStrictEqual(engine.context, template, other));
        const parameters = try vm.get(engine, template, "parameters");
        defer engine.freeValue(parameters);
        const parameters_again = try getParameters(engine, name);
        defer engine.freeValue(parameters_again);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, parameters, parameters_again));
        const kind = try vm.get(engine, parameters, "~kind");
        defer engine.freeValue(kind);
        const text = try engine.toString(kind);
        defer engine.gpa.free(text);
        try std.testing.expectEqualStrings("Object", text);
        const actual = try engine.stringify(template);
        defer engine.gpa.free(actual);
        const expected = try std.json.Stringify.valueAlloc(std.testing.allocator, source.value.array.items[index].object.get("metadata").?, .{});
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "canonical builtin schemas retain shared mutations and hidden nested TypeBox identity independently of template rows" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "readA", try getTemplate(engine, "read"));
    try vm.put(engine, global, "readB", try getTemplate(engine, "read"));
    try vm.put(engine, global, "editA", try getTemplate(engine, "edit"));
    const proof = try engine.eval(
        "if(readA===readB||readA.parameters!==readB.parameters||readA.outputSchema!==readB.outputSchema)throw Error('factory identity');" ++
            "if(readA.promptGuidelines===readB.promptGuidelines)throw Error('factory guidelines');" ++
            "const hidden=(x,k)=>Object.getOwnPropertyDescriptor(x,k)?.enumerable===false;" ++
            "if(!hidden(readA.parameters,'~kind')||!hidden(readA.parameters.properties.offset,'~optional')||readA.parameters.properties.path['~kind']!=='String'||editA.parameters.properties.edits.items['~kind']!=='Object'||editA.parameters.properties.edits['~kind']!=='Array')throw Error('genuine schemas');" ++
            "readA.parameters.properties.path.description='retained schema mutation';readA.promptGuidelines.push('local');readA.description='local';true",
        "builtin-template-identities.js",
        c.JS_EVAL_TYPE_GLOBAL,
    );
    defer engine.freeValue(proof);
    try vm.put(engine, global, "readC", try getTemplate(engine, "read"));
    const retained = try engine.eval("if(readC.parameters.properties.path.description!=='retained schema mutation'||readC.description==='local'||readC.promptGuidelines.includes('local'))throw Error('constant ownership');true", "builtin-template-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
}

test "canonical builtin schemas and factory templates unwind every admitted host allocation before atomic publication" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                return err;
            };
        }
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try Engine.init(gpa, .{});
            defer engine.deinit();
            for (names) |name| {
                const row = try getTemplate(engine, name);
                engine.freeValue(row);
                const parameters = try getParameters(engine, name);
                engine.freeValue(parameters);
                const output = try getOutputSchema(engine, name);
                engine.freeValue(output);
            }
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
