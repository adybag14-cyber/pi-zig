//! Direct C ABI for the extension language. No Node process or bridge source.
const std = @import("std");
const builtin = @import("builtin");
const file_urls = @import("file_urls.zig");
pub const c = @cImport({
    // Zig 0.16 translate-c emits invalid unused declarations for MinGW's
    // fortified wide-string inline wrappers in ReleaseSafe. This affects
    // declaration import only; the separately compiled C library keeps its
    // normal compiler safety flags and does not use these inline wrappers.
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("libregexp.h");
});

pub const Options = struct {
    memory_limit: usize = 64 * 1024 * 1024,
    stack_limit: usize = 1024 * 1024,
    interrupt_budget: u64 = 10_000,
    job_budget: usize = 100_000,
    host_await_timeout_ms: u64 = 15_000,
    // Hosted extensions are imported by Pi, rather than being JS entrypoints.
    // Standalone embedders may explicitly designate their evaluated root.
    main_module: bool = false,
};

pub const SourceLoader = struct {
    context: ?*anyopaque = null,
    load: *const fn (?*anyopaque, std.mem.Allocator, []const u8) anyerror![]u8,
    normalize: ?*const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8) anyerror![]u8 = null,
    normalize_require: ?*const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8) anyerror![]u8 = null,
    input: ?*const fn (?*anyopaque, *Engine, []const u8) anyerror!ModuleInput = null,
};

/// Values and source returned by the loader are owned by its caller.
pub const ModuleInput = union(enum) { source: []u8, exports: c.JSValue };

pub const Engine = struct {
    gpa: std.mem.Allocator,
    runtime: *c.JSRuntime,
    context: *c.JSContext,
    options: Options,
    interrupts: u64 = 0,
    cancelled: std.atomic.Value(bool) = .init(false),
    last_error: ?[]u8 = null,
    captured_exception: ?c.JSValue = null,
    host_data: ?*anyopaque = null,
    native_ui_manager: ?*anyopaque = null,
    host_ui_pending: usize = 0,
    native_io: ?std.Io = null,
    native_sdk_class: c.JSClassID = 0,
    native_durable_class: c.JSClassID = 0,
    native_models_store_class: c.JSClassID = 0,
    native_sdk_extension_group: ?*anyopaque = null,
    native_sdk_next_runtime_id: u64 = 1,
    native_durable_harness_class: c.JSClassID = 0,
    native_durable_runtime_class: c.JSClassID = 0,
    native_durable_watch_class: c.JSClassID = 0,
    native_durable_state_class: c.JSClassID = 0,
    native_durable_subscriber_class: c.JSClassID = 0,
    native_durable_registry_class: c.JSClassID = 0,
    native_durable_registry_snapshot_class: c.JSClassID = 0,
    native_durable_uuid_last_ms: u64 = 0,
    native_durable_uuid_sequence: ?u64 = null,
    native_sdk_model_bridge_registry: ?c.JSValue = null,
    native_sdk_model_bridge_lease_class: c.JSClassID = 0,
    native_sdk_next_session_generation: u64 = 1,
    native_sdk_prototypes: [7]?c.JSValue = .{null} ** 7,
    native_weak_ref_constructor: ?c.JSValue = null,
    native_weak_ref_deref: ?c.JSValue = null,
    native_console_stdout: bool = false,
    text_encoder_class: c.JSClassID = 0,
    text_decoder_class: c.JSClassID = 0,
    dom_exception_class: c.JSClassID = 0,
    url_class: c.JSClassID = 0,
    url_search_params_class: c.JSClassID = 0,
    url_search_params_iterator_class: c.JSClassID = 0,
    url_decode_uri_component: ?c.JSValue = null,
    event_stream_class: c.JSClassID = 0,
    event_stream_iterator_class: c.JSClassID = 0,
    event_stream_async_atom: c.JSAtom = c.JS_ATOM_NULL,
    buffer_prototype: ?c.JSValue = null,
    buffer_ready: bool = false,
    abort_signal_class: c.JSClassID = 0,
    abort_controller_class: c.JSClassID = 0,
    abort_signals_ready: bool = false,
    host_scheduler: ?*anyopaque = null,
    host_pump: ?*const fn (*Engine) anyerror!bool = null,
    // Called only by the context's owning thread. Transport reader tasks may
    // queue bytes, but must never call QuickJS or dispatch AbortSignal listeners.
    host_control_context: ?*anyopaque = null,
    host_control_pump: ?*const fn (*Engine) anyerror!bool = null,
    // The notifier is synchronization-only and may be copied into worker leases.
    // Its owner keeps the context alive until every leased worker has joined.
    host_owner_notify_context: ?*anyopaque = null,
    host_owner_notify: ?*const fn (?*anyopaque) void = null,
    native_durable_control_context: ?*anyopaque = null,
    native_durable_control_pump: ?*const fn (*Engine) anyerror!bool = null,
    native_durable_control_deinit: ?*const fn (*Engine) void = null,
    host_scheduler_deinit: ?*const fn (*Engine) void = null,
    host_await_deadline_ms: ?i64 = null,
    modules: std.StringHashMapUnmanaged([:0]u8) = .empty,
    native_module_names: std.StringHashMapUnmanaged(void) = .empty,
    native_module_values: std.StringHashMapUnmanaged(c.JSValue) = .empty,
    native_namespace_counter: u64 = 0,
    commonjs_cache: c.JSValue,
    source_loader: ?SourceLoader = null,

    pub fn init(gpa: std.mem.Allocator, options: Options) !*Engine {
        const self = try gpa.create(Engine);
        errdefer gpa.destroy(self);
        const runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer c.JS_FreeRuntime(runtime);
        c.JS_SetMemoryLimit(runtime, options.memory_limit);
        c.JS_SetMaxStackSize(runtime, options.stack_limit);
        const context = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
        errdefer c.JS_FreeContext(context);
        const commonjs_cache = c.JS_NewObjectProto(context, c.pi_js_null());
        if (c.JS_IsException(commonjs_cache)) {
            return error.OutOfMemory;
        }
        errdefer c.JS_FreeValue(context, commonjs_cache);
        self.* = .{ .gpa = gpa, .runtime = runtime, .context = context, .options = options, .commonjs_cache = commonjs_cache };
        c.JS_SetContextOpaque(context, self);
        c.JS_SetRuntimeOpaque(runtime, self);
        c.JS_SetInterruptHandler(runtime, interrupt, self);
        c.JS_SetModuleLoaderFunc(runtime, null, moduleLoader, self);
        // Capture pristine intrinsics before any extension input executes.
        // Lease affinity must not depend on mutable globals/prototypes.
        const global = c.JS_GetGlobalObject(context);
        defer self.freeValue(global);
        const weak_ctor = c.JS_GetPropertyStr(context, global, "WeakRef");
        const weak_proto = c.JS_GetPropertyStr(context, weak_ctor, "prototype");
        defer self.freeValue(weak_proto);
        const weak_deref = c.JS_GetPropertyStr(context, weak_proto, "deref");
        if (c.JS_IsException(weak_ctor) or c.JS_IsException(weak_proto) or c.JS_IsException(weak_deref)) {
            self.freeValue(weak_ctor);
            self.freeValue(weak_deref);
            return error.OutOfMemory;
        }
        self.native_weak_ref_constructor = weak_ctor;
        self.native_weak_ref_deref = weak_deref;
        return self;
    }

    pub fn deinit(self: *Engine) void {
        self.closeDurableOwner();
        for (self.native_sdk_prototypes) |prototype| if (prototype) |value| self.freeValue(value);
        if (self.native_weak_ref_constructor) |value| self.freeValue(value);
        if (self.native_weak_ref_deref) |value| self.freeValue(value);
        c.JS_FreeAtom(self.context, self.event_stream_async_atom);
        if (self.host_scheduler_deinit) |cleanup| cleanup(self);
        if (self.captured_exception) |exception| self.freeValue(exception);
        if (self.buffer_prototype) |prototype| self.freeValue(prototype);
        if (self.url_decode_uri_component) |decoder| self.freeValue(decoder);
        var values = self.native_module_values.valueIterator();
        while (values.next()) |value| self.freeValue(value.*);
        self.native_module_values.deinit(self.gpa);
        if (self.native_sdk_model_bridge_registry) |value| self.freeValue(value);
        self.freeValue(self.commonjs_cache);
        c.JS_FreeContext(self.context);
        c.JS_FreeRuntime(self.runtime);
        if (self.last_error) |message| self.gpa.free(message);
        var modules = self.modules.iterator();
        while (modules.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.modules.deinit(self.gpa);
        var native_modules = self.native_module_names.keyIterator();
        while (native_modules.next()) |name| self.gpa.free(name.*);
        self.native_module_names.deinit(self.gpa);
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    pub fn fromContext(context: *c.JSContext) *Engine {
        return @ptrCast(@alignCast(c.JS_GetContextOpaque(context).?));
    }

    pub fn beginInvocation(self: *Engine) void {
        self.interrupts = 0;
        self.cancelled.store(false, .release);
        if (self.last_error) |message| self.gpa.free(message);
        self.last_error = null;
        if (self.captured_exception) |exception| self.freeValue(exception);
        self.captured_exception = null;
    }

    pub fn cancel(self: *Engine) void {
        self.cancelled.store(true, .release);
    }

    /// Register native-loader input; source is extension input, not host code.
    pub fn registerModule(self: *Engine, name: []const u8, source: []const u8) !void {
        if (name.len == 0 or std.mem.indexOfScalar(u8, name, 0) != null) return error.InvalidNativeModuleName;
        if (self.modules.contains(name) or self.native_module_names.contains(name)) return error.DuplicateExtensionModule;
        const key = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(key);
        const terminated = try self.gpa.dupeZ(u8, source);
        errdefer self.gpa.free(terminated);
        try self.modules.put(self.gpa, key, terminated);
    }

    pub fn setSourceLoader(self: *Engine, loader: SourceLoader) void {
        self.source_loader = loader;
        const normalizer: ?*const c.JSModuleNormalizeFunc = if (loader.normalize != null) normalizeModule else null;
        c.JS_SetModuleLoaderFunc(self.runtime, normalizer, moduleLoader, self);
    }

    fn normalizeModule(context: ?*c.JSContext, base: [*c]const u8, name: [*c]const u8, context_data: ?*anyopaque) callconv(.c) [*c]u8 {
        const self: *Engine = @ptrCast(@alignCast(context_data.?));
        const specifier = std.mem.span(name);
        const registered = self.native_module_names.contains(specifier);
        // Node builtins always use native host bindings. Schema packages may
        // instead come from an extension project's user-installed ESM input.
        const schema_package = std.mem.eql(u8, specifier, "typebox") or std.mem.eql(u8, specifier, "@sinclair/typebox");
        var resolved: ?[]u8 = null;
        defer if (resolved) |owned| self.gpa.free(owned);
        if (!(registered and !schema_package) and !self.modules.contains(specifier)) {
            const loader = self.source_loader.?;
            resolved = loader.normalize.?(loader.context, self.gpa, std.mem.span(base), specifier) catch |err| fallback: {
                if (err == error.ExtensionModuleNotFound and registered) break :fallback null;
                _ = c.JS_ThrowReferenceError(context, "Native extension resolution failed: %s", @as([*:0]const u8, @errorName(err)));
                return null;
            };
        }
        const bytes = resolved orelse specifier;
        const allocation = c.js_malloc(context, bytes.len + 1) orelse return null;
        const output: [*]u8 = @ptrCast(allocation);
        @memcpy(output[0..bytes.len], bytes);
        output[bytes.len] = 0;
        return output;
    }

    /// Export a native object as an ES module without generating bridge code.
    /// The engine duplicates exports; the caller retains its original value.
    pub fn registerValueModule(self: *Engine, name: []const u8, exports: c.JSValue) !void {
        _ = try self.createValueModule(name, exports);
    }
    /// Native namespaces use the engine's real ESM exotic object, including its
    /// readonly bindings and descriptors. No JavaScript shim is evaluated.
    pub fn valueNamespace(self: *Engine, exports: c.JSValue) !c.JSValue {
        self.native_namespace_counter += 1;
        const name = try std.fmt.allocPrint(self.gpa, "pi-native:namespace/{d}", .{self.native_namespace_counter});
        defer self.gpa.free(name);
        const module = try self.createValueModule(name, exports);
        const value = c.pi_js_module_value(self.context, module);
        var consumed = false;
        errdefer if (!consumed) self.freeValue(value);
        if (c.JS_ResolveModule(self.context, value) < 0) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        consumed = true;
        const pending = try self.checked(c.JS_EvalFunction(self.context, value));
        defer self.freeValue(pending);
        const settled = try self.awaitValue(pending);
        self.freeValue(settled);
        return self.checked(c.JS_GetModuleNamespace(self.context, module));
    }

    fn createValueModule(self: *Engine, name: []const u8, exports: c.JSValue) !*c.JSModuleDef {
        if (name.len == 0 or std.mem.indexOfScalar(u8, name, 0) != null) return error.InvalidNativeModuleName;
        if (self.modules.contains(name) or self.native_module_names.contains(name)) return error.DuplicateExtensionModule;
        const terminated = try self.gpa.dupeZ(u8, name);
        defer self.gpa.free(terminated);
        // Finish host allocations before installing an immutable C module.
        const owned_name = try self.gpa.dupe(u8, name);
        var reserved = false;
        var module_created = false;
        errdefer if (!module_created) {
            if (reserved) _ = self.native_module_names.remove(name);
            self.gpa.free(owned_name);
        };
        try self.native_module_values.ensureUnusedCapacity(self.gpa, 1);
        try self.native_module_names.put(self.gpa, owned_name, {});
        reserved = true;
        const module = c.JS_NewCModule(self.context, terminated.ptr, initializeValueModule) orelse return error.OutOfMemory;
        // A failed C registration remains reserved until engine teardown.
        module_created = true;
        self.native_module_values.putAssumeCapacity(owned_name, c.JS_DupValue(self.context, exports));
        if (c.JS_SetModulePrivateValue(self.context, module, c.JS_DupValue(self.context, exports)) < 0) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        var properties: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(self.context, &properties, &count, exports, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        defer c.JS_FreePropertyEnum(self.context, properties, count);
        for (0..count) |index| {
            const property = c.JS_AtomToCString(self.context, properties[index].atom);
            if (property == null) return error.OutOfMemory;
            defer c.JS_FreeCString(self.context, property);
            if (c.JS_AddModuleExport(self.context, module, property) < 0) return error.InvalidNativeModuleExport;
        }
        return module;
    }

    /// ESM namespaces expose a default binding without putting a cyclic
    /// `.default` property on the underlying builtin object.
    pub fn registerDefaultModule(self: *Engine, name: []const u8, object: c.JSValue) !void {
        _ = try self.createDefaultModule(name, object);
    }

    fn createDefaultModule(self: *Engine, name: []const u8, object: c.JSValue) !*c.JSModuleDef {
        const exports = try self.defaultExports(object);
        defer self.freeValue(exports);
        return self.createValueModule(name, exports);
    }

    pub fn defaultExports(self: *Engine, object: c.JSValue) !c.JSValue {
        const exports = try self.checked(c.JS_NewObject(self.context));
        errdefer self.freeValue(exports);
        var properties: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_IsObject(object)) {
            if (c.JS_GetOwnPropertyNames(self.context, &properties, &count, object, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
        }
        defer c.JS_FreePropertyEnum(self.context, properties, count);
        for (0..count) |index| {
            const value = try self.checked(c.JS_GetProperty(self.context, object, properties[index].atom));
            if (c.JS_DefinePropertyValue(self.context, exports, properties[index].atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        if (c.JS_DefinePropertyValueStr(self.context, exports, "default", c.JS_DupValue(self.context, object), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        return exports;
    }

    pub fn loadModuleInput(self: *Engine, name: []const u8) !ModuleInput {
        const loader = self.source_loader orelse return error.NativeModuleLoaderUnavailable;
        if (loader.input) |input| return input(loader.context, self, name);
        return .{ .source = try loader.load(loader.context, self.gpa, name) };
    }

    pub fn normalizeRequire(self: *Engine, base: []const u8, name: []const u8) ![]u8 {
        const schema_package = std.mem.eql(u8, name, "typebox") or std.mem.startsWith(u8, name, "typebox/") or std.mem.eql(u8, name, "@sinclair/typebox") or std.mem.startsWith(u8, name, "@sinclair/typebox/");
        if (self.native_module_values.contains(name) and !schema_package) return self.gpa.dupe(u8, name);
        const loader = self.source_loader orelse return error.NativeModuleLoaderUnavailable;
        const normalize = loader.normalize_require orelse loader.normalize orelse return error.NativeModuleLoaderUnavailable;
        return normalize(loader.context, self.gpa, base, name);
    }

    pub fn requireBuiltin(self: *Engine, name: []const u8) !?c.JSValue {
        if (std.fs.path.isAbsolute(name)) return null;
        const namespace = self.native_module_values.get(name) orelse return null;
        const default = try self.checked(c.JS_GetPropertyStr(self.context, namespace, "default"));
        if (!c.JS_IsUndefined(default)) return default;
        self.freeValue(default);
        return c.JS_DupValue(self.context, namespace);
    }

    fn initializeValueModule(context: ?*c.JSContext, module: ?*c.JSModuleDef) callconv(.c) c_int {
        const exports = c.JS_GetModulePrivateValue(context, module);
        defer c.JS_FreeValue(context, exports);
        var properties: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(context, &properties, &count, exports, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return -1;
        defer c.JS_FreePropertyEnum(context, properties, count);
        for (0..count) |index| {
            const property = c.JS_AtomToCString(context, properties[index].atom);
            if (property == null) return -1;
            defer c.JS_FreeCString(context, property);
            const value = c.JS_GetProperty(context, exports, properties[index].atom);
            if (c.JS_IsException(value)) return -1;
            if (c.JS_SetModuleExport(context, module, property, value) < 0) return -1;
        }
        return 0;
    }

    /// Evaluate an ES module and return its owned export namespace.
    pub fn evalModule(self: *Engine, source: []const u8, filename: [:0]const u8) !c.JSValue {
        const compiled = try self.eval(source, filename, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
        const module = c.pi_js_module(compiled) orelse {
            self.freeValue(compiled);
            return error.InvalidExtensionModule;
        };
        self.setImportMeta(module, filename, self.options.main_module) catch |err| {
            self.freeValue(compiled);
            return err;
        };
        // JS_EvalFunction consumes the compiled module value even on failure.
        const evaluated = try self.checked(c.JS_EvalFunction(self.context, compiled));
        defer self.freeValue(evaluated);
        const settled = try self.awaitValue(evaluated);
        defer self.freeValue(settled);
        return self.checked(c.JS_GetModuleNamespace(self.context, module));
    }

    fn setImportMeta(self: *Engine, module: *c.JSModuleDef, filename: []const u8, main: bool) !void {
        const meta = try self.checked(c.JS_GetImportMeta(self.context, module));
        defer self.freeValue(meta);
        if (c.JS_DefinePropertyValueStr(self.context, meta, "main", c.pi_js_bool(self.context, @intFromBool(main)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        if (!std.fs.path.isAbsolute(filename)) return;
        const url = try file_urls.fromPath(self.gpa, filename, builtin.os.tag == .windows);
        defer self.gpa.free(url);
        const platform_path = try self.gpa.dupe(u8, filename);
        defer self.gpa.free(platform_path);
        if (builtin.os.tag == .windows) for (platform_path) |*byte| {
            if (byte.* == '/') byte.* = '\\';
        };
        const directory = std.fs.path.dirname(platform_path) orelse platform_path;
        const fields = [_]struct { name: [*:0]const u8, value: []const u8 }{
            .{ .name = "url", .value = url },
            .{ .name = "filename", .value = platform_path },
            .{ .name = "dirname", .value = directory },
        };
        for (fields) |field| {
            const value = try self.checked(c.JS_NewStringLen(self.context, field.value.ptr, field.value.len));
            if (c.JS_DefinePropertyValueStr(self.context, meta, field.name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
    }

    fn moduleLoader(context: ?*c.JSContext, name: [*c]const u8, context_data: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
        const self: *Engine = @ptrCast(@alignCast(context_data.?));
        const module_name = std.mem.span(name);
        const source = self.modules.get(module_name) orelse loaded: {
            const loader = self.source_loader orelse {
                _ = c.JS_ThrowReferenceError(context, "Native extension module not registered: %s", name);
                return null;
            };
            _ = loader;
            const loaded = self.loadModuleInput(module_name) catch |err| {
                _ = c.JS_ThrowReferenceError(context, "Native extension import failed: %s", @as([*:0]const u8, @errorName(err)));
                return null;
            };
            if (loaded == .exports) {
                defer self.freeValue(loaded.exports);
                return self.createDefaultModule(module_name, loaded.exports) catch |err| {
                    _ = c.JS_ThrowReferenceError(context, "Native extension value import failed: %s", @as([*:0]const u8, @errorName(err)));
                    return null;
                };
            }
            defer self.gpa.free(loaded.source);
            self.registerModule(module_name, loaded.source) catch |err| {
                _ = c.JS_ThrowReferenceError(context, "Native extension import registration failed: %s", @as([*:0]const u8, @errorName(err)));
                return null;
            };
            break :loaded self.modules.get(module_name).?;
        };
        const compiled = c.JS_Eval(context, source.ptr, source.len, name, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
        if (c.JS_IsException(compiled)) return null;
        // QuickJS keeps the compiled dependency in its module registry.
        const module = c.pi_js_module(compiled) orelse {
            c.JS_FreeValue(context, compiled);
            _ = c.JS_ThrowInternalError(context, "Invalid native extension module");
            return null;
        };
        self.setImportMeta(module, module_name, false) catch |err| {
            c.JS_FreeValue(context, compiled);
            _ = c.JS_ThrowInternalError(context, "Native import metadata failed: %s", @as([*:0]const u8, @errorName(err)));
            return null;
        };
        c.JS_FreeValue(context, compiled);
        return module;
    }

    /// Returns an owned value. The caller releases it with freeValue().
    pub fn eval(self: *Engine, source: []const u8, filename: [:0]const u8, flags: c_int) !c.JSValue {
        const terminated = try self.gpa.dupeZ(u8, source);
        defer self.gpa.free(terminated);
        return self.checked(c.JS_Eval(self.context, terminated.ptr, source.len, filename.ptr, flags));
    }

    pub fn checked(self: *Engine, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value)) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        return value;
    }

    /// Native callbacks preserve the user's exception object and identity.
    pub fn throwCaptured(self: *Engine) c.JSValue {
        if (c.JS_HasException(self.context)) return c.JS_Throw(self.context, c.JS_GetException(self.context));
        if (self.captured_exception) |exception| return c.JS_Throw(self.context, c.JS_DupValue(self.context, exception));
        return c.JS_ThrowInternalError(self.context, "Native callback failed without an exception value");
    }

    pub fn freeValue(self: *Engine, value: c.JSValue) void {
        c.JS_FreeValue(self.context, value);
    }

    pub const NativeFunction = *const fn (?*c.JSContext, c.JSValue, c_int, [*c]c.JSValue) callconv(.c) c.JSValue;

    /// Install a Zig callback as a real extension-language function.
    pub fn bindFunction(self: *Engine, name: [:0]const u8, function: NativeFunction, arity: c_int) !void {
        const global = c.JS_GetGlobalObject(self.context);
        defer self.freeValue(global);
        const native = try self.checked(c.JS_NewCFunction(self.context, function, name.ptr, arity));
        // SetProperty consumes native on both its success and failure paths.
        if (c.JS_SetPropertyStr(self.context, global, name.ptr, native) < 0) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
    }

    pub fn stringify(self: *Engine, value: c.JSValue) ![]u8 {
        const encoded = try self.checked(c.JS_JSONStringify(self.context, value, c.pi_js_undefined(), c.pi_js_undefined()));
        defer self.freeValue(encoded);
        return self.toString(encoded);
    }

    /// Construct host DTOs without evaluating generated bridge source. Numbers
    /// retain NaN/Infinity when an upstream API returns them outside JSON.
    pub fn fromJsonValue(self: *Engine, value: std.json.Value) !c.JSValue {
        return self.fromJsonValueDepth(value, 0);
    }

    fn fromJsonValueDepth(self: *Engine, value: std.json.Value, depth: usize) anyerror!c.JSValue {
        if (depth > 256) return error.NativeValueDepthLimit;
        return switch (value) {
            .null => c.pi_js_null(),
            .bool => |boolean| c.pi_js_bool(self.context, @intFromBool(boolean)),
            .integer => |integer| self.checked(c.JS_NewInt64(self.context, integer)),
            .float => |number| self.checked(c.JS_NewFloat64(self.context, number)),
            .number_string => |text| self.checked(c.JS_NewFloat64(self.context, try std.fmt.parseFloat(f64, text))),
            .string => |text| self.checked(c.JS_NewStringLen(self.context, text.ptr, text.len)),
            .array => |array| result: {
                const object = try self.checked(c.JS_NewArray(self.context));
                errdefer self.freeValue(object);
                for (array.items, 0..) |item, index| {
                    const child = try self.fromJsonValueDepth(item, depth + 1);
                    if (c.JS_SetPropertyUint32(self.context, object, @intCast(index), child) < 0) return error.JavaScriptException;
                }
                break :result object;
            },
            .object => |map| result: {
                const object = try self.checked(c.JS_NewObject(self.context));
                errdefer self.freeValue(object);
                var fields = map.iterator();
                while (fields.next()) |field| {
                    const key = c.JS_NewAtomLen(self.context, field.key_ptr.*.ptr, field.key_ptr.*.len);
                    if (key == c.JS_ATOM_NULL) return error.OutOfMemory;
                    defer c.JS_FreeAtom(self.context, key);
                    const child = try self.fromJsonValueDepth(field.value_ptr.*, depth + 1);
                    if (c.JS_DefinePropertyValue(self.context, object, key, child, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
                }
                break :result object;
            },
        };
    }

    pub fn toString(self: *Engine, value: c.JSValue) ![]u8 {
        var length: usize = 0;
        const bytes = c.JS_ToCStringLen(self.context, &length, value);
        if (bytes == null) {
            self.captureException(self.context);
            return error.JavaScriptException;
        }
        defer c.JS_FreeCString(self.context, bytes);
        return self.gpa.dupe(u8, bytes[0..length]);
    }

    /// Return a new owned result without consuming the caller's promise/value.
    pub fn pumpControls(self: *Engine) !bool {
        self.refreshUiDeadline();
        const host_worked = if (self.host_control_pump) |pump| try pump(self) else false;
        const durable_worked = if (self.native_durable_control_pump) |pump| try pump(self) else false;
        return host_worked or durable_worked;
    }
    pub fn closeDurableOwner(self: *Engine) void {
        if (self.native_durable_control_deinit) |cleanup| cleanup(self);
        self.native_durable_control_context = null;
        self.native_durable_control_pump = null;
        self.native_durable_control_deinit = null;
    }

    /// Drain queued microtasks without awaiting a promise or sleeping on the
    /// host scheduler. Used by the persistent owner's idle event loop.
    pub fn drainReadyJobs(self: *Engine) !bool {
        var jobs: usize = 0;
        while (c.JS_IsJobPending(self.runtime)) {
            if (jobs >= self.options.job_budget) return error.JavaScriptJobLimit;
            var context: ?*c.JSContext = null;
            if (c.JS_ExecutePendingJob(self.runtime, &context) < 0) {
                self.captureException(context orelse self.context);
                return error.JavaScriptException;
            }
            jobs += 1;
        }
        return jobs != 0;
    }

    fn refreshUiDeadline(self: *Engine) void {
        if (self.host_ui_pending == 0 or self.host_await_deadline_ms == null or self.options.host_await_timeout_ms == 0) return;
        if (self.native_io) |io| self.host_await_deadline_ms = std.Io.Clock.awake.now(io).toMilliseconds() +| @as(i64, @intCast(@min(self.options.host_await_timeout_ms, std.math.maxInt(i64))));
    }

    pub fn awaitValue(self: *Engine, value: c.JSValue) !c.JSValue {
        const previous_deadline = self.host_await_deadline_ms;
        defer self.host_await_deadline_ms = previous_deadline;
        if (self.native_io) |io| {
            if (self.options.host_await_timeout_ms > 0) self.host_await_deadline_ms = std.Io.Clock.awake.now(io).toMilliseconds() +| @as(i64, @intCast(@min(self.options.host_await_timeout_ms, std.math.maxInt(i64))));
        }
        var jobs: usize = 0;
        while (c.JS_PromiseState(self.context, value) == c.JS_PROMISE_PENDING or c.JS_IsJobPending(self.runtime)) {
            self.refreshUiDeadline();
            if (self.native_io) |io| if (self.host_await_deadline_ms) |limit| {
                if (std.Io.Clock.awake.now(io).toMilliseconds() >= limit) return error.NativeHostPromiseTimeout;
            };
            // Once this promise has settled, remaining queued microtasks may
            // still drain, but a late wire abort must not mutate its signal.
            if (c.JS_PromiseState(self.context, value) == c.JS_PROMISE_PENDING) _ = try self.pumpControls();
            if (c.JS_PromiseState(self.context, value) != c.JS_PROMISE_PENDING and !c.JS_IsJobPending(self.runtime)) break;
            if (jobs >= self.options.job_budget) return error.JavaScriptJobLimit;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime, &context);
            if (status < 0) {
                self.captureException(context orelse self.context);
                return error.JavaScriptException;
            }
            if (status == 0) {
                if (self.host_pump) |pump| {
                    if (try pump(self)) continue;
                }
                // A native transport can settle a promise through an incoming
                // abort or UI response even when no timer or JS job is pending.
                if ((self.host_control_pump != null or self.native_durable_control_pump != null) and self.native_io != null) {
                    try self.native_io.?.sleep(.fromMilliseconds(5), .awake);
                    continue;
                }
                return error.JavaScriptPromiseUnsettled;
            }
            jobs += 1;
        }
        return switch (c.JS_PromiseState(self.context, value)) {
            c.JS_PROMISE_REJECTED => blk: {
                const reason = c.JS_PromiseResult(self.context, value);
                defer self.freeValue(reason);
                self.captureValue(self.context, reason);
                break :blk error.JavaScriptException;
            },
            c.JS_PROMISE_FULFILLED => c.JS_PromiseResult(self.context, value),
            else => c.JS_DupValue(self.context, value),
        };
    }

    fn captureException(self: *Engine, context: *c.JSContext) void {
        const exception = c.JS_GetException(context);
        defer c.JS_FreeValue(context, exception);
        self.captureValue(context, exception);
    }

    fn captureValue(self: *Engine, context: *c.JSContext, exception: c.JSValue) void {
        const text = c.JS_ToCString(context, exception);
        defer if (text != null) c.JS_FreeCString(context, text);
        const diagnostic_message = if (text == null) null else self.gpa.dupe(u8, std.mem.span(text)) catch null;
        // String conversion can invoke user code and another native callback.
        // Commit ownership only afterward, retaining the original thrown value.
        if (self.last_error) |message| self.gpa.free(message);
        self.last_error = diagnostic_message;
        if (self.captured_exception) |previous| self.freeValue(previous);
        self.captured_exception = c.JS_DupValue(context, exception);
        if (text == null and c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
    }

    fn interrupt(_: ?*c.JSRuntime, context_data: ?*anyopaque) callconv(.c) c_int {
        const self: *Engine = @ptrCast(@alignCast(context_data.?));
        if (self.cancelled.load(.acquire)) return 1;
        self.interrupts += 1;
        return if (self.interrupts > self.options.interrupt_budget) 1 else 0;
    }
};

test "native control pump settles an idle promise on its owner thread and bounds missing responses" {
    const Control = struct {
        polls: usize = 0,
        settle: bool = true,

        fn pump(engine: *Engine) !bool {
            const self: *@This() = @ptrCast(@alignCast(engine.host_control_context.?));
            self.polls += 1;
            if (!self.settle or self.polls < 2) return false;
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const resolve = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "ownedResolve"));
            defer engine.freeValue(resolve);
            var arguments = [_]c.JSValue{try engine.checked(c.JS_NewString(engine.context, "owner-settled"))};
            defer engine.freeValue(arguments[0]);
            const result = try engine.checked(c.JS_Call(engine.context, resolve, c.pi_js_undefined(), 1, &arguments));
            engine.freeValue(result);
            return true;
        }
    };
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 1000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var control: Control = .{};
    engine.host_control_context = &control;
    engine.host_control_pump = Control.pump;
    const pending = try engine.eval("new Promise(resolve=>globalThis.ownedResolve=resolve)", "owner-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("owner-settled", text);
    try std.testing.expectEqual(@as(usize, 2), control.polls);
    control.settle = false;
    engine.options.host_await_timeout_ms = 1;
    const unanswered = try engine.eval("new Promise(()=>{})", "owner-control-timeout.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(unanswered);
    try std.testing.expectError(error.NativeHostPromiseTimeout, engine.awaitValue(unanswered));
}

test "native rejected promises retain the original reason when diagnostic conversion throws" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const promise = try engine.eval("globalThis.rejectReason={toString(){throw Error('diagnostic conversion');}}; Promise.reject(rejectReason);", "native-rejection.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(promise));
    try std.testing.expect(!c.JS_HasException(engine.context));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const original = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "rejectReason"));
    defer engine.freeValue(original);
    _ = engine.throwCaptured();
    const thrown = c.JS_GetException(engine.context);
    defer engine.freeValue(thrown);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, thrown));
}

test "native DTO construction preserves nonfinite numbers and literal prototype and NUL keys" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var object: std.json.ObjectMap = .empty;
    try object.put(allocator, "nan", .{ .float = std.math.nan(f64) });
    try object.put(allocator, "__proto__", .{ .bool = true });
    try object.put(allocator, "nul\x00key", .{ .integer = 42 });
    const value = try engine.fromJsonValue(.{ .object = object });
    defer engine.freeValue(value);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try std.testing.expect(c.JS_DefinePropertyValueStr(engine.context, global, "nativeDto", c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) >= 0);
    const result = try engine.eval("if(!Number.isNaN(nativeDto.nan)||!Object.hasOwn(nativeDto,'__proto__')||Object.getPrototypeOf(nativeDto)!==Object.prototype||nativeDto['nul\\0key']!==42)throw Error('native DTO');", "native-dto.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
}

test "native import metadata distinguishes hosted modules from explicitly selected entrypoints" {
    for ([_]bool{ false, true }) |main| {
        const engine = try Engine.init(std.testing.allocator, .{ .main_module = main });
        defer engine.deinit();
        const filename = if (builtin.os.tag == .windows) "C:/native/input file.mjs" else "/native/input file.mjs";
        const result = try engine.evalModule("export const main=import.meta.main; export const url=import.meta.url;", filename);
        defer engine.freeValue(result);
        const value = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "main"));
        defer engine.freeValue(value);
        try std.testing.expectEqual(@as(c_int, @intFromBool(main)), c.JS_ToBool(engine.context, value));
        const url_value = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "url"));
        defer engine.freeValue(url_value);
        const url = try engine.toString(url_value);
        defer engine.gpa.free(url);
        try std.testing.expect(std.mem.endsWith(u8, url, "/native/input%20file.mjs"));
    }
}

test "native module allocation failures do not install hidden modules before retry" {
    for (0..4) |failure_offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try Engine.init(failing.allocator(), .{});
        defer engine.deinit();
        const exports = try engine.checked(c.JS_NewObject(engine.context));
        defer engine.freeValue(exports);
        try std.testing.expect(c.JS_DefinePropertyValueStr(engine.context, exports, "value", c.pi_js_int32(engine.context, 42), c.JS_PROP_C_W_E) >= 0);
        failing.fail_index = failing.alloc_index + failure_offset;
        try std.testing.expectError(error.OutOfMemory, engine.registerValueModule("native:retry", exports));
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expectError(error.JavaScriptException, engine.evalModule("import {value} from 'native:retry'; export const answer=value;", "missing-module-probe.js"));
        engine.beginInvocation();
        try engine.registerValueModule("native:retry", exports);
        const namespace = try engine.evalModule("import {value} from 'native:retry'; export const answer=value;", "healthy-module-probe.js");
        defer engine.freeValue(namespace);
        const answer = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "answer"));
        defer engine.freeValue(answer);
        var number: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &number, answer));
        try std.testing.expectEqual(@as(i32, 42), number);
        try std.testing.expectError(error.InvalidNativeModuleName, engine.registerValueModule("invalid\x00name", exports));
    }
}

test "linked C engine executes modern extension language without Node" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const value = try engine.eval("JSON.stringify({ value: 2 ** 5, text: 'hello 🌍', spread: [...new Set([1, 1, 2])] })", "fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const text = try engine.toString(value);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"value\":32,\"text\":\"hello 🌍\",\"spread\":[1,2]}", text);
}

test "linked C engine settles promises and async generator code" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const promise = try engine.eval("(async () => { async function* values() { yield 2; yield 3; } let total = 0; for await (const value of values()) total += value; return total; })()", "async-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const text = try engine.stringify(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("5", text);
}

test "linked C engine reports rejected promises and syntax errors" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.eval("const = invalid;", "invalid-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(engine.last_error != null);
    engine.beginInvocation();
    const promise = try engine.eval("Promise.reject(new Error('extension rejected'))", "rejected-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(promise));
    try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "extension rejected") != null);
}

test "linked C engine interrupts infinite loops and supports cancellation" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 2 });
    defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.eval("while (true) {}", "hostile-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    engine.beginInvocation();
    engine.cancel();
    try std.testing.expectError(error.JavaScriptException, engine.eval("while (true) {}", "cancel-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
}

test "native module loader resolves relative imports and top level await" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.registerModule("helpers/value.js", "export const value = 41;");
    const namespace = try engine.evalModule("import { value } from './helpers/value.js'; export const answer = await Promise.resolve(value + 1); export default (name) => `hello ${name}`;", "entry.js");
    defer engine.freeValue(namespace);
    const answer = c.JS_GetPropertyStr(engine.context, namespace, "answer");
    defer engine.freeValue(answer);
    const encoded = try engine.stringify(answer);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("42", encoded);
    const factory = c.JS_GetPropertyStr(engine.context, namespace, "default");
    defer engine.freeValue(factory);
    const name = c.JS_NewString(engine.context, "pi");
    defer engine.freeValue(name);
    var arguments = [_]c.JSValue{name};
    const result = try engine.checked(c.JS_Call(engine.context, factory, c.pi_js_undefined(), 1, &arguments));
    defer engine.freeValue(result);
    const greeting = try engine.toString(result);
    defer std.testing.allocator.free(greeting);
    try std.testing.expectEqualStrings("hello pi", greeting);
}

test "native module loader rejects missing dependencies and duplicate registrations" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.registerModule("helper.js", "export const value = 1;");
    try std.testing.expectError(error.DuplicateExtensionModule, engine.registerModule("helper.js", "export const value = 2;"));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("import './missing.js';", "missing-entry.js"));
    try std.testing.expect(engine.last_error != null);
}

test "extension calls a Zig host function through the direct C ABI" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const Add = struct {
        fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            if (argc != 2) return c.JS_ThrowTypeError(context, "nativeAdd expects two integer arguments");
            var left: i32 = 0;
            var right: i32 = 0;
            if (c.JS_ToInt32(context, &left, argv[0]) < 0 or c.JS_ToInt32(context, &right, argv[1]) < 0) return c.JS_ThrowTypeError(context, "nativeAdd expects integers");
            const value = std.math.add(i32, left, right) catch return c.JS_ThrowRangeError(context, "nativeAdd overflow");
            return c.pi_js_int32(context, value);
        }
    };
    try engine.bindFunction("nativeAdd", Add.call, 2);
    const value = try engine.eval("nativeAdd(19, 23)", "native-host-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const encoded = try engine.stringify(value);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("42", encoded);
    try std.testing.expectError(error.JavaScriptException, engine.eval("nativeAdd(1)", "native-argument-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
}

test "extension imports native object exports without a JavaScript bridge module" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const exports = c.JS_NewObject(engine.context);
    defer engine.freeValue(exports);
    try std.testing.expect(c.JS_SetPropertyStr(engine.context, exports, "answer", c.pi_js_int32(engine.context, 42)) >= 0);
    try engine.registerValueModule("@pi/native", exports);
    try std.testing.expectError(error.DuplicateExtensionModule, engine.registerValueModule("@pi/native", exports));
    try std.testing.expectError(error.DuplicateExtensionModule, engine.registerModule("@pi/native", "export const answer = 0;"));
    const namespace = try engine.evalModule("import { answer } from '@pi/native'; export const result = answer;", "native-import.js");
    defer engine.freeValue(namespace);
    const result = c.JS_GetPropertyStr(engine.context, namespace, "result");
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("42", encoded);
}
