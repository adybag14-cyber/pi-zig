//! Explicit immutable publication of the actual public child + canonical net
//! graph. No Engine bootstrap selection, forwarding module or legacy overwrite.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_socket_scope.zig").Scope;
const fnc = @import("native_child_process_function.zig");
pub const State = struct {
    phase: enum { ready, publishing, published, failed } = .ready,
    reason: ?c.JSValue = null,
    failure: ?anyerror = null,
    pub fn mark(self: State, runtime: ?*c.JSRuntime, visitor: ?*const c.JS_MarkFunc) void { if (self.reason) |value| c.JS_MarkValue(runtime, value, visitor); }
    pub fn deinit(self: State, runtime: ?*c.JSRuntime) void { if (self.reason) |value| c.JS_FreeValueRT(runtime, value); }
};
fn existing(scope: *Scope, name: []const u8, carrier: c.JSValue) !bool {
    const engine = scope.engine;
    if (engine.modules.contains(name)) return error.NativeChildBuiltinSourceConflict;
    const actual = engine.native_builtin_aliases.get(name) orelse name;
    const canonical_name: ?[]const u8 = if (std.mem.eql(u8, name, "net")) "node:net" else if (std.mem.eql(u8, name, "child_process")) "node:child_process" else null;
    if (canonical_name) |expected| {
        if (engine.native_builtin_aliases.contains(name)) {
            if (!std.mem.eql(u8, actual, expected)) return error.NativeChildBuiltinAliasInvalid;
        } else if (engine.native_module_names.contains(name)) {
            // A separate bare C module can freeze different named exports even
            // with the same .default. Never silently admit it as the alias.
            return error.NativeChildBuiltinBareModuleConflict;
        }
    }
    if (!engine.native_module_names.contains(actual)) {
        if (engine.native_builtin_aliases.contains(name)) return error.NativeChildBuiltinAliasInvalid;
        return false;
    }
    const record = engine.native_module_values.get(actual) orelse return error.NativeChildBuiltinRecordMissing;
    if (!scope.equal(try scope.get(record, "default"), carrier)) return error.NativeChildBuiltinCarrierMismatch;
    return true;
}
fn defaultRecord(scope: *Scope, carrier: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const record = try scope.object();
    var properties: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    const status = c.JS_GetOwnPropertyNames(engine.context, &properties, &count, carrier, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY);
    if (status < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    try engine.checkNativeEntry();
    for (properties[0..count]) |property| {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        const generation = engine.native_allocation_generation;
        const value = try row.ownSince(c.JS_GetProperty(engine.context, carrier, property.atom), generation);
        const defined = c.JS_DefinePropertyValue(engine.context, record, property.atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E);
        try engine.checkNativeEntry(); if (defined < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    }
    try scope.put(record, "default", carrier);
    return record;
}
fn perform(engine: *js.Engine, state: *State, node: c.JSValue, net: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (state.phase == .failed) {
        if (state.reason) |reason| { _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)); return error.JavaScriptException; }
        return state.failure orelse error.NativeChildBuiltinPublicationFailed;
    }
    if (state.phase == .publishing) return error.NativeChildBuiltinPublicationInProgress;
    const was_published = state.phase == .published;
    // Guard BEFORE the first live default/export getter. A getter can reenter
    // the actual host installer; it must not begin a second transaction.
    state.phase = .publishing;
    const names = [_][]const u8{ "node:net", "net", "node:child_process", "child_process" };
    const carriers = [_]c.JSValue{ net, net, node, node };
    var present: [4]bool = undefined;
    for (names, carriers, &present) |name, carrier, *found| found.* = try existing(&scope, name, carrier);
    if (was_published) {
        for (present) |found| if (!found) return error.NativeChildBuiltinRegistrationChanged;
        state.phase = .published;
        return;
    }
    const net_record = if (present[0]) c.pi_js_undefined() else try defaultRecord(&scope, net);
    const node_record = if (present[2]) c.pi_js_undefined() else try defaultRecord(&scope, node);
    // Live export getters may have registered a competing genuine module.
    for (names, carriers, present) |name, carrier, before| if (try existing(&scope, name, carrier) != before) return error.NativeChildBuiltinRegistrationChanged;
    state.phase = .publishing;
    if (!present[0]) { try engine.registerValueModule("node:net", net_record); try engine.checkNativeEntry(); }
    if (!present[1]) { try engine.registerBuiltinAlias("net", "node:net"); try engine.checkNativeEntry(); }
    if (!present[2]) { try engine.registerValueModule("node:child_process", node_record); try engine.checkNativeEntry(); }
    if (!present[3]) { try engine.registerBuiltinAlias("child_process", "node:child_process"); try engine.checkNativeEntry(); }
    state.phase = .published;
}
/// Engine must contain RootBfb + the independently reviewed genuine builtin
/// alias primitive. This unit imports neither an old Engine nor a shared patch.
pub fn install(engine: *js.Engine, state: *State, node: c.JSValue, net: c.JSValue) !void {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    // A rejected nested entry never owns/mutates the outer transaction's
    // sticky status. Its live getter can handle this ordinary rejection.
    if (state.phase == .publishing) return error.NativeChildBuiltinPublicationInProgress;
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const generation = engine.native_allocation_generation;
    var failure: ?anyerror = null;
    perform(engine, state, node, net) catch |err| { failure = fnc.directFailure(engine, err, generation); };
    _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |err| { failure = err; };
    if (failure) |err| {
        // C-module side effects are immutable. Retain the actual selected reason
        // and graph; no rollback fiction or retry after partial publication.
        if (state.phase != .failed) {
            state.phase = .failed; state.failure = err;
            if (err == error.JavaScriptException) {
                if (engine.captured_exception) |reason| state.reason = c.JS_DupValue(engine.context, reason);
            }
        }
        return @as(anyerror!void, err);
    }
}

test "publication registry preserves actual carrier records and refuses a conflicting carrier" {
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var state: State = .{}; defer state.deinit(engine.runtime);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const net = try scope.object(); const node = try scope.object();
    // Registry-only control uses plain real VM carrier objects. It does not
    // stand in for a Socket, process backend or physical child qualification.
    try install(engine, &state, node, net);
    const net_record = engine.native_module_values.get("node:net").?;
    try install(engine, &state, node, net);
    try std.testing.expect(scope.equal(net_record, engine.native_module_values.get("node:net").?));
    try std.testing.expectEqualStrings("node:net", engine.native_builtin_aliases.get("net").?);
    try std.testing.expectEqualStrings("node:child_process", engine.native_builtin_aliases.get("child_process").?);
    try std.testing.expect(scope.equal(try scope.get(net_record, "default"), net));
    var other: State = .{}; defer other.deinit(engine.runtime);
    try std.testing.expectError(error.NativeChildBuiltinCarrierMismatch, install(engine, &other, node, try scope.object()));
    try std.testing.expect(scope.equal(net_record, engine.native_module_values.get("node:net").?));
}

test "actual canonical Socket export getter cannot recursively publish the same child transaction" {
    const Fixture = struct {
        engine: *js.Engine, state: *State, calls: usize = 0, rejected: usize = 0,
        fn getter(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const self: *@This() = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
            self.calls += 1;
            install(engine, self.state, roots[2], roots[1]) catch |err| {
                if (err != error.NativeChildBuiltinPublicationInProgress) return @as(anyerror!c.JSValue, err);
                self.rejected += 1; return c.JS_DupValue(engine.context, roots[3]);
            };
            return error.PublicationControlNestedEntryWasAdmitted;
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{});
    const process = (try engine.requireBuiltin("node:process")).?; defer engine.freeValue(process);
    try @import("native_node_stream.zig").install(engine, process);
    const streams = (try engine.requireBuiltin("node:stream")).?; defer engine.freeValue(streams);
    const shared = try @import("native_node_net_socket_provider.zig").acquire(engine, streams, process);
    var state: State = .{}; defer state.deinit(engine.runtime);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const node = try scope.object(); // Registry test carrier, no fake child.
    var fixture: Fixture = .{ .engine = engine, .state = &state };
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual publication reentry control context" };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const context = try scope.own(c.JS_NewObjectClass(engine.context, id)); _ = c.JS_SetOpaque(context, &fixture);
    const original = try scope.get(shared.net, "Socket");
    const getter = try scope.own(try fnc.createMethod(engine, "get Socket", 0, Fixture.getter, &.{context, shared.net, node, original}));
    const atom = c.JS_NewAtom(engine.context, "Socket"); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, shared.net, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    defer {
        if (c.JS_DefinePropertyValueStr(engine.context, shared.net, "Socket", c.JS_DupValue(engine.context, original), c.JS_PROP_C_W_E) < 0) @panic("owned publication control failed to restore genuine Socket export");
    }
    try install(engine, &state, node, shared.net);
    try install(engine, &state, node, shared.net);
    try std.testing.expectEqual(@as(usize, 1), fixture.calls);
    try std.testing.expectEqual(@as(usize, 1), fixture.rejected);
    try std.testing.expect(state.phase == .published);
    try std.testing.expect(scope.equal(try scope.get(engine.native_module_values.get("node:net").?, "Socket"), original));
}

test "same default under wrong native alias target or standalone bare module is not canonical" {
    for ([_]bool{ false, true }) |bare_module| {
        const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var state: State = .{}; defer state.deinit(engine.runtime);
        var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        const carrier = try scope.object(); const node = try scope.object();
        const record = try scope.object(); try scope.put(record, "default", carrier); try scope.put(record, "differentNamedExport", c.JS_NewInt32(engine.context, 1));
        if (bare_module) try engine.registerValueModule("net", record) else {
            try engine.registerValueModule("node:other", record);
            // A genuine owned host registry mutation supplies an invalid prior
            // alias. The public alias API itself correctly refuses this shape.
            var transferred = false;
            const alias = try engine.gpa.dupe(u8, "net"); errdefer if (!transferred) engine.gpa.free(alias);
            const target = try engine.gpa.dupe(u8, "node:other"); errdefer if (!transferred) engine.gpa.free(target);
            try engine.native_builtin_aliases.put(engine.gpa, alias, target);
            transferred = true;
        }
        try std.testing.expectError(if (bare_module) error.NativeChildBuiltinBareModuleConflict else error.NativeChildBuiltinAliasInvalid, install(engine, &state, node, carrier));
        try std.testing.expect(!engine.native_module_names.contains("node:net"));
        try std.testing.expect(!engine.native_module_names.contains("node:child_process"));
    }
}
