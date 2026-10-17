//! Explicit Windows TTY builtin assembly; never selected by Engine bootstrap.
//! Compose only with the canonical Socket/Hub/Scheduler/Wake/ClosePool modules.
//! Private cache publication precedes the LAST fallible adopter commit. Public
//! immutable C-module publication is a separate, sticky transaction.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const colors = @import("native_node_tty_colors.zig");
const inspect = @import("native_node_util_inspect.zig");
const bundle_module = @import("native_node_readline_errors.zig");
const frontend = @import("native_node_tty_frontend_mode.zig");
const Cleanup = @import("native_node_tty_assembly_cleanup.zig").Cleanup;

/// Capture at pristine bootstrap, BEFORE admitting user modules. The retained
/// functions are the actual runtime primordials, never executable host JS.
pub const Primordials = struct {
    engine: *v.em.Engine,
    colors: colors.Primordials,
    inspect: inspect.Inputs,
    json_stringify: c.JSValue,
    string_slice: c.JSValue,
    string_index_of: c.JSValue,
    pub fn deinit(self: Primordials) void {
        self.colors.deinit(self.engine); self.inspect.deinit(self.engine);
        self.engine.freeValue(self.json_stringify);
        self.engine.freeValue(self.string_slice); self.engine.freeValue(self.string_index_of);
    }
};
pub fn capturePrimordials(engine: *v.em.Engine) !Primordials {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    const color_inputs = try colors.capturePrimordials(engine); errdefer color_inputs.deinit(engine);
    const inspect_inputs = try inspect.capturePrimordials(engine); errdefer inspect_inputs.deinit(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const prototype = try h.get(&s, inspect_inputs.string, "prototype");
    const slice = try h.get(&s, prototype, "slice"); const index = try h.get(&s, prototype, "indexOf");
    const json = try s.own(try h.success(engine, try v.js.global(engine, "JSON")));
    const stringify = try h.get(&s, json, "stringify");
    inline for (.{ slice, index, stringify }) |function| if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualTtyAssemblyPrimordial;
    return .{ .engine = engine, .colors = color_inputs, .inspect = inspect_inputs,
        .json_stringify = c.JS_DupValue(engine.context, stringify), .string_slice = c.JS_DupValue(engine.context, slice), .string_index_of = c.JS_DupValue(engine.context, index) };
}

pub fn Assembly(comptime Socket: type, comptime Hub: type, comptime Scheduler: type, comptime Wake: type, comptime ClosePool: type) type {
    return struct {
        const Self = @This();
        const Native = @import("native_node_tty_windows_owner.zig").Owner(Socket, Hub, Scheduler, Wake, ClosePool);
        const Binding = @import("native_node_tty_binding.zig").Binding(Socket, Native);
        // Distinct concrete module compositions must never cast one another's
        // native holders, even if someone instantiates a second generic type.
        const key = "#pi-native:actual-tty-assembly/" ++ @typeName(Self);
        const Phase = enum { initializing, ready, publishing, published, publication_failed };
        pub const Inputs = struct {
            canonical_socket: *const Socket.Provider,
            actual_net: c.JSValue,
            actual_process: c.JSValue,
            /// Real physical caller filename for node:module.createRequire.
            /// Resolving a source file is not replaced by a fake require table.
            physical_filename: c.JSValue,
            primordials: *const Primordials,
            frontend_mode: ?frontend.Snapshot = null,
            /// Explicit future owned target only; never inferred from isTTY
            /// hydration or supplied by a guest/remote framed worker.
            qualification_admission: bool = false,
        };
        pub const Exports = struct {
            tty: c.JSValue, util: c.JSValue, readline: c.JSValue, net: c.JSValue,
            tty_exports: c.JSValue, util_exports: c.JSValue, readline_exports: c.JSValue, net_exports: c.JSValue,
            /// Private, unregistered carrier objects; these are not exposed as
            /// invented complete internal modules or mutable registry cells.
            tty_wrap: c.JSValue, internal_inspect: c.JSValue, codes: c.JSValue,
            pub fn deinit(self: Exports, engine: *v.em.Engine) void {
                inline for (std.meta.fields(Exports)) |field| engine.freeValue(@field(self, field.name));
            }
        };
        const Identity = struct { net: c.JSValue, process: c.JSValue, filename: c.JSValue, socket: c.JSValue, states: c.JSValue };
        const State = struct {
            engine: *v.em.Engine, class_id: c.JSClassID, phase: Phase = .initializing,
            canonical_socket: *const Socket.Provider,
            frontend_mode: ?frontend.Snapshot,
            qualification_admission: bool,
            identity: Identity,
            exports: Exports,
            actual_require: c.JSValue,
            primordial_roots: c.JSValue,
            bundle: ?bundle_module.Exports = null,
            native: ?*Native.Provider = null,
            binding: ?Binding.Prepared = null,
            failure: ?anyerror = null,
            failure_reason: ?c.JSValue = null,
            net_canonical_registered: bool = false,
            net_bare_registered: bool = false,
        };
        fn emptyExports() Exports {
            var result: Exports = undefined;
            inline for (std.meta.fields(Exports)) |field| @field(result, field.name) = c.pi_js_undefined();
            return result;
        }
        fn visitBundle(runtime: ?*c.JSRuntime, bundle: bundle_module.Exports, marker: ?*const c.JS_MarkFunc, comptime release: bool) void {
            inline for (.{ "codes", "tty", "util" }) |name| {
                inline for (std.meta.fields(@TypeOf(@field(bundle, name)))) |field| {
                    const value = @field(@field(bundle, name), field.name);
                    if (release) c.JS_FreeValueRT(runtime, value) else c.JS_MarkValue(runtime, value, marker);
                }
            }
            inline for (.{ "invalid_arg_value", "invalid_cursor_pos", "validate_function" }) |name| {
                if (release) c.JS_FreeValueRT(runtime, @field(bundle, name)) else c.JS_MarkValue(runtime, @field(bundle, name), marker);
            }
        }
        fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
            // An uncommitted native resource has never been exposed through
            // an adopter. Remove its real Hub ownership on failed assembly.
            if (state.native) |native| {
                if (state.binding == null or !state.binding.?.committed) native.rollbackUnpublished();
                native.release();
            }
            if (state.binding) |binding| {
                c.JS_FreeValueRT(runtime, binding.exports.tty); c.JS_FreeValueRT(runtime, binding.exports.is_tty); c.JS_FreeValueRT(runtime, binding.owner);
            }
            if (state.bundle) |bundle| visitBundle(runtime, bundle, null, true);
            inline for (std.meta.fields(Identity)) |field| c.JS_FreeValueRT(runtime, @field(state.identity, field.name));
            inline for (std.meta.fields(Exports)) |field| c.JS_FreeValueRT(runtime, @field(state.exports, field.name));
            c.JS_FreeValueRT(runtime, state.actual_require); c.JS_FreeValueRT(runtime, state.primordial_roots);
            if (state.failure_reason) |reason| c.JS_FreeValueRT(runtime, reason);
            const engine = state.engine; engine.gpa.destroy(state);
            c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
        }
        fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
            if (state.binding) |binding| {
                c.JS_MarkValue(runtime, binding.exports.tty, marker); c.JS_MarkValue(runtime, binding.exports.is_tty, marker); c.JS_MarkValue(runtime, binding.owner, marker);
                // binding.owner marks the native provider's owned JS edges.
                // The extra native reference is NOT another set of JS roots.
            }
            if (state.bundle) |bundle| visitBundle(runtime, bundle, marker, false);
            inline for (std.meta.fields(Identity)) |field| c.JS_MarkValue(runtime, @field(state.identity, field.name), marker);
            inline for (std.meta.fields(Exports)) |field| c.JS_MarkValue(runtime, @field(state.exports, field.name), marker);
            c.JS_MarkValue(runtime, state.actual_require, marker); c.JS_MarkValue(runtime, state.primordial_roots, marker);
            if (state.failure_reason) |reason| c.JS_MarkValue(runtime, reason, marker);
        }
        fn stateOf(engine: *v.em.Engine, holder: c.JSValue) !*State {
            // Only this private, unregistered key admits this holder. No guest
            // property supplies either the opaque value or its expected brand.
            const id = c.JS_GetClassID(holder);
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, id) orelse return error.InvalidActualTtyAssemblyOwner));
            if (state.engine != engine or state.class_id != id) return error.ForeignActualTtyAssemblyOwner;
            return state;
        }
        fn duplicate(engine: *v.em.Engine, exports: Exports) Exports {
            var result: Exports = undefined;
            inline for (std.meta.fields(Exports)) |field| @field(result, field.name) = c.JS_DupValue(engine.context, @field(exports, field.name));
            return result;
        }
        fn makeHolder(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
            if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
            var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
            const state = try engine.gpa.create(State); errdefer if (!attached) engine.gpa.destroy(state);
            var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
            const definition: c.JSClassDef = .{ .class_name = "Private genuine TTY builtin assembly", .finalizer = finalize, .gc_mark = mark };
            if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
            const holder = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), id));
            state.* = .{ .engine = engine, .class_id = id, .canonical_socket = inputs.canonical_socket, .frontend_mode = inputs.frontend_mode, .qualification_admission = inputs.qualification_admission,
                .identity = .{ .net = c.JS_DupValue(engine.context, inputs.actual_net), .process = c.JS_DupValue(engine.context, inputs.actual_process), .filename = c.JS_DupValue(engine.context, inputs.physical_filename),
                    .socket = c.JS_DupValue(engine.context, inputs.canonical_socket.constructor), .states = c.JS_DupValue(engine.context, inputs.canonical_socket.states) },
                .exports = emptyExports(), .actual_require = c.pi_js_undefined(), .primordial_roots = c.pi_js_undefined() };
            _ = c.JS_SetOpaque(holder, state); attached = true; return holder;
        }
        fn sameInputs(engine: *v.em.Engine, state: *State, inputs: Inputs) !void {
            if (state.canonical_socket != inputs.canonical_socket or !std.meta.eql(state.frontend_mode, inputs.frontend_mode) or state.qualification_admission != inputs.qualification_admission) return error.ActualTtyAssemblyNativeAuthorityChanged;
            const actual: Identity = .{ .net = inputs.actual_net, .process = inputs.actual_process, .filename = inputs.physical_filename, .socket = inputs.canonical_socket.constructor, .states = inputs.canonical_socket.states };
            inline for (std.meta.fields(Identity)) |field| if (!c.JS_IsStrictEqual(engine.context, @field(state.identity, field.name), @field(actual, field.name))) return error.ActualTtyAssemblyImportsChanged;
            var s: v.Scope = .{ .engine = engine }; defer s.deinit();
            inline for (std.meta.fields(colors.Primordials)) |field| if (!c.JS_IsStrictEqual(engine.context, try h.get(&s, state.primordial_roots, "colors/" ++ field.name), @field(inputs.primordials.colors, field.name))) return error.ActualTtyAssemblyPrimordialsChanged;
            inline for (std.meta.fields(inspect.Inputs)) |field| if (!c.JS_IsStrictEqual(engine.context, try h.get(&s, state.primordial_roots, "inspect/" ++ field.name), @field(inputs.primordials.inspect, field.name))) return error.ActualTtyAssemblyPrimordialsChanged;
            inline for (.{ "json_stringify", "string_slice", "string_index_of" }) |name| if (!c.JS_IsStrictEqual(engine.context, try h.get(&s, state.primordial_roots, name), @field(inputs.primordials.*, name))) return error.ActualTtyAssemblyPrimordialsChanged;
        }
        fn retainPrimordials(engine: *v.em.Engine, inputs: *const Primordials) !c.JSValue {
            var s: v.Scope = .{ .engine = engine }; defer s.deinit();
            const roots = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
            inline for (std.meta.fields(colors.Primordials)) |field| try h.put(engine, roots, "colors/" ++ field.name, @field(inputs.colors, field.name));
            inline for (std.meta.fields(inspect.Inputs)) |field| try h.put(engine, roots, "inspect/" ++ field.name, @field(inputs.inspect, field.name));
            inline for (.{ "json_stringify", "string_slice", "string_index_of" }) |name| try h.put(engine, roots, name, @field(inputs, name));
            return c.JS_DupValue(engine.context, roots);
        }
        const Temporaries = struct {
            scope: v.Scope,
            messages: ?@import("native_node_tty_error_messages.zig").Exports = null,
            colors: ?colors.Exports = null,
            fn retire(self: *Temporaries, cleanup: *Cleanup) void {
                if (self.messages) |messages| {
                    self.messages = null;
                    inline for (std.meta.fields(@TypeOf(messages))) |field| cleanup.release(@field(messages, field.name));
                }
                if (self.colors) |methods| {
                    self.colors = null;
                    inline for (std.meta.fields(@TypeOf(methods))) |field| cleanup.release(@field(methods, field.name));
                }
                cleanup.scope(&self.scope);
            }
        };
        fn retireState(state: *State, cleanup: *Cleanup) void {
            // Retire owned values individually with BOTH exception slots empty.
            // Holder finalization afterward sees only undefined/null fields.
            if (state.native) |native| {
                state.native = null;
                const generation = cleanup.engine.native_allocation_generation;
                native.rollbackUnpublished(); native.release();
                cleanup.collect(generation);
            }
            if (state.binding) |binding| {
                state.binding = null;
                cleanup.release(binding.exports.tty); cleanup.release(binding.exports.is_tty); cleanup.release(binding.owner);
            }
            if (state.bundle) |bundle| {
                state.bundle = null;
                inline for (.{ "codes", "tty", "util" }) |name| {
                    inline for (std.meta.fields(@TypeOf(@field(bundle, name)))) |field| cleanup.release(@field(@field(bundle, name), field.name));
                }
                inline for (.{ "invalid_arg_value", "invalid_cursor_pos", "validate_function" }) |name| cleanup.release(@field(bundle, name));
            }
            inline for (std.meta.fields(Identity)) |field| { const value = @field(state.identity, field.name); @field(state.identity, field.name) = c.pi_js_undefined(); cleanup.release(value); }
            inline for (std.meta.fields(Exports)) |field| { const value = @field(state.exports, field.name); @field(state.exports, field.name) = c.pi_js_undefined(); cleanup.release(value); }
            const require = state.actual_require; state.actual_require = c.pi_js_undefined(); cleanup.release(require);
            const roots = state.primordial_roots; state.primordial_roots = c.pi_js_undefined(); cleanup.release(roots);
            if (state.failure_reason) |reason| { state.failure_reason = null; cleanup.release(reason); }
        }
        fn own(s: *v.Scope, cleanup: *Cleanup, owned: c.JSValue, generation: u64) !c.JSValue {
            return s.own(try cleanup.takeOwned(owned, generation));
        }
        fn get(s: *v.Scope, cleanup: *Cleanup, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
            const generation = s.engine.native_allocation_generation;
            return own(s, cleanup, c.JS_GetPropertyStr(s.engine.context, receiver, name), generation);
        }
        fn call(s: *v.Scope, cleanup: *Cleanup, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
            const generation = s.engine.native_allocation_generation;
            return own(s, cleanup, c.JS_Call(s.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation);
        }
        fn global(s: *v.Scope, cleanup: *Cleanup, name: [*:0]const u8) !c.JSValue {
            const generation = s.engine.native_allocation_generation;
            const object = try own(s, cleanup, c.JS_GetGlobalObject(s.engine.context), generation);
            return get(s, cleanup, object, name);
        }
        fn registeredBuiltin(s: *v.Scope, cleanup: *Cleanup, name: []const u8) !c.JSValue {
            // Mirror the actual Engine requireBuiltin guard/default fallback,
            // intercepting its RAW owned result before Bfb.checked can retire
            // success+pending. This never exposes an unregistered private key.
            const engine = s.engine;
            if (std.fs.path.isAbsolute(name)) return error.RequiredActualTtyBuiltin;
            const canonical = engine.native_builtin_aliases.get(name) orelse name;
            if (!engine.native_module_names.contains(canonical)) return error.RequiredActualTtyBuiltin;
            const record = engine.native_module_values.get(canonical) orelse return error.RequiredActualTtyBuiltin;
            const value = try get(s, cleanup, record, "default");
            if (!c.JS_IsUndefined(value)) return value;
            return s.own(c.JS_DupValue(engine.context, record));
        }
        fn defaultExports(s: *v.Scope, cleanup: *Cleanup, object: c.JSValue) !c.JSValue {
            // Same actual export-record/default semantics as Engine, but raw
            // enumerable getters are normalized BEFORE checked/next key. Do
            // not keep duplicate field roots past Define's consuming call.
            const engine = s.engine;
            const allocation_generation = engine.native_allocation_generation;
            const record = try own(s, cleanup, c.JS_NewObject(engine.context), allocation_generation);
            if (c.JS_IsObject(object)) {
                var properties: [*c]c.JSPropertyEnum = null;
                var count: u32 = 0;
                const generation = engine.native_allocation_generation;
                const status = c.JS_GetOwnPropertyNames(engine.context, &properties, &count, object, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY);
                if (status < 0) { cleanup.collect(generation); return error.JavaScriptException; }
                // This array owns atoms only, no JS descriptor-field values.
                defer c.JS_FreePropertyEnum(engine.context, properties, count);
                try statusBoundary(engine, cleanup, status, generation);
                for (0..count) |index| {
                    const read_generation = engine.native_allocation_generation;
                    const value = try cleanup.takeOwned(c.JS_GetProperty(engine.context, object, properties[index].atom), read_generation);
                    const define_generation = engine.native_allocation_generation;
                    const defined = c.JS_DefinePropertyValue(engine.context, record, properties[index].atom, value, c.JS_PROP_C_W_E);
                    // Define consumes value on BOTH success and failure.
                    try statusBoundary(engine, cleanup, defined, define_generation);
                }
            }
            const generation = engine.native_allocation_generation;
            const defined = c.JS_DefinePropertyValueStr(engine.context, record, "default", c.JS_DupValue(engine.context, object), c.JS_PROP_C_W_E);
            try statusBoundary(engine, cleanup, defined, generation);
            return c.JS_DupValue(engine.context, record);
        }
        fn statusBoundary(engine: *v.em.Engine, cleanup: *Cleanup, status: c_int, generation: u64) !void {
            // A successful native integer hook can have captured a NEW actual
            // event with no VM pending value. Older history is outside both
            // slots; stop here before another getter/default construction.
            if (status < 0 or c.JS_HasException(engine.context) or engine.captured_exception != null) {
                cleanup.collect(generation); return error.JavaScriptException;
            }
            // Also preserve a producer retained only by a live Bfb invocation.
            engine.checkNativeEntry() catch |err| { cleanup.collect(generation); return err; };
        }
        fn prepare(engine: *v.em.Engine, state: *State, inputs: Inputs, temporaries: *Temporaries, cleanup: *Cleanup) !void {
            const s = &temporaries.scope;
            const actual_process = try global(s, cleanup, "process");
            if (!c.JS_IsStrictEqual(engine.context, actual_process, inputs.actual_process) or !c.JS_IsFunction(engine.context, try get(s, cleanup, actual_process, "nextTick"))) return error.RequiredActualTtyProcessTicks;
            if (!c.JS_IsObject(inputs.actual_net) or !c.JS_IsStrictEqual(engine.context, try get(s, cleanup, inputs.actual_net, "Socket"), inputs.canonical_socket.constructor)) return error.RequiredCanonicalTtySocketCarrier;
            // This actual carrier contains genuine Socket/Stream constructor
            // aliases. TCP/Server/connect remain outside this selected profile.
            // Existing genuine records are reused, never replaced by a clone.
            if (engine.modules.contains("net") or engine.modules.contains("node:net")) return error.ActualTtyNetSourceModuleConflict;
            state.net_canonical_registered = engine.native_module_names.contains("node:net");
            state.net_bare_registered = engine.native_module_names.contains("net") or engine.native_builtin_aliases.contains("net");
            if (state.net_canonical_registered) {
                const record = engine.native_module_values.get("node:net") orelse return error.RequiredActualTtyNetRecord;
                if (!c.JS_IsStrictEqual(engine.context, try get(s, cleanup, record, "default"), inputs.actual_net)) return error.ActualTtyNetCarrierMismatch;
            }
            if (state.net_bare_registered) {
                const canonical = engine.native_builtin_aliases.get("net") orelse "net";
                const record = engine.native_module_values.get(canonical) orelse return error.RequiredActualTtyNetRecord;
                if (!c.JS_IsStrictEqual(engine.context, try get(s, cleanup, record, "default"), inputs.actual_net)) return error.ActualTtyNetCarrierMismatch;
            }
            state.exports.net = c.JS_DupValue(engine.context, inputs.actual_net);
            state.exports.net_exports = if (state.net_canonical_registered) c.JS_DupValue(engine.context, engine.native_module_values.get("node:net").?) else try defaultExports(s, cleanup, inputs.actual_net);
            // Actual CJS implementation performs normalization and builtin
            // lookup. No locally fabricated require dispatcher is installed.
            const node_module = try registeredBuiltin(s, cleanup, "node:module");
            const create_require = try get(s, cleanup, node_module, "createRequire");
            if (!c.JS_IsFunction(engine.context, create_require)) return error.RequiredActualNodeModuleCreateRequire;
            state.actual_require = c.JS_DupValue(engine.context, try call(s, cleanup, create_require, node_module, &.{inputs.physical_filename}));
            // Require actual dependency registration, without a live default/
            // release getter. Source loads os/release LAZILY at the color call.
            if (!engine.native_module_names.contains("os") or !engine.native_module_values.contains("os")) return error.RequiredActualNodeOsForTtyColors;
            state.primordial_roots = try retainPrimordials(engine, inputs.primordials);
            state.exports.internal_inspect = try @import("native_node_util_tty_dependencies.zig").createPrivateInspect(engine, inputs.primordials.inspect);
            temporaries.messages = try @import("native_node_tty_error_messages.zig").create(engine, .{ .internal_inspect = state.exports.internal_inspect,
                .string = inputs.primordials.inspect.string, .number_is_integer = inputs.primordials.colors.number_is_integer,
                .json_stringify = inputs.primordials.json_stringify, .string_slice = inputs.primordials.string_slice, .string_index_of = inputs.primordials.string_index_of });
            state.bundle = try bundle_module.create(engine, .{ .messages = temporaries.messages.?, .internal_inspect = state.exports.internal_inspect, .require = state.actual_require });
            const bundle = state.bundle.?;
            state.exports.codes = try engine.checked(c.JS_NewObject(engine.context));
            inline for (.{ .{ "ERR_INVALID_FD_TYPE", "invalid_fd" }, .{ "ERR_INVALID_ARG_TYPE", "invalid_arg_type" }, .{ "ERR_OUT_OF_RANGE", "out_of_range" }, .{ "ERR_TTY_INIT_FAILED", "tty_init_failed" } }) |pair| try h.put(engine, state.exports.codes, pair[0], @field(bundle.codes, pair[1]));
            state.exports.util = try engine.checked(c.JS_NewObject(engine.context));
            try @import("native_node_util_tty_dependencies.zig").installRequired(engine, state.exports.util, state.exports.internal_inspect, bundle.util);
            state.exports.readline = try @import("native_node_readline_callbacks.zig").create(engine, .{ .validate_function = bundle.validate_function, .invalid_arg_value = bundle.invalid_arg_value, .invalid_cursor_pos = bundle.invalid_cursor_pos });
            state.native = try Native.Provider.create(engine, inputs.canonical_socket, .{ .errno_exception = bundle.tty.errno_exception, .process = actual_process, .frontend_mode = inputs.frontend_mode, .qualification_admission = inputs.qualification_admission });
            state.binding = try Binding.prepare(engine, &state.native.?.socket, state.native.?);
            state.exports.tty_wrap = try engine.checked(c.JS_NewObject(engine.context));
            try h.put(engine, state.exports.tty_wrap, "TTY", state.binding.?.exports.tty); try h.put(engine, state.exports.tty_wrap, "isTTY", state.binding.?.exports.is_tty);
            const validator = try s.own(try colors.createValidator(engine, inputs.primordials.colors.number_is_integer, bundle.tty.invalid_arg_type, bundle.tty.out_of_range));
            temporaries.colors = try colors.create(engine, .{ .require = state.actual_require, .validate_integer = validator,
                .string_split = inputs.primordials.colors.string_split, .string_lower = inputs.primordials.colors.string_lower,
                .regexp_exec = inputs.primordials.colors.regexp_exec, .regexp_constructor = inputs.primordials.colors.regexp_constructor, .has_own = inputs.primordials.colors.has_own });
            state.exports.tty = try @import("native_node_tty.zig").create(engine, .{ .net = inputs.actual_net,
                .tty_constructor = state.binding.?.exports.tty, .is_tty = state.binding.?.exports.is_tty,
                .invalid_fd = bundle.tty.invalid_fd, .tty_init_failed = bundle.tty.tty_init_failed, .errno_exception = bundle.tty.errno_exception,
                .require = state.actual_require, .number_is_integer = inputs.primordials.colors.number_is_integer, .colors = temporaries.colors.? });
            state.exports.tty_exports = try defaultExports(s, cleanup, state.exports.tty);
            state.exports.util_exports = try defaultExports(s, cleanup, state.exports.util);
            state.exports.readline_exports = try defaultExports(s, cleanup, state.exports.readline);
            // Return through every temporary cleanup BEFORE adopter commit.
            // In particular Scope and color/message exports retire here.
        }
        /// Construct once, without registering any public module. Only a real
        /// owner can opt into this entry; Engine/default bootstrap never does.
        pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
            engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
            try engine.checkNativeEntry();
            if (@import("builtin").os.tag != .windows) return error.RequiredActualPlatformTtyAssembly;
            if (inputs.primordials.engine != engine) return error.ForeignActualTtyPrimordials;
            if (engine.native_module_values.get(key)) |holder| {
                const state = try stateOf(engine, holder);
                if (state.phase == .initializing or state.phase == .publishing) return error.ActualTtyAssemblyInitializing;
                try sameInputs(engine, state, inputs);
                return duplicate(engine, state.exports);
            }
            try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
            var cleanup = Cleanup.begin(engine);
            const generation = engine.native_allocation_generation;
            const holder = makeHolder(engine, inputs) catch |err| {
                cleanup.collect(generation);
                try cleanup.finish(err); unreachable;
            };
            engine.native_module_values.putAssumeCapacity(key, c.JS_DupValue(engine.context, holder));
            // makeHolder creates this exact private native brand; no guest can
            // replace the map entry before this immediate opaque lookup.
            const state = stateOf(engine, holder) catch unreachable;
            var temporaries: Temporaries = .{ .scope = .{ .engine = engine } };
            var failure: ?anyerror = null;
            prepare(engine, state, inputs, &temporaries, &cleanup) catch |err| { failure = err; };
            cleanup.collect(generation);
            temporaries.retire(&cleanup);
            if (failure != null or cleanup.selected != null) return rollback(engine, holder, state, &cleanup, failure);
            // The cache holder and ALL retained JS/native roots are live;
            // prepare's temporary cleanups have finished. No later allocation
            // or guest operation can consume a second adopter on retry.
            state.binding.?.commit() catch |err| {
                cleanup.collect(generation); return rollback(engine, holder, state, &cleanup, err);
            };
            state.phase = .ready;
            cleanup.restoreHistory();
            engine.freeValue(holder); // private map still owns this holder.
            return duplicate(engine, state.exports);
        }
        fn rollback(engine: *v.em.Engine, holder: c.JSValue, state: *State, cleanup: *Cleanup, failure: ?anyerror) anyerror {
            retireState(state, cleanup);
            if (engine.native_module_values.fetchRemove(key)) |entry| cleanup.release(entry.value);
            cleanup.release(holder); // empty native holder; no hidden JS roots.
            cleanup.finish(failure) catch |actual| return actual;
            unreachable;
        }
        /// Explicit publication only. All aliases share the SAME default
        /// carrier/constructors/functions. Engine creates real ESM namespaces;
        /// this function does not emulate them with ordinary JS objects.
        pub fn install(engine: *v.em.Engine, inputs: Inputs) !Exports {
            engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
            try engine.checkNativeEntry();
            const exports = try create(engine, inputs); errdefer exports.deinit(engine);
            const state = try stateOf(engine, engine.native_module_values.get(key).?);
            if (state.phase == .published) return exports;
            if (state.phase == .publication_failed) {
                if (state.failure_reason) |reason| return h.throwValue(engine, reason);
                return state.failure.?;
            }
            // Conflicting prior installations are not replaced or relabeled.
            inline for (.{ "node:util", "util", "node:readline", "readline", "node:tty", "tty" }) |name| if (engine.native_module_names.contains(name) or engine.native_builtin_aliases.contains(name) or engine.modules.contains(name)) return error.ActualTtyBuiltinAlreadyInstalled;
            // Host registration cannot silently switch after private assembly.
            // There is no public unregister/retry of an immutable C module.
            if (state.net_canonical_registered != engine.native_module_names.contains("node:net") or state.net_bare_registered != (engine.native_module_names.contains("net") or engine.native_builtin_aliases.contains("net")) or engine.modules.contains("net") or engine.modules.contains("node:net")) return error.ActualTtyNetRegistrationChanged;
            state.phase = .publishing;
            publish(engine, state) catch |err| {
                // Existing Engine contract cannot undo an immutable C module.
                // Retain completed graph/adopter and exact captured reason;
                // never allocate another class/brand or pretend retry worked.
                state.failure = err;
                if (c.JS_HasException(engine.context)) {
                    const reason = c.JS_GetException(engine.context);
                    state.failure_reason = c.JS_DupValue(engine.context, reason);
                    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch {};
                } else if (err == error.JavaScriptException) {
                    // registerValueModule captures only its actual failing VM
                    // event. A host allocation error must not relabel an old
                    // captured-history value as this publication's reason.
                    if (engine.captured_exception) |reason| state.failure_reason = c.JS_DupValue(engine.context, reason);
                }
                state.phase = .publication_failed; return err;
            };
            state.phase = .published; return exports;
        }
        fn publish(engine: *v.em.Engine, state: *State) !void {
            const exports = state.exports;
            if (!state.net_canonical_registered) try engine.registerValueModule("node:net", exports.net_exports);
            if (!state.net_bare_registered) try engine.registerBuiltinAlias("net", "node:net");
            try engine.registerValueModule("node:util", exports.util_exports); try engine.registerBuiltinAlias("util", "node:util");
            try engine.registerValueModule("node:readline", exports.readline_exports); try engine.registerBuiltinAlias("readline", "node:readline");
            try engine.registerValueModule("node:tty", exports.tty_exports); try engine.registerBuiltinAlias("tty", "node:tty");
        }
    };
}
