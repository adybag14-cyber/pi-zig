//! Source loader.ts551–733 orchestration. Real lazy module imports are required
//! bindings, not a fabricated jiti object or an empty virtual module registry.
//! Graph2/default-interop composition and production selection remain separate.
//! Local revision2: rejected Await DATA is distinct from a current VM event.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
const af = body.native;
const cache = @import("native_sdk_extension_cache.zig");
const Captures = struct {
    engine: *v.em.Engine,
    prior: ?c.JSValue,
    fn enter(engine: *v.em.Engine) Captures {
        const previous = engine.captured_exception;
        engine.captured_exception = null;
        return .{ .engine = engine, .prior = previous };
    }
    fn deinit(self: *Captures) void {
        if (self.engine.captured_exception == null) self.engine.captured_exception = self.prior else if (self.prior) |reason| self.engine.freeValue(reason);
        self.prior = null;
    }
};
pub const Inputs = struct {
    initializer: @import("native_sdk_extension_initializer.zig").Inputs,
    /// Actual original lazy getCreateJiti; must resolve the real createJiti.
    get_create_jiti: c.JSValue,
    /// Actual lazy import of the namespace from extension_virtual_modules.evaluate.
    /// Construction must not invoke it; its real importer owns module identity.
    import_virtual_module: c.JSValue,
    get_aliases: c.JSValue,
    loader_module_url: c.JSValue,
    uses_embedded_modules: bool,
    is_typescript_source_runtime: bool,
};
const Stage = enum(i32) { create_jiti, virtual_modules, imported, factory, initialized, iteration };
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue { return if (i < args.len) args[i] else c.pi_js_undefined(); }
fn wait(s: *Scope, job: c.JSValue, stage: Stage, value: c.JSValue) !af.Action {
    try put(s.engine, job, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(stage)));
    return .{ .awaited = c.JS_DupValue(s.engine.context, value) };
}
fn boundary(s: *Scope, job: c.JSValue) !void {
    try put(s.engine, job, "generation", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, s.engine.native_allocation_generation))));
}
fn stage(s: *Scope, job: c.JSValue) !Stage {
    var value: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &value, try s.get(job, "stage")) < 0) return v.js.capture(s.engine);
    return @enumFromInt(value);
}
fn trusted(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) {
        // A still-pending actual event is normalized before consulting this
        // invocation's new capture. The prior diagnostic slot is isolated.
        if (c.JS_HasException(engine.context)) {
            const capture_error = v.js.capture(engine);
            if (capture_error != error.JavaScriptException) return capture_error;
        }
        const reason = engine.captured_exception orelse return error.MissingExtensionLoaderCurrentCapturedReason;
        if (c.JS_IsUncatchableError(reason)) return err;
        try body.rethrowRecognizedAllocation(engine, reason, generation);
    }
}
fn take(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    try trusted(engine, err, generation);
    if (err != error.JavaScriptException) return err;
    // Local helpers capture their pending exception at its actual boundary.
    const reason = engine.captured_exception orelse return error.MissingExtensionLoaderReason;
    engine.captured_exception = null;
    return reason;
}
fn failure(engine: *v.em.Engine, err: anyerror, generation: u64) !af.Action {
    if (err == error.JavaScriptException) return .{ .thrown = try take(engine, err, generation) };
    try trusted(engine, err, generation);
    return body.failureSince(engine, err, generation);
}
fn reject(s: *Scope, job: c.JSValue, reason: c.JSValue) !void {
    if (c.JS_HasException(s.engine.context)) return v.js.capture(s.engine);
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(s.engine.context, &generation, try s.get(job, "generation")) < 0) return v.js.capture(s.engine);
    try body.rethrowRecognizedAllocation(s.engine, reason, generation);
    if (c.JS_HasException(s.engine.context)) return v.js.capture(s.engine);
    // No active VM event or exact fresh private allocation cause exists.
    // This is rejected DATA, even when it has a historical hidden fatal bit.
    // C2 Action.THROW would otherwise reinterpret that old bit as a new event.
    // Source catch formatting/IteratorClose also receives the SAME raw object.
    c.JS_ClearUncatchableError(s.engine.context, reason);
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(imports, name), c.pi_js_undefined(), args);
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    inline for (.{ inputs.get_create_jiti, inputs.import_virtual_module, inputs.get_aliases }) |value| if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualExtensionModuleImports;
    if (!c.JS_IsString(inputs.loader_module_url)) return error.RequiredPhysicalExtensionLoaderUrl;
    const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try put(engine, imports, "getCreateJiti", inputs.get_create_jiti);
    try put(engine, imports, "getVirtualModules", try s.own(try @import("native_sdk_extension_virtual_modules.zig").createLazy(engine, inputs.import_virtual_module)));
    try put(engine, imports, "getAliases", inputs.get_aliases);
    try put(engine, imports, "url", inputs.loader_module_url);
    try put(engine, imports, "embedded", c.pi_js_bool(engine.context, @intFromBool(inputs.uses_embedded_modules)));
    try put(engine, imports, "typescript", c.pi_js_bool(engine.context, @intFromBool(inputs.is_typescript_source_runtime)));
    try put(engine, imports, "time", try s.get(inputs.initializer.timing, "time"));
    const initializer = try @import("native_sdk_extension_initializer.zig").createGraph(engine, inputs.initializer);
    defer engine.freeValue(initializer.namespace);
    defer engine.freeValue(initializer.initialize_extension);
    try put(engine, imports, "initializeExtension", initializer.initialize_extension);
    try put(engine, imports, "loadExtensionModule", try s.own(try af.createResumable(engine, "loadExtensionModule", 2, moduleBody, &.{imports})));
    try put(engine, imports, "loadExtension", try s.own(try af.createResumable(engine, "loadExtension", 5, extensionBody, &.{imports})));
    try put(engine, imports, "loadExtensionsInternal", try s.own(try af.createResumable(engine, "loadExtensionsInternal", 4, internalBody, &.{imports})));
    const result = try s.object();
    try put(engine, result, "clearExtensionCache", try s.own(try cache.createClear(engine)));
    try put(engine, result, "loadExtensionFromFactory", try s.get(initializer.namespace, "loadExtensionFromFactory"));
    try put(engine, result, "loadExtensions", try s.own(try af.create(engine, "loadExtensions", 4, publicLoad, &.{ imports, c.pi_js_bool(engine.context, 0) })));
    try put(engine, result, "loadExtensionsCached", try s.own(try af.create(engine, "loadExtensionsCached", 4, publicLoad, &.{ imports, c.pi_js_bool(engine.context, 1) })));
    return c.JS_DupValue(engine.context, result);
}
fn publicLoad(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // Source return-expression adoption, with no additional Await.
    const function = try v.js.get(engine, roots[0], "loadExtensionsInternal");
    defer engine.freeValue(function);
    return v.js.call(engine, function, c.pi_js_undefined(), &.{ arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3), roots[1] });
}
fn moduleBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var captures = Captures.enter(engine); defer captures.deinit();
    // The qualified AF trampoline suppresses diagnostics before this private
    // callback. An execution-context hook may already have left a real event.
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    return moduleInner(engine, args, roots[0], state, completion, input) catch |err| return failure(engine, err, generation);
}
fn moduleInner(engine: *v.em.Engine, args: []const c.JSValue, imports: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try boundary(&s, job);
        const cached = try s.own(try cache.lookup(engine, arg(args, 0), arg(args, 1)));
        if (s.truthy(cached)) return .{ .returned = c.JS_DupValue(engine.context, cached) };
        return wait(&s, job, .create_jiti, try imported(&s, imports, "getCreateJiti", &.{}));
    }
    const job = state.*;
    if (completion == .rejected) { try reject(&s, job, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    try boundary(&s, job);
    switch (try stage(&s, job)) {
        .create_jiti => {
            try put(engine, job, "createJiti", input);
            if (s.truthy(try s.get(imports, "embedded")) or s.truthy(try s.get(imports, "typescript"))) return wait(&s, job, .virtual_modules, try imported(&s, imports, "getVirtualModules", &.{}));
            const options = try s.object();
            try put(engine, options, "alias", try imported(&s, imports, "getAliases", &.{}));
            return importModule(&s, job, imports, arg(args, 0), options);
        },
        .virtual_modules => {
            const options = try s.object();
            try put(engine, options, "virtualModules", input);
            if (s.truthy(try s.get(imports, "embedded"))) try put(engine, options, "tryNative", c.pi_js_bool(engine.context, 0)) else try put(engine, options, "tsconfigPaths", c.pi_js_bool(engine.context, 1));
            return importModule(&s, job, imports, arg(args, 0), options);
        },
        .imported => {
            if (!c.JS_IsFunction(engine.context, input)) return .{ .returned = c.pi_js_undefined() };
            try cache.remember(engine, arg(args, 0), input, arg(args, 1));
            return .{ .returned = c.JS_DupValue(engine.context, input) };
        },
        else => return error.InvalidExtensionModuleStage,
    }
}
fn importModule(s: *Scope, job: c.JSValue, imports: c.JSValue, path: c.JSValue, resolution: c.JSValue) !af.Action {
    const options = try s.object();
    try put(s.engine, options, "moduleCache", c.pi_js_bool(s.engine.context, 0));
    try v.js.spreadInto(s.engine, options, resolution);
    const jiti = try s.call(try s.get(job, "createJiti"), c.pi_js_undefined(), &.{ try s.get(imports, "url"), options });
    const function = try s.get(jiti, "import");
    const import_options = try s.object();
    try put(s.engine, import_options, "default", c.pi_js_bool(s.engine.context, 1));
    return wait(s, job, .imported, try s.call(function, jiti, &.{ path, import_options }));
}
fn errorResult(s: *Scope, message: c.JSValue) !af.Action {
    const result = try s.object();
    try put(s.engine, result, "extension", c.JS_NULL);
    try put(s.engine, result, "error", message);
    return .{ .returned = c.JS_DupValue(s.engine.context, result) };
}
fn caught(s: *Scope, reason: c.JSValue) !af.Action {
    const error_ctor = try s.global("Error");
    const instance = c.JS_IsInstanceOf(s.engine.context, reason, error_ctor);
    if (instance < 0) return v.js.capture(s.engine);
    const message = if (instance == 1) try s.get(reason, "message") else try s.call(try s.global("String"), c.pi_js_undefined(), &.{reason});
    return errorResult(s, try s.concat(try s.text("Failed to load extension: "), try s.stringify(message)));
}
fn extensionBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var captures = Captures.enter(engine); defer captures.deinit();
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    return extensionInner(engine, args, roots[0], state, completion, input) catch |err| {
        try trusted(engine, err, generation);
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        if (err == error.JavaScriptException) {
            const reason = try s.own(try take(engine, err, generation));
            if (c.JS_IsObject(state.*) and s.truthy(try s.get(state.*, "inTry"))) {
                // Source's catch formatter is outside the protected try.
                try put(engine, state.*, "inTry", c.pi_js_bool(engine.context, 0));
                return caught(&s, reason);
            }
            return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        }
        return failure(engine, err, generation);
    };
}
fn extensionInner(engine: *v.em.Engine, args: []const c.JSValue, imports: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try boundary(&s, job);
        const options = try s.object();
        try put(engine, options, "normalizeUnicodeSpaces", c.pi_js_bool(engine.context, 1));
        const resolved = try s.own(try @import("native_sdk_source_paths.zig").resolve(engine, arg(args, 0), arg(args, 1), options));
        try put(engine, job, "resolvedPath", resolved);
        try put(engine, job, "inTry", c.pi_js_bool(engine.context, 1));
        return wait(&s, job, .factory, try imported(&s, imports, "loadExtensionModule", &.{ resolved, arg(args, 4) }));
    }
    const job = state.*;
    if (completion == .rejected) {
        try reject(&s, job, input);
        try put(engine, job, "inTry", c.pi_js_bool(engine.context, 0));
        return caught(&s, input);
    }
    try boundary(&s, job);
    switch (try stage(&s, job)) {
        .factory => {
            _ = try imported(&s, imports, "time", &.{ try s.concat(try s.stringify(arg(args, 0)), try s.text(" module import")), try s.text("extensions") });
            if (!s.truthy(input)) return errorResult(&s, try s.concat(try s.text("Extension does not export a valid factory function: "), try s.stringify(arg(args, 0))));
            return wait(&s, job, .initialized, try imported(&s, imports, "initializeExtension", &.{ input, arg(args, 0), try s.get(job, "resolvedPath"), arg(args, 1), arg(args, 2), arg(args, 3) }));
        },
        .initialized => {
            const result = try s.object();
            try put(engine, result, "extension", input);
            try put(engine, result, "error", c.JS_NULL);
            return .{ .returned = c.JS_DupValue(engine.context, result) };
        },
        else => return error.InvalidExtensionLoadStage,
    }
}
fn internalBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var captures = Captures.enter(engine); defer captures.deinit();
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    return internalInner(engine, args, roots[0], state, completion, input) catch |err| {
        try trusted(engine, err, generation);
        if (err == error.JavaScriptException) {
            const reason = try take(engine, err, generation);
            defer engine.freeValue(reason);
            try closeAbrupt(engine, state.*, generation);
            return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        }
        return failure(engine, err, generation);
    };
}
fn closeAbrupt(engine: *v.em.Engine, job: c.JSValue, generation: u64) !void {
    if (!c.JS_IsObject(job)) return;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(try s.get(job, "iteratorActive"))) return;
    try put(engine, job, "iteratorActive", c.pi_js_bool(engine.context, 0));
    const iterator = try s.get(job, "iterator");
    const method = s.get(iterator, "return") catch |err| { const suppressed = try take(engine, err, generation); engine.freeValue(suppressed); return; };
    if (v.nullish(method)) return;
    // A throwing completion wins over ordinary IteratorClose failures. Fatal
    // native failures are still propagated, without guest formatting.
    _ = s.call(method, iterator, &.{}) catch |err| { const suppressed = try take(engine, err, generation); engine.freeValue(suppressed); return; };
}
fn internalInner(engine: *v.em.Engine, args: []const c.JSValue, imports: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try boundary(&s, job);
        inline for (.{ "extensions", "errors", "warnings" }) |name| try put(engine, job, name, try s.array());
        const token = if (s.truthy(arg(args, 4))) try s.own(try cache.useCwd(engine, arg(args, 1))) else c.pi_js_undefined();
        try put(engine, job, "cacheToken", token);
        const token_cwd = if (v.nullish(token)) c.pi_js_undefined() else try s.get(token, "cwd");
        const cwd = if (v.nullish(token_cwd)) try s.own(try @import("native_sdk_source_paths.zig").resolve(engine, arg(args, 1), c.pi_js_undefined(), c.pi_js_undefined())) else token_cwd;
        try put(engine, job, "cwd", cwd);
        const bus = if (v.nullish(arg(args, 2))) try s.own(try @import("native_sdk_event_bus.zig").create(engine)) else arg(args, 2);
        try put(engine, job, "eventBus", bus);
        const runtime = if (v.nullish(arg(args, 3))) try s.own(try @import("native_sdk_extension_runtime.zig").create(engine, c.pi_js_undefined())) else arg(args, 3);
        try put(engine, job, "runtime", runtime);
        var iterator = try v.iterator(&s, arg(args, 0)); defer iterator.deinit();
        try put(engine, job, "iterator", iterator.iterator);
        try put(engine, job, "next", iterator.next_function);
        try put(engine, job, "iteratorActive", c.pi_js_bool(engine.context, 1));
    } else {
        const job = state.*;
        if (completion == .rejected) {
            try reject(&s, job, input);
            try closeAbrupt(engine, job, engine.native_allocation_generation);
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        try boundary(&s, job);
        // Preserve destructuring getter order: extension, then error.
        const extension = try s.get(input, "extension");
        const error_value = try s.get(input, "error");
        if (s.truthy(error_value)) {
            const errors = try s.get(job, "errors");
            const push = try s.get(errors, "push");
            const row = try s.object();
            try put(engine, row, "path", try s.get(job, "extPath"));
            try put(engine, row, "error", error_value);
            _ = try s.call(push, errors, &.{row});
        } else if (s.truthy(extension)) _ = try s.invoke(try s.get(job, "extensions"), "push", &.{extension});
    }
    const job = state.*;
    // IteratorStep errors do not call IteratorClose. Abrupt body errors do.
    try put(engine, job, "iteratorActive", c.pi_js_bool(engine.context, 0));
    const step = try s.call(try s.get(job, "next"), try s.get(job, "iterator"), &.{});
    if (!c.JS_IsObject(step)) return v.js.typeError(engine, "Iterator result is not an object");
    if (s.truthy(try s.get(step, "done"))) {
        const result = try s.object();
        inline for (.{ "extensions", "errors", "warnings", "runtime" }) |name| try put(engine, result, name, try s.get(job, name));
        return .{ .returned = c.JS_DupValue(engine.context, result) };
    }
    const path = try s.get(step, "value");
    try put(engine, job, "iteratorActive", c.pi_js_bool(engine.context, 1));
    try put(engine, job, "extPath", path);
    return wait(&s, job, .iteration, try imported(&s, imports, "loadExtension", &.{ path, try s.get(job, "cwd"), try s.get(job, "eventBus"), try s.get(job, "runtime"), try s.get(job, "cacheToken") }));
}
