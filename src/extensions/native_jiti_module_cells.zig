//! Private once-linked cyclic import cells for REAL jiti core/frontend bodies.
//! No C/Engine policy, ambient graph, Source property or partial namespace cache.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const core = @import("native_jiti_core_factory.zig");
const frontend = @import("native_jiti_eval_frontend.zig");
const functions = @import("native_node_module_callable.zig");
const body = @import("native_async_body.zig");
const Phase = enum { declared, linked, initializing, ready, failed };
const Record = struct {
    engine: *v.em.Engine,
    class_id: c.JSClassID,
    reserved: usize,
    phase: Phase,
    core: c.JSValue,
    frontend: c.JSValue,
    platform: c.JSValue,
    core_imports: core.Imports,
    frontend_imports: frontend.Imports,
    is_windows: bool,
};
/// Host-internal only. Production declaration hard-wires canonical bodies in
/// native_jiti_core_graph; positive controls may not inject fake callbacks.
pub const Bodies = struct { core: functions.Callback, frontend: functions.Callback };
pub const Bindings = struct {
    core: core.Imports,
    frontend: frontend.Imports,
    platform: c.JSValue,
};
pub const Exports = struct { create_jiti: c.JSValue, eval_module: c.JSValue };
/// Owned, move-only host handle. Source cannot reach owner through any property.
/// Borrowing/copying without JS_DupValue does not create a second owned handle.
pub const Cells = struct {
    owner: c.JSValue,
    class_id: c.JSClassID,
    engine: *v.em.Engine,
    pub fn deinit(self: *Cells, engine: *v.em.Engine) void {
        // Owned handles must be released in their original Engine. Never free
        // a foreign-runtime JSValue through the supplied unrelated context.
        std.debug.assert(self.engine == engine);
        engine.freeValue(self.owner); self.owner = c.pi_js_undefined(); self.class_id = 0;
    }
};
fn empty(comptime T: type) T {
    var value: T = undefined;
    inline for (std.meta.fields(T)) |field| @field(value, field.name) = c.pi_js_undefined();
    return value;
}
fn freeImports(runtime: ?*c.JSRuntime, imports: anytype) void {
    inline for (std.meta.fields(@TypeOf(imports))) |field| c.JS_FreeValueRT(runtime, @field(imports, field.name));
}
fn markImports(runtime: ?*c.JSRuntime, imports: anytype, marker: ?*const c.JS_MarkFunc) void {
    inline for (std.meta.fields(@TypeOf(imports))) |field| c.JS_MarkValue(runtime, @field(imports, field.name), marker);
}
fn finalizer(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const record: *Record = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    const engine = record.engine; const reserved = record.reserved;
    c.JS_FreeValueRT(runtime, record.core); c.JS_FreeValueRT(runtime, record.frontend); c.JS_FreeValueRT(runtime, record.platform);
    freeImports(runtime, record.core_imports); freeImports(runtime, record.frontend_imports);
    engine.gpa.destroy(record); c.pi_js_native_memory_release(engine.native_memory_owner, reserved);
}
fn mark(runtime: ?*c.JSRuntime, owner: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const record: *Record = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    c.JS_MarkValue(runtime, record.core, marker); c.JS_MarkValue(runtime, record.frontend, marker); c.JS_MarkValue(runtime, record.platform, marker);
    markImports(runtime, record.core_imports, marker); markImports(runtime, record.frontend_imports, marker);
}
pub fn declare(engine: *v.em.Engine, bodies: Bodies) !Cells {
    const reserved = @sizeOf(Record);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, reserved) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, reserved);
    const record = try engine.gpa.create(Record); errdefer if (!attached) engine.gpa.destroy(record);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Private Jiti Import Cells", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.JS_NULL, id));
    record.* = .{ .engine = engine, .class_id = id, .reserved = reserved, .phase = .declared, .core = c.pi_js_undefined(), .frontend = c.pi_js_undefined(),
        .platform = c.pi_js_undefined(), .core_imports = empty(core.Imports), .frontend_imports = empty(frontend.Imports), .is_windows = false };
    _ = c.JS_SetOpaque(owner, record); attached = true;
    errdefer {
        // Break private outgoing function roots before releasing the unpublished
        // owner. Any function/prototype cycles remain visible/charged until GC.
        const first = record.core; record.core = c.pi_js_undefined(); engine.freeValue(first);
        const second = record.frontend; record.frontend = c.pi_js_undefined(); engine.freeValue(second);
        engine.freeValue(owner);
    }
    record.core = try functions.create(engine, "createJiti", 1, true, bodies.core, &.{owner});
    record.frontend = try functions.create(engine, "evalModule", 2, true, bodies.frontend, &.{owner});
    return .{ .owner = owner, .class_id = id, .engine = engine };
}
fn hostRecord(engine: *v.em.Engine, cells: *const Cells) !*Record {
    if (cells.engine != engine) return error.ForeignJitiModuleCells;
    if (cells.class_id == 0 or c.JS_GetClassID(cells.owner) != cells.class_id) return error.InvalidJitiModuleCells;
    const record: *Record = @ptrCast(@alignCast(c.JS_GetOpaque(cells.owner, cells.class_id) orelse return error.InvalidJitiModuleCells));
    if (record.engine != engine or record.class_id != cells.class_id) return error.ForeignJitiModuleCells;
    return record;
}
fn duplicate(comptime T: type, engine: *v.em.Engine, imports: T) T {
    var result: T = undefined;
    inline for (std.meta.fields(T)) |field| @field(result, field.name) = c.JS_DupValue(engine.context, @field(imports, field.name));
    return result;
}
/// All retained structs are fixed-size/precharged in declare. Validation has
/// no guest lookup; JS_DupValue is nonallocating. Commit cannot fail/partially
/// link, and no callback/platform/module initializer runs in this operation.
pub fn link(engine: *v.em.Engine, cells: *const Cells, supplied: Bindings) !void {
    const record = try hostRecord(engine, cells);
    if (record.phase != .declared) return error.JitiModuleCellsAlreadyLinked;
    var core_imports = supplied.core; var frontend_imports = supplied.frontend;
    core_imports.eval_module = record.frontend;
    frontend_imports.nested_create_jiti = record.core;
    frontend_imports.eval_module_self = record.frontend;
    try core.validate(engine, core_imports); try frontend.validate(engine, frontend_imports);
    if (!c.JS_IsFunction(engine.context, supplied.platform)) return error.RequiredActualJitiPlatform;
    const retained_core = duplicate(core.Imports, engine, core_imports);
    const retained_frontend = duplicate(frontend.Imports, engine, frontend_imports);
    const platform = c.JS_DupValue(engine.context, supplied.platform);
    record.core_imports = retained_core; record.frontend_imports = retained_frontend; record.platform = platform;
    record.phase = .linked;
}
pub fn initialize(engine: *v.em.Engine, cells: *const Cells) !void {
    const record = try hostRecord(engine, cells);
    if (record.phase != .linked) return error.JitiModuleCellsNotLinkedOrAlreadyInitialized;
    // A throwing/reentrant platform initializer cannot rerun this module's
    // initialization. Its unpublished graph is discarded by the assembler.
    record.phase = .initializing;
    errdefer record.phase = .failed;
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    const value = v.js.call(engine, record.platform, c.pi_js_undefined(), &.{}) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            if (!c.JS_IsUncatchableError(reason)) try body.rethrowRecognizedAllocation(engine, reason, generation);
        };
        return err;
    };
    defer engine.freeValue(value);
    const win32 = try engine.checked(c.JS_NewString(engine.context, "win32")); defer engine.freeValue(win32);
    record.is_windows = c.JS_IsStrictEqual(engine.context, value, win32);
    record.phase = .ready;
}
pub fn exports(engine: *v.em.Engine, cells: *const Cells) !Exports {
    const record = try hostRecord(engine, cells);
    if (record.phase != .ready) return error.JitiModuleCellsNotReady;
    return .{ .create_jiti = c.JS_DupValue(engine.context, record.core), .eval_module = c.JS_DupValue(engine.context, record.frontend) };
}
fn bodyRecord(engine: *v.em.Engine, owner: c.JSValue) !*Record {
    // Only canonical declaration captures carry this private class value; it is
    // never accepted as a guest parameter or public Source ownership token.
    const id = c.JS_GetClassID(owner);
    const record: *Record = @ptrCast(@alignCast(c.JS_GetOpaque(owner, id) orelse return error.InvalidJitiModuleCells));
    if (record.engine != engine or record.class_id != id) return error.ForeignJitiModuleCells;
    if (record.phase != .ready) {
        _ = try engine.checked(c.JS_ThrowReferenceError(engine.context, "Jiti module imports are not initialized")); unreachable;
    }
    return record;
}
pub fn coreImports(engine: *v.em.Engine, owner: c.JSValue) !core.Imports { return (try bodyRecord(engine, owner)).core_imports; }
pub fn frontendImports(engine: *v.em.Engine, owner: c.JSValue) !frontend.Imports { return (try bodyRecord(engine, owner)).frontend_imports; }
pub fn isWindows(engine: *v.em.Engine, owner: c.JSValue) !bool { return (try bodyRecord(engine, owner)).is_windows; }
