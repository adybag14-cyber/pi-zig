//! Production composition of the actual ordinary AgentSession class.
//! Imports capture genuine AI/manager functions; no legacy AgentSession object,
//! placeholder Models, empty builtin registry, or missing method is supplied.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
const order = @import("native_sdk_session_declaration_order.zig");

pub const InstallSessionExports = *const fn (*em.Engine, c.JSValue, c.JSValue) anyerror!void;
pub const Inputs = struct {
    /// Actual configurable pi-ai namespace (createModels/createProvider).
    ai: c.JSValue,
    /// Actual shared pi-ai/compat dispatch namespace with all ten builtins.
    compat: c.JSValue,
    /// Existing native SDK namespace supplies its actual SessionManager identity.
    sdk_namespace: c.JSValue,
    /// Optional already-created native_sdk_session_ai_assembly result.
    shared_ai: c.JSValue,
    /// Actual native platform installer; null is a hard incomplete-composition
    /// error, never a request to invent executeBash/export methods.
    install_session_exports: ?InstallSessionExports,
};

fn requireFunction(scope: *Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue {
    if (!c.JS_IsObject(namespace)) return error.RequiredActualNativeNamespace;
    const value = try scope.get(namespace, name);
    if (!c.JS_IsFunction(scope.engine.context, value)) return error.RequiredActualNativeNamespaceBinding;
    return value;
}
pub fn validateInputs(engine: *em.Engine, inputs: Inputs) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // These checks establish composition prerequisites, not provenance or full
    // transport qualification. The application supplies the actual assembly.
    inline for (.{ "createModels", "createProvider" }) |name| _ = try requireFunction(&scope, inputs.ai, name);
    inline for (.{ "streamSimple", "completeSimple", "resetApiProviders", "getApiProviders" }) |name| _ = try requireFunction(&scope, inputs.compat, name);
    _ = try requireFunction(&scope, inputs.sdk_namespace, "SessionManager");
    if (inputs.install_session_exports == null) return error.RequiredActualNativeSessionPlatformAssembly;
    try validateBuiltinProviders(&scope, inputs.compat);
    if (!temp.nullish(inputs.shared_ai)) {
        inline for (.{ "completeSummarization", "compact", "resetApiProviders" }) |name| _ = try requireFunction(&scope, inputs.shared_ai, name);
        const reset = try scope.get(inputs.shared_ai, "resetApiProviders");
        if (!scope.equal(reset, try scope.get(inputs.compat, "resetApiProviders"))) return error.SharedNativeAiProviderIdentityMismatch;
        const branch = try scope.get(inputs.shared_ai, "branchSummary");
        inline for (.{ "collectEntriesForBranchSummary", "generateBranchSummary" }) |name| _ = try requireFunction(&scope, branch, name);
    }
}
fn validateBuiltinProviders(scope: *Scope, compat: c.JSValue) !void {
    const ids = @import("native_ai_compat.zig").builtin_api_ids;
    var found = [_]bool{false} ** ids.len;
    const providers = try scope.invoke(compat, "getApiProviders", &.{});
    var iterator = try js.Iterator.init(scope.engine, providers, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |provider| {
        defer scope.engine.freeValue(provider);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const api = try row.get(provider, "api");
        inline for (ids, 0..) |name, index| {
            if (row.equal(api, try row.text(name))) {
                _ = try requireFunction(&row, provider, "stream");
                _ = try requireFunction(&row, provider, "streamSimple");
                found[index] = true;
            }
        }
    }
    for (found) |present| if (!present) return error.RequiredAllActualNativeBuiltinProviders;
}

/// Returns a new ordinary class whose constructor executes the actual Source
/// declarations/config/hook/runtime/restore phases. It inherits no SDK.State
/// AgentSession prototype and does not construct a model/provider substitute.
pub fn constructor(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    try validateInputs(engine, inputs);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const shared = if (temp.nullish(inputs.shared_ai)) try scope.own(try @import("native_sdk_session_ai_assembly.zig").create(engine, inputs.compat)) else inputs.shared_ai;
    const dependencies = try scope.object();
    try scope.put(dependencies, "streamSimple", try requireFunction(&scope, inputs.compat, "streamSimple"));
    try scope.put(dependencies, "SessionManager", try requireFunction(&scope, inputs.sdk_namespace, "SessionManager"));
    try scope.put(dependencies, "convertToLlm", try scope.own(try @import("native_sdk_messages.zig").create(engine)));
    try scope.put(dependencies, "normalizeToolResultImages", try scope.own(try @import("native_sdk_tool_result_images.zig").create(engine)));
    try scope.put(dependencies, "NestedToolCallRunner", try scope.own(try @import("native_nested_tool_calls.zig").constructor(engine)));
    try scope.put(dependencies, "runToolCall", try scope.own(try @import("native_agent_single_tool.zig").create(engine)));
    try @import("native_sdk_session_estimate.zig").install(engine, dependencies);
    const staging = try scope.object();
    try installOrdinary(engine, staging, dependencies, shared, inputs.install_session_exports.?);
    const prototype = try scope.object();
    const result = try scope.own(try @import("native_sdk_session_construct.zig").constructor(engine, prototype));
    inline for (order.names) |name| try copyOwnMethod(engine, staging, prototype, name);
    return c.JS_DupValue(engine.context, result);
}
fn installOrdinary(engine: *em.Engine, prototype: c.JSValue, dependencies: c.JSValue, shared: c.JSValue, platform: InstallSessionExports) !void {
    inline for (.{
        @import("native_sdk_session_public_values.zig"),   @import("native_sdk_session_queries.zig"),
        @import("native_sdk_session_utilities.zig"),       @import("native_sdk_session_events.zig"),
        @import("native_sdk_session_control.zig"),         @import("native_sdk_session_queue.zig"),
        @import("native_sdk_session_models.zig"),          @import("native_sdk_session_prepare.zig"),
        @import("native_sdk_session_prompt.zig"),          @import("native_sdk_session_prompt_images.zig"),
        @import("native_sdk_session_prompt_handlers.zig"), @import("native_sdk_session_post_run.zig"),
        @import("native_sdk_session_run.zig"),             @import("native_sdk_session_settled.zig"),
        @import("native_sdk_session_retry.zig"),           @import("native_sdk_session_statistics.zig"),
        @import("native_sdk_send_user.zig"),               @import("native_sdk_session_registry.zig"),
        @import("native_sdk_session_loadout.zig"),         @import("native_sdk_session_restore.zig"),
        @import("native_sdk_session_bindings.zig"),        @import("native_sdk_custom_message.zig"),
        @import("native_sdk_session_active_tools.zig"),
    }) |module| try module.install(engine, prototype);
    try @import("native_sdk_session_auto_compaction.zig").install(engine, prototype);
    try @import("native_sdk_session_request_auth.zig").install(engine, prototype, dependencies);
    try @import("native_sdk_session_hooks.zig").installWithDependencies(engine, prototype, dependencies);
    try @import("native_sdk_check_compaction.zig").install(engine, prototype, dependencies);
    try @import("native_sdk_session_boundaries.zig").install(engine, prototype, dependencies);
    try @import("native_sdk_session_ai_assembly.zig").install(engine, prototype, shared);
    try platform(engine, prototype, shared);
}
fn copyOwnMethod(engine: *em.Engine, staging: c.JSValue, prototype: c.JSValue, name: [:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, name.ptr);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(engine.context, &descriptor, staging, atom);
    if (found < 0) return js.capture(engine);
    if (found == 0) return error.RequiredActualOrdinaryAgentSessionMethod;
    defer engine.freeValue(descriptor.value);
    defer engine.freeValue(descriptor.getter);
    defer engine.freeValue(descriptor.setter);
    // Preserve genuine installed flags/arity/async shape. The Source166 gate
    // reports a mismatch rather than rewriting a method to fit the reference.
    const flags = descriptor.flags | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
        (if (descriptor.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
    if (c.JS_DefineProperty(engine.context, prototype, atom, descriptor.value, descriptor.getter, descriptor.setter, flags) < 0) return js.capture(engine);
}
