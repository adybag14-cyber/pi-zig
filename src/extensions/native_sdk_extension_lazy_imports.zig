//! Native lazy module definitions for actual virtual-modules/jiti reexports.
//! A reviewed genuine queued dynamic-import binding remains a required input.
//! Immediate JS_LoadModule is deliberately not substituted for guest import().
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const f = @import("native_node_function.zig");
const virtual = @import("native_sdk_extension_virtual_modules.zig");
const body = @import("native_async_body.zig");
pub const Inputs = struct {
    loader_filename: []const u8,
    lazy_jiti_filename: []const u8,
    static_jiti_filename: []const u8,
    virtual_module_filename: []const u8,
    /// Actual complete native jiti namespaces. Missing namespaces are NOT
    /// substituted by the current namespace-only Graph2 prototype.
    lazy_jiti_namespace: []const u8,
    static_jiti_namespace: []const u8,
    virtual_names: virtual.Names,
    uses_embedded_modules: bool,
    /// Actual queued C import operation (physical basename, module specifier).
    /// Must use the reviewed native ABI, not JS_LoadModule or a Promise shim.
    dynamic_import: c.JSValue,
};
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try v.js.define(engine, target, name, c.JS_DupValue(engine.context, value)); }
fn nullObject(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.JS_NULL))); }
fn accessor(s: *Scope, exports: c.JSValue, name: [*:0]const u8, getter: c.JSValue) !void {
    const atom = c.JS_NewAtom(s.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(s.engine.context, exports, atom, c.JS_DupValue(s.engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return v.js.capture(s.engine);
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const std = @import("std");
    if (!c.JS_IsFunction(engine.context, inputs.dynamic_import)) return error.RequiredGenuineQueuedDynamicImport;
    inline for (.{ inputs.loader_filename, inputs.lazy_jiti_filename, inputs.static_jiti_filename, inputs.virtual_module_filename }) |name| if (!std.fs.path.isAbsolute(name) or std.mem.indexOfScalar(u8, name, 0) != null) return error.RequiredPhysicalLazyLoaderModuleName;
    if (std.mem.eql(u8, inputs.lazy_jiti_filename, inputs.static_jiti_filename) or std.mem.eql(u8, inputs.lazy_jiti_filename, inputs.virtual_module_filename) or std.mem.eql(u8, inputs.static_jiti_filename, inputs.virtual_module_filename)) return error.DuplicateActualLazyModuleName;
    // Registration reads own enumerable export names, not these accessors.
    // No namespace lookup or createJiti evaluation occurs during assembly.
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const names = try nullObject(&s);
    inline for (@typeInfo(virtual.Names).@"struct".fields) |field| try put(engine, names, field.name, try s.text(@field(inputs.virtual_names, field.name)));
    const virtual_exports = try s.object();
    try accessor(&s, virtual_exports, "VIRTUAL_MODULES", try s.own(try f.createArrow(engine, "get VIRTUAL_MODULES", 0, virtualExport, &.{names})));
    try engine.registerValueModule(inputs.virtual_module_filename, virtual_exports);
    inline for (.{ .{ inputs.lazy_jiti_filename, inputs.lazy_jiti_namespace }, .{ inputs.static_jiti_filename, inputs.static_jiti_namespace } }) |entry| {
        const exports = try s.object();
        try accessor(&s, exports, "createJiti", try s.own(try f.createArrow(engine, "get createJiti", 0, jitiExport, &.{try s.text(entry[1])})));
        try engine.registerValueModule(entry[0], exports);
    }
    const selected = if (inputs.uses_embedded_modules) inputs.static_jiti_filename else inputs.lazy_jiti_filename;
    const import_jiti = try s.own(try f.createArrow(engine, "importJitiLoader", 0, importModule, &.{ try s.text(inputs.loader_filename), try s.text(selected), inputs.dynamic_import }));
    const import_virtual = try s.own(try f.createArrow(engine, "importVirtualModule", 0, importModule, &.{ try s.text(inputs.loader_filename), try s.text(inputs.virtual_module_filename), inputs.dynamic_import }));
    const owner = try nullObject(&s);
    try put(engine, owner, "promise", c.pi_js_undefined());
    const select_jiti = try s.own(try f.createArrow(engine, "", 1, selectJiti, &.{}));
    const result = try s.object();
    try put(engine, result, "getCreateJiti", try s.own(try f.create(engine, "getCreateJiti", 0, getCreateJiti, &.{ owner, import_jiti, select_jiti })));
    try put(engine, result, "importVirtualModule", import_virtual);
    return c.JS_DupValue(engine.context, result);
}
fn importModule(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.js.call(engine, roots[2], c.pi_js_undefined(), &.{ roots[0], roots[1] });
}
fn selectJiti(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "createJiti");
}
fn getCreateJiti(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const cached = try s.get(roots[0], "promise");
    if (!v.nullish(cached)) return c.JS_DupValue(engine.context, cached);
    const importing = try s.call(roots[1], c.pi_js_undefined(), &.{});
    const promise = try s.invoke(importing, "then", &.{roots[2]});
    try put(engine, roots[0], "promise", promise);
    return c.JS_DupValue(engine.context, promise);
}
fn pending(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return err;
    if (!c.JS_IsUncatchableError(reason)) body.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| {
        if (fatal != error.JavaScriptException) return fatal;
    };
    // Engine's C module initializer consumes the VM exception. Remove the
    // native catch slot first, so a rejected import cannot retain an old reason
    // while getCreateJiti subsequently reads Promise.prototype.then.
    const owned = engine.captured_exception orelse return err;
    engine.captured_exception = null;
    _ = c.JS_Throw(engine.context, owned);
    return error.JavaScriptException;
}
fn jitiExport(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return jitiValue(engine, roots[0]) catch |err| return pending(engine, err, generation);
}
fn jitiValue(engine: *v.em.Engine, key: c.JSValue) !c.JSValue {
    const name = try engine.toString(key); defer engine.gpa.free(name);
    if (!engine.native_module_names.contains(name)) return v.js.typeError(engine, "Actual complete native createJiti module is unavailable");
    const namespace = engine.native_module_values.get(name) orelse return v.js.typeError(engine, "Actual complete native createJiti module is unavailable");
    const function = try v.js.get(engine, namespace, "createJiti");
    if (!c.JS_IsFunction(engine.context, function)) { engine.freeValue(function); return v.js.typeError(engine, "Actual complete native createJiti export is unavailable"); }
    return function;
}
fn virtualExport(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return virtualValue(engine, roots[0]) catch |err| return pending(engine, err, generation);
}
fn virtualValue(engine: *v.em.Engine, keys: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var names: virtual.Names = undefined;
    var strings: [9][*c]const u8 = .{null} ** 9;
    defer for (strings) |string| if (string != null) c.JS_FreeCString(engine.context, string);
    inline for (@typeInfo(virtual.Names).@"struct".fields, 0..) |field, i| {
        var length: usize = 0;
        strings[i] = c.JS_ToCStringLen(engine.context, &length, try s.get(keys, field.name));
        if (strings[i] == null) return v.js.capture(engine);
        @field(names, field.name) = strings[i][0..length];
    }
    const namespace = try s.own(try virtual.evaluate(engine, names));
    return v.js.get(engine, namespace, "VIRTUAL_MODULES");
}
