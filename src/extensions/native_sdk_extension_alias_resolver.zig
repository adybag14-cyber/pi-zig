//! Private physical resolver for the five getAliases package import fallbacks.
//! This does not install or claim a general Node import.meta.resolve API.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const charged = @import("native_env_charged_allocator.zig");
const State = struct { engine: *v.em.Engine, loader: v.em.SourceLoader, filename: []u8, allocations: charged.ChargedAllocator };
const allowed = [_][]const u8{ "@earendil-works/pi-agent-core", "@earendil-works/pi-tui", "@earendil-works/pi-ai/compat", "@earendil-works/pi-ai/oauth", "@earendil-works/pi-ai/providers/all" };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    state.allocations.allocator().free(state.filename);
    state.allocations.deinit();
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
/// The captured SourceLoader context must remain alive through Engine teardown,
/// as for the actual application loader. A replacement is rejected before the
/// borrowed old context can be dereferenced. No ambient private graph is used.
pub fn create(engine: *v.em.Engine, physical_filename: []const u8) !c.JSValue {
    const loader = engine.source_loader orelse return error.RequiredActualAliasSourceLoader;
    if (loader.normalize == null) return error.RequiredActualAliasImportNormalizer;
    if (!std.fs.path.isAbsolute(physical_filename) or std.mem.indexOfScalar(u8, physical_filename, 0) != null) return error.RequiredPhysicalAliasLoaderFilename;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State);
    errdefer if (!attached) engine.gpa.destroy(state);
    state.* = .{ .engine = engine, .loader = loader, .filename = undefined, .allocations = charged.ChargedAllocator.init(engine) };
    errdefer if (!attached) state.allocations.deinit();
    state.filename = try state.allocations.allocator().dupe(u8, physical_filename);
    errdefer if (!attached) state.allocations.allocator().free(state.filename);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Private SDK Alias Resolver", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.JS_NULL, id));
    defer engine.freeValue(owner);
    _ = c.JS_SetOpaque(owner, state);
    attached = true;
    return @import("native_node_function.zig").createMethod(engine, "resolve", 1, resolve, &.{owner});
}
fn resolve(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])) orelse return error.InvalidActualAliasResolverOwner));
    if (state.engine != engine) return error.InvalidActualAliasResolverOwner;
    const current = engine.source_loader orelse return error.ActualAliasSourceLoaderChanged;
    if (current.context != state.loader.context or current.normalize != state.loader.normalize or current.normalize_require != state.loader.normalize_require or current.load != state.loader.load or current.input != state.loader.input) return error.ActualAliasSourceLoaderChanged;
    if (args.len != 1 or !c.JS_IsString(args[0])) return error.UnobservedAliasImportResolveInput;
    const specifier = try engine.toString(args[0]); defer engine.gpa.free(specifier);
    var observed = false;
    for (allowed) |name| if (std.mem.eql(u8, name, specifier)) { observed = true; break; };
    if (!observed) return error.UnobservedAliasImportResolveInput;
    const allocator = state.allocations.allocator();
    const path = try state.loader.normalize.?(state.loader.context, allocator, state.filename, specifier);
    defer allocator.free(path);
    if (!std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, 0) != null) return error.RequiredPhysicalAliasImportResolution;
    const url = try @import("file_urls.zig").fromPath(allocator, path, builtin.os.tag == .windows);
    defer allocator.free(url);
    return engine.checked(c.JS_NewStringLen(engine.context, url.ptr, url.len));
}
