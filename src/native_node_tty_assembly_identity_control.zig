//! Prepared host control. The caller supplies the actual canonical module
//! composition and real bootstrap/frontend inputs; no compatible fake types.
//! Not an independently runnable target and not an executed test result.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const h = @import("extensions/native_node_tty_values.zig");
pub fn run(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, publish: bool) !void {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    const first = try ActualAssembly.create(engine, actual); defer first.deinit(engine);
    const second = try ActualAssembly.create(engine, actual); defer second.deinit(engine);
    inline for (std.meta.fields(ActualAssembly.Exports)) |field| try std.testing.expect(c.JS_IsStrictEqual(engine.context, @field(first, field.name), @field(second, field.name)));
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    inline for (.{ .{ first.tty, first.tty_exports }, .{ first.util, first.util_exports }, .{ first.readline, first.readline_exports }, .{ first.net, first.net_exports } }) |pair| {
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, pair[0], try h.get(&s, pair[1], "default")));
    }
    inline for (.{ "inspect", "format" }) |name| try std.testing.expect(c.JS_IsStrictEqual(engine.context, try h.get(&s, first.util, name), try h.get(&s, first.internal_inspect, name)));
    const socket_prototype = try h.get(&s, actual.canonical_socket.constructor, "prototype");
    inline for (.{ "ReadStream", "WriteStream" }) |name| {
        const constructor = try h.get(&s, first.tty, name);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, constructor, try h.get(&s, first.tty_exports, name)));
        const parent = try s.own(try h.success(engine, try engine.checked(c.JS_GetPrototype(engine.context, constructor))));
        const prototype = try h.get(&s, constructor, "prototype");
        const prototype_parent = try s.own(try h.success(engine, try engine.checked(c.JS_GetPrototype(engine.context, prototype))));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, parent, actual.canonical_socket.constructor));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, prototype_parent, socket_prototype));
    }
    if (publish) {
        const installed = try ActualAssembly.install(engine, actual); defer installed.deinit(engine);
        const installed_again = try ActualAssembly.install(engine, actual); defer installed_again.deinit(engine);
        inline for (std.meta.fields(ActualAssembly.Exports)) |field| try std.testing.expect(c.JS_IsStrictEqual(engine.context, @field(first, field.name), @field(installed_again, field.name)));
        inline for (.{ .{ "node:tty", "tty", first.tty }, .{ "node:util", "util", first.util }, .{ "node:readline", "readline", first.readline }, .{ "node:net", "net", first.net } }) |entry| {
            const prefixed = (try engine.requireBuiltin(entry[0])) orelse return error.MissingActualTtyBuiltin; defer engine.freeValue(prefixed);
            const bare = (try engine.requireBuiltin(entry[1])) orelse return error.MissingActualTtyBuiltin; defer engine.freeValue(bare);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, prefixed, entry[2]));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, bare, entry[2]));
        }
        const filename = try engine.toString(actual.physical_filename); defer engine.gpa.free(filename);
        const terminated = try engine.gpa.dupeZ(u8, filename); defer engine.gpa.free(terminated);
        const namespace = try s.own(try h.success(engine, try engine.evalModule(@embedFile("extensions/fixtures/node-tty-original-alias-identity.mjs"), terminated)));
        inline for (.{ "namespaces", "defaults", "requires", "constructors" }) |name| try std.testing.expect(c.JS_ToBool(engine.context, try h.get(&s, namespace, name)) == 1);
    }
}

/// Each invocation requires a FRESH actual Engine/composition. This changes
/// only a genuine net carrier's Socket descriptor and restores it exactly.
/// A real getter reenters the initializing assembly, or throws its owned reason
/// before native admission. Successful retry uses the original constructors.
pub fn initializationBoundary(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, throw_first: bool) !void {
    const Control = struct {
        const State = struct { engine: *v.em.Engine, inputs: ActualAssembly.Inputs, reason: c.JSValue, throwing: bool, calls: usize = 0, reentries: usize = 0 };
        var active: ?*State = null;
        fn getter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?;
            std.debug.assert(state.engine.context == context);
            state.calls += 1;
            if (state.throwing) return c.JS_Throw(context, c.JS_DupValue(context, state.reason));
            const unexpected = ActualAssembly.create(state.engine, state.inputs) catch |err| {
                if (err != error.ActualTtyAssemblyInitializing) return c.JS_ThrowInternalError(context, "Unexpected assembly reentry error");
                state.reentries += 1;
                return c.JS_DupValue(context, state.inputs.canonical_socket.constructor);
            };
            unexpected.deinit(state.engine);
            return c.JS_ThrowInternalError(context, "Initializing assembly was exposed");
        }
    };
    try std.testing.expect(Control.active == null);
    const atom = c.JS_NewAtom(engine.context, "Socket"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var original: c.JSPropertyDescriptor = undefined;
    try std.testing.expect(c.JS_GetOwnProperty(engine.context, &original, actual.actual_net, atom) == 1);
    defer { engine.freeValue(original.value); engine.freeValue(original.getter); engine.freeValue(original.setter); }
    defer {
        const flags = (original.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
            (if (original.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
        std.debug.assert(c.JS_DefineProperty(engine.context, actual.actual_net, atom, original.value, original.getter, original.setter, flags | c.JS_PROP_THROW) >= 0);
    }
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    var state: Control.State = .{ .engine = engine, .inputs = actual, .reason = reason, .throwing = throw_first };
    Control.active = &state; defer Control.active = null;
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, Control.getter, "actualAssemblyBoundary", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, actual.actual_net, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    if (throw_first) {
        const unexpected = ActualAssembly.create(engine, actual) catch |err| {
            try std.testing.expect(err == error.JavaScriptException);
            const caught = engine.captured_exception orelse return error.MissingActualAssemblyReason;
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, caught, reason));
            engine.captured_exception = null; engine.freeValue(caught);
            try std.testing.expect(!c.JS_HasException(engine.context));
            state.throwing = false;
            const retried = try ActualAssembly.create(engine, actual); defer retried.deinit(engine);
            try std.testing.expect(state.reentries != 0);
            return;
        };
        unexpected.deinit(engine); return error.ExpectedActualAssemblyGetterFailure;
    }
    const exports = try ActualAssembly.create(engine, actual); defer exports.deinit(engine);
    try std.testing.expect(state.calls != 0 and state.reentries == state.calls);
}
