//! Actual createExtension/initializeExtension/loadExtensionFromFactory bodies.
//! Transactional API construction is a required concrete import until assembled.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
const af = body.native;
fn put(scope: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try v.js.define(scope.engine, target, name, c.JS_DupValue(scope.engine.context, value));
}
pub const Inputs = struct { create_extension_api: c.JSValue, paths: c.JSValue, timing: c.JSValue };
/// Both values are owned. The internal binding is available to the real loader
/// assembler without exposing a new property on the Source public namespace.
pub const Graph = struct { namespace: c.JSValue, initialize_extension: c.JSValue };
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const graph = try createGraph(engine, inputs);
    engine.freeValue(graph.initialize_extension);
    return graph.namespace;
}
pub fn createGraph(engine: *v.em.Engine, inputs: Inputs) !Graph {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsFunction(engine.context, inputs.create_extension_api)) return error.RequiredActualTransactionalExtensionApi;
    const imports = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try put(&scope, imports, "createExtensionAPI", inputs.create_extension_api);
    try put(&scope, imports, "dirname", try scope.get(inputs.paths, "dirname"));
    try put(&scope, imports, "time", try scope.get(inputs.timing, "time"));
    try put(&scope, imports, "sourceInfo", try scope.own(try @import("native_sdk_source_information.zig").create(engine)));
    const initializer = try scope.own(try af.createResumable(engine, "initializeExtension", 6, initialize, &.{imports}));
    const result = try scope.object();
    try put(&scope, result, "loadExtensionFromFactory", try scope.own(try af.create(engine, "loadExtensionFromFactory", 4, fromFactory, &.{initializer})));
    return .{ .namespace = c.JS_DupValue(engine.context, result), .initialize_extension = c.JS_DupValue(engine.context, initializer) };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn extension(scope: *Scope, imports: c.JSValue, path: c.JSValue, resolved: c.JSValue) !c.JSValue {
    const source_info = try scope.get(imports, "sourceInfo");
    const supplied_source = try scope.invoke(source_info, "getSyntheticPathSource", &.{path});
    const source = if (v.nullish(supplied_source)) try scope.text("local") else supplied_source;
    const base = if (scope.truthy(try scope.invoke(source_info, "isSyntheticPath", &.{path}))) c.pi_js_undefined() else try scope.call(try scope.get(imports, "dirname"), c.pi_js_undefined(), &.{resolved});
    const result = try scope.object();
    try put(scope, result, "path", path);
    try put(scope, result, "resolvedPath", resolved);
    const options = try scope.object();
    try put(scope, options, "source", source);
    try put(scope, options, "baseDir", base);
    try put(scope, result, "sourceInfo", try scope.invoke(source_info, "createSyntheticSourceInfo", &.{ path, options }));
    inline for (.{ "handlers", "tools", "messageRenderers", "entryRenderers", "commands", "flags", "shortcuts" }) |name| try put(scope, result, name, try scope.own(try v.js.builtin(scope.engine, "Map", &.{})));
    return result;
}
fn fail(scope: *Scope, job: c.JSValue, reason: c.JSValue) !af.Action {
    _ = try scope.invoke(try scope.get(job, "load"), "discard", &.{});
    return .{ .thrown = c.JS_DupValue(scope.engine.context, reason) };
}
fn invokeFactory(scope: *Scope, factory: c.JSValue, load: c.JSValue) !c.JSValue {
    return scope.call(factory, c.pi_js_undefined(), &.{try scope.get(load, "api")});
}
fn trustedBoundary(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        // Mark/rethrow the exact fresh private reason before classification can
        // turn it into a host error union and allocate a replacement reason.
        try body.rethrowRecognizedAllocation(engine, reason, generation);
    };
}
fn takeReason(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    try trustedBoundary(engine, err, generation);
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingExtensionInitializerReason;
    engine.captured_exception = null;
    return reason;
}
fn initialize(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const generation = engine.native_allocation_generation;
    return initializeBody(engine, receiver, args, roots, state, completion, input) catch |err| {
        try trustedBoundary(engine, err, generation);
        if (err == error.JavaScriptException) return .{ .thrown = try takeReason(engine, err, generation) };
        return body.failureSince(engine, err, generation);
    };
}
fn initializeBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    if (completion == .start) {
        const job = try body.init(&scope, state);
        try put(&scope, job, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
        const value = try extension(&scope, roots[0], arg(args, 1), arg(args, 2));
        try put(&scope, job, "extension", value);
        const load = try scope.call(try scope.get(roots[0], "createExtensionAPI"), c.pi_js_undefined(), &.{ value, arg(args, 5), arg(args, 3), arg(args, 4) });
        try put(&scope, job, "load", load);
        const factory_result = invokeFactory(&scope, arg(args, 0), load) catch |err| {
            try trustedBoundary(engine, err, generation);
            const reason = try scope.own(try takeReason(engine, err, generation));
            return fail(&scope, job, reason);
        };
        return .{ .awaited = c.JS_DupValue(engine.context, factory_result) };
    }
    const job = state.*;
    if (completion == .rejected) {
        if (c.JS_IsUncatchableError(input)) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, input)));
            unreachable;
        }
        var boundary: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &boundary, try scope.get(job, "generation")) < 0) return v.js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, boundary);
        return fail(&scope, job, input);
    }
    // commit is inside Source's try, so a commit failure also discards.
    _ = scope.invoke(try scope.get(job, "load"), "commit", &.{}) catch |err| {
        try trustedBoundary(engine, err, generation);
        const reason = try scope.own(try takeReason(engine, err, generation));
        return fail(&scope, job, reason);
    };
    const value = try scope.get(job, "extension");
    const label = try scope.concat(try scope.stringify(arg(args, 1)), try scope.text(" factory"));
    _ = try scope.call(try scope.get(roots[0], "time"), c.pi_js_undefined(), &.{ label, try scope.text("extensions") });
    return .{ .returned = c.JS_DupValue(engine.context, value) };
}
fn fromFactory(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return fromFactoryBody(engine, receiver, args, roots) catch |err| {
        try trustedBoundary(engine, err, generation);
        return err;
    };
}
fn fromFactoryBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = if (c.JS_IsUndefined(arg(args, 4))) try scope.text("<inline>") else arg(args, 4);
    const cwd = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, arg(args, 1), c.pi_js_undefined(), c.pi_js_undefined()));
    return v.js.call(engine, roots[0], c.pi_js_undefined(), &.{ arg(args, 0), path, path, cwd, arg(args, 2), arg(args, 3) });
}
