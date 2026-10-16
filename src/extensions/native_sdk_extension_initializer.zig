//! Actual createExtension/initializeExtension/loadExtensionFromFactory bodies.
//! Transactional API construction is a required concrete import until assembled.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
const af = body.native;
pub const Inputs = struct { create_extension_api: c.JSValue, paths: c.JSValue, timing: c.JSValue };
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsFunction(engine.context, inputs.create_extension_api)) return error.RequiredActualTransactionalExtensionApi;
    const imports = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(imports, "createExtensionAPI", inputs.create_extension_api);
    try scope.put(imports, "dirname", try scope.get(inputs.paths, "dirname"));
    try scope.put(imports, "time", try scope.get(inputs.timing, "time"));
    try scope.put(imports, "sourceInfo", try scope.own(try @import("native_sdk_source_information.zig").create(engine)));
    const initializer = try scope.own(try af.createResumable(engine, "initializeExtension", 6, initialize, &.{imports}));
    const result = try scope.object();
    try scope.put(result, "loadExtensionFromFactory", try scope.own(try af.create(engine, "loadExtensionFromFactory", 4, fromFactory, &.{initializer})));
    return c.JS_DupValue(engine.context, result);
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
    try scope.put(result, "path", path);
    try scope.put(result, "resolvedPath", resolved);
    const options = try scope.object();
    try scope.put(options, "source", source);
    try scope.put(options, "baseDir", base);
    try scope.put(result, "sourceInfo", try scope.invoke(source_info, "createSyntheticSourceInfo", &.{ path, options }));
    inline for (.{ "handlers", "tools", "messageRenderers", "entryRenderers", "commands", "flags", "shortcuts" }) |name| try scope.put(result, name, try scope.own(try v.js.builtin(scope.engine, "Map", &.{})));
    return result;
}
fn fail(scope: *Scope, job: c.JSValue, reason: c.JSValue) !af.Action {
    _ = try scope.invoke(try scope.get(job, "load"), "discard", &.{});
    return .{ .thrown = c.JS_DupValue(scope.engine.context, reason) };
}
fn invokeFactory(scope: *Scope, factory: c.JSValue, load: c.JSValue) !c.JSValue {
    return scope.call(factory, c.pi_js_undefined(), &.{try scope.get(load, "api")});
}
fn initialize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    if (completion == .start) {
        const job = try body.init(&scope, state);
        try scope.put(job, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
        const value = try extension(&scope, roots[0], arg(args, 1), arg(args, 2));
        try scope.put(job, "extension", value);
        const load = try scope.call(try scope.get(roots[0], "createExtensionAPI"), c.pi_js_undefined(), &.{ value, arg(args, 5), arg(args, 3), arg(args, 4) });
        try scope.put(job, "load", load);
        const factory_result = invokeFactory(&scope, arg(args, 0), load) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = try scope.own(@import("native_agent_async.zig").reason(engine, err));
            return fail(&scope, job, reason);
        };
        return .{ .awaited = c.JS_DupValue(engine.context, factory_result) };
    }
    const job = state.*;
    if (completion == .rejected) {
        var boundary: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &boundary, try scope.get(job, "generation")) < 0) return v.js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, boundary);
        return fail(&scope, job, input);
    }
    // commit is inside Source's try, so a commit failure also discards.
    _ = scope.invoke(try scope.get(job, "load"), "commit", &.{}) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const reason = try scope.own(@import("native_agent_async.zig").reason(engine, err));
        return fail(&scope, job, reason);
    };
    const value = try scope.get(job, "extension");
    const label = try scope.concat(try scope.stringify(arg(args, 1)), try scope.text(" factory"));
    _ = try scope.call(try scope.get(roots[0], "time"), c.pi_js_undefined(), &.{ label, try scope.text("extensions") });
    return .{ .returned = c.JS_DupValue(engine.context, value) };
}
fn fromFactory(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = if (c.JS_IsUndefined(arg(args, 4))) try scope.text("<inline>") else arg(args, 4);
    const cwd = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, arg(args, 1), c.pi_js_undefined(), c.pi_js_undefined()));
    return v.js.call(engine, roots[0], c.pi_js_undefined(), &.{ arg(args, 0), path, path, cwd, arg(args, 2), arg(args, 3) });
}
