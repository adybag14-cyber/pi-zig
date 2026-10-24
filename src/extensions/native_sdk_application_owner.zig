//! Actual native SDK factory owner over the canonical frontend and suppliers.
//! No public/default module selection and no fabricated Completed record.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const p = @import("native_agent_af_values.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const owned = @import("native_sdk_owned_completion.zig");
const guest = @import("native_sdk_guest_operation.zig");
const captured_inputs = @import("native_child_process_frontend_inputs.zig");
const auth = @import("native_sdk_auth_runtime_owner.zig");
const bootstrap = @import("native_sdk_application_bootstrap.zig");
const lazy = @import("native_sdk_extension_lazy_imports.zig");

// Only this synchronous composition owner uses these raw-operation adapters.
// Actual call/get completion is checked and qualified before storing its owned
// result; ownRoot then records real storage OOM before retiring the input.
fn root(s: *Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(s, value); }
fn get(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return guest.get(s, target, name);
}
fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return guest.call(s, function, receiver, args);
}

pub const Inputs = struct {
    /// Already bound genuine frontend. Its bridge, environment and native
    /// provider/descriptor owners outlive this owner AND the Engine caches.
    frontend: *@import("native_stdio_frontend.zig").Frontend,
    host: captured_inputs.Host,
    /// Actual physical config.ts or packaged config.js; never a dummy URL.
    config_module_url: c.JSValue,
    /// Actual SourceLoader metadata and queued import operation. This is the
    /// existing real lazy-loader input ABI, not getCreateJiti stand-in callbacks.
    loader_import_meta: c.JSValue,
    lazy_modules: lazy.Inputs,
    is_typescript_source_runtime: bool,
};

/// Move-only host owner. Native frontend/provider capabilities remain borrowed;
/// all returned JS graphs and captured input roots are owned here. Cache roots
/// may outlive this handle, so retiring it does not authorize frontend teardown.
pub const Owner = struct {
    engine: *em.Engine,
    inputs: ?captured_inputs.Owned,
    auth: ?auth.Owner,
    application: c.JSValue,
    live: bool = true,

    fn check(self: *Owner) !void {
        if (!self.live) return error.ActualSdkApplicationOwnerRetired;
        try self.engine.checkNativeEntry();
        const inputs = if (self.inputs) |*value| value else return error.ActualSdkApplicationInputsRetired;
        _ = try inputs.view(self.engine);
    }
    /// Owned actual factory/model/session API produced by the existing real
    /// assembler. It is NOT advertised as the complete coding-agent namespace.
    pub fn factoryExports(self: *Owner) !c.JSValue {
        return exportsEntry(self);
    }
    pub fn authStorage(self: *Owner) !c.JSValue {
        try self.check();
        return if (self.auth) |*value| value.authStorage() else error.ActualSdkApplicationAuthRetired;
    }
    /// Owned actual public print module bound to this application's existing
    /// shell and stdout owner. The caller supplies only the real runtimeHost
    /// and Source print options when invoking its runPrintMode export.
    pub fn createPrintMode(self: *Owner) !c.JSValue {
        try self.check();
        return if (self.auth) |*value| value.createPrintMode() else error.ActualSdkApplicationAuthRetired;
    }
    /// Complete private original trust path/resource/options helpers over this
    /// owner's genuine filesystem, path, OS, configuration and path utilities.
    /// Store/event policy and the full Main runtimeFactory are separate owners.
    pub fn createProjectTrustPaths(self: *Owner) !c.JSValue {
        try self.check();
        return if (self.auth) |*value| value.createProjectTrustPaths() else error.ActualSdkApplicationAuthRetired;
    }
    /// The complete original trust manager over the same authenticated runtime.
    pub fn createProjectTrustManager(self: *Owner) !c.JSValue {
        try self.check();
        return if (self.auth) |*value| value.createProjectTrustManager() else error.ActualSdkApplicationAuthRetired;
    }
    /// Original trust resolution using actual manager, event and defaults.
    pub fn createProjectTrustResolver(self: *Owner) !c.JSValue {
        try self.check();
        return if (self.auth) |*value| value.createProjectTrustResolver() else error.ActualSdkApplicationAuthRetired;
    }
    /// Genuine original Main options and path helpers over the retained Auth
    /// provider graph; no runtimeFactory or complete Main namespace is fabricated.
    pub fn createMainRuntimeHelpers(self: *Owner) !c.JSValue {
        try self.check();
        return if (self.auth) |*value| value.createMainRuntimeHelpers() else error.ActualSdkApplicationAuthRetired;
    }
    /// Explicit Source mode transitions. Call only at the actual noninteractive
    /// or RPC transition, never infer takeover from TTY state or a mode boolean.
    pub fn takeOverStdout(self: *Owner) !void { return stdoutTransition(self, false); }
    pub fn restoreStdout(self: *Owner) !void { return stdoutTransition(self, true); }
    pub fn deinit(self: *Owner) !void {
        if (!self.live) return error.ActualSdkApplicationOwnerAlreadyRetired;
        var completion = owned.Completion.initVoid(self.engine, {});
        self.retireInto(&completion);
        return completion.finishVoid();
    }
    pub fn retireInto(self: *Owner, completion: *owned.Completion) void {
        std.debug.assert(self.live);
        self.live = false;
        const graph = self.application;
        self.application = c.pi_js_undefined();
        completion.release(graph);
        if (self.auth) |*value| value.retireInto(completion);
        self.auth = null;
        if (self.inputs) |*value| value.retireInto(completion);
        self.inputs = null;
    }
};

fn factoryExportsBody(self: *Owner, s: *Scope) !c.JSValue {
    return c.JS_DupValue(self.engine.context, try get(s, self.application, "exports"));
}
fn exportsEntry(self: *Owner) !c.JSValue {
    try self.check();
    const engine = self.engine;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine };
    const value = owned.finishValue(&s, factoryExportsBody(self, &s)) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn stdoutTransition(self: *Owner, restore: bool) !void {
    try self.check();
    const engine = self.engine;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine };
    owned.finishVoid(&s, stdoutBody(self, &s, restore)) catch |err| {
        _ = try engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
        unreachable;
    };
    engine.freeValue(try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())));
}
fn stdoutBody(self: *Owner, s: *Scope, restore: bool) !void {
    const core = if (self.auth) |*value| value else return error.ActualSdkApplicationAuthRetired;
    const frontend = core.frontend orelse return error.ActualSdkApplicationFrontendRetired;
    const function = if (restore) frontend.output_guard.restore_stdout else frontend.output_guard.take_over_stdout;
    _ = try call(s, function, c.pi_js_undefined(), &.{});
}

/// Construction performs real existing factories. It does not install the
/// native-only host, choose a backend, publish partial SDK/Jiti modules, import
/// extensions or launch commands. Root must qualify the actual dependency union
/// and perform its complete public-module selection at the real module boundary.
pub fn create(engine: *em.Engine, inputs: Inputs) !Owner {
    try engine.checkNativeEntry();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var result = createOwned(engine, inputs) catch |err| {
        const escaped = engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
        if (escaped) |unexpected| {
            engine.freeValue(unexpected);
            return error.ActualSdkApplicationCreationDidNotEscape;
        } else |actual| return actual;
    };
    const terminal = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
    if (c.JS_IsException(terminal) or c.JS_HasException(engine.context)) {
        var failed = owned.Completion.initVoid(engine, error.JavaScriptException);
        result.retireInto(&failed);
        try failed.finishVoid();
        unreachable;
    }
    return result;
}
fn createOwned(engine: *em.Engine, inputs: Inputs) !Owner {
    var captured = try captured_inputs.capture(engine, inputs.frontend, inputs.host);
    var core = createAuth(engine, &captured, inputs.config_module_url) catch |err| {
        var failed = owned.Completion.initVoid(engine, err);
        captured.retireInto(&failed);
        try failed.finishVoid();
        unreachable;
    };
    var scope: Scope = .{ .engine = engine };
    var selected = owned.Completion.initValue(engine, assemble(&scope, &core, inputs));
    selected.releaseScope(&scope);
    const graph = selected.finishValue() catch |err| {
        var failed = owned.Completion.initVoid(engine, err);
        core.retireInto(&failed);
        captured.retireInto(&failed);
        try failed.finishVoid();
        unreachable;
    };
    return .{ .engine = engine, .inputs = captured, .auth = core, .application = graph };
}
fn createAuth(engine: *em.Engine, captured: *captured_inputs.Owned, config_module_url: c.JSValue) !auth.Owner {
    return auth.create(engine, .{ .frontend = try captured.view(engine), .config_module_url = config_module_url });
}
fn installed(engine: *em.Engine, name: []const u8) !c.JSValue {
    if (!engine.native_module_names.contains(name) or engine.modules.contains(name)) return error.RequiredActualSdkInstalledBuiltin;
    return engine.native_module_values.get(name) orelse error.RequiredActualSdkInstalledBuiltin;
}
fn builtinDefault(s: *Scope, name: []const u8) !c.JSValue {
    return get(s, try installed(s.engine, name), "default");
}
fn actualModule(s: *Scope) !c.JSValue {
    const module = try builtinDefault(s, "node:module");
    const constructor = try get(s, module, "Module");
    // This reads the real private Module owner, rejecting the old CommonJS
    // facade even if it happens to have similarly named public properties.
    const state = try root(s, try @import("native_node_module_constructor.zig").commonJSState(s.engine, constructor));
    if (c.JS_IsNull(state) or c.JS_IsUndefined(state)) return error.RequiredActualNodeModuleLoaderBootstrap;
    if (!c.JS_IsFunction(s.engine.context, try get(s, module, "createRequire")) or !c.JS_IsFunction(s.engine.context, try get(s, constructor, "_load"))) return error.RequiredActualNodeModuleLoaderBootstrap;
    return module;
}
fn requireFileAuth(s: *Scope, core: *auth.Owner) !void {
    const namespace = try root(s, try core.authStorage());
    const prototype = try get(s, try get(s, namespace, "FileAuthStorageBackend"), "prototype");
    inline for (.{ "acquireLockAsync", "withLockAsync" }) |name| {
        const function = try get(s, prototype, name);
        if (!c.JS_IsAsyncFunction(function) or c.JS_IsConstructor(s.engine.context, function)) return error.RequiredActualFileAuthAsyncOwner;
    }
}
fn assemble(s: *Scope, core: *auth.Owner, inputs: Inputs) !c.JSValue {
    const engine = s.engine;
    try requireFileAuth(s, core);
    const frontend = core.frontend orelse return error.ActualSdkApplicationFrontendRetired;
    const runtime = core.runtime_imports;
    const platform = try get(s, runtime, "platform");
    const filesystem = try get(s, platform, "filesystem");
    const paths = try get(s, platform, "paths");
    const process = try get(s, runtime, "process");
    const configuration = try get(s, runtime, "configuration");
    const timing = try get(s, runtime, "timing");
    const os = try builtinDefault(s, "node:os");
    const url = try builtinDefault(s, "node:url");
    const module = try actualModule(s);
    const path_utilities = try root(s, try @import("native_sdk_path_utilities_namespace.zig").createWithPlatform(engine, filesystem, process, frontend.process_imports.spawn_process_sync));
    if (!s.equal(path_utilities, try get(s, platform, "pathUtilities"))) return error.RequiredSingleActualSdkPathsModule;
    const text = try root(s, try @import("native_sdk_model_text_production.zig").create(engine));
    const crypto = try root(s, try @import("native_node_crypto_hash.zig").create(engine));
    const semver = try root(s, try @import("native_semver785.zig").create(engine));
    const git = try root(s, try @import("native_sdk_git_url.zig").create(engine, url));
    const ignore = try root(s, try @import("native_sdk_ignore708.zig").createDefault(engine));
    const minimatch = try get(s, try root(s, try @import("native_minimatch_namespace.zig").create(engine)), "minimatch");
    const package = try root(s, try @import("native_sdk_package_assembly.zig").create(engine, .{
        .paths = paths, .filesystem = filesystem, .process = process, .os = os,
        .path_utilities = path_utilities, .text = text, .crypto = crypto,
        .semver = semver, .git = git, .ignore = ignore, .minimatch = minimatch,
        .config_dir = try get(s, configuration, "CONFIG_DIR_NAME"),
        .transport = .{
            .process = process, .read_file_sync = try get(s, filesystem, "readFileSync"),
            .spawn_process = frontend.process_imports.spawn_process,
            .spawn_process_sync = frontend.process_imports.spawn_process_sync,
            .is_stdout_taken_over = frontend.process_imports.is_stdout_taken_over,
        },
    }));
    const package_manager = try get(s, try get(s, package, "exports"), "DefaultPackageManager");
    const exec = try root(s, try @import("native_sdk_exec.zig").create(engine, .{
        .spawn = try get(s, frontend.transport.child.node, "spawn"),
        .wait_for_child_process = try get(s, frontend.transport.utilities, "waitForChildProcess"),
    }));
    const mcp = try root(s, try @import("native_sdk_mcp_config.zig").create(engine));
    const loader = try root(s, try @import("native_sdk_extension_loader_assembly.zig").create(engine, .{
        .api = .{ .exec_command = try get(s, exec, "execCommand"), .mcp = mcp },
        .paths = paths, .filesystem = filesystem, .url = url, .node_module = module,
        .import_meta = inputs.loader_import_meta, .timing = timing,
        .lazy_modules = inputs.lazy_modules,
        .is_typescript_source_runtime = inputs.is_typescript_source_runtime,
    }));
    const chalk = try root(s, try @import("native_sdk_chalk.zig").createDefault(engine));
    const view = frontend.transport.child.node; // Borrowed same real child namespace.
    return bootstrap.createNativeFromOwners(engine, .{
        .process = process, .os = os, .url = url, .child_process = view,
        .config_module_url = inputs.config_module_url, .user_agent_runtime = .native_zig,
    }, .{
        .package_manager = package_manager, .chalk_default = chalk,
        .load_extension_from_factory = try get(s, loader, "loadExtensionFromFactory"),
        .load_extensions_cached = try get(s, loader, "loadExtensionsCached"),
    });
}
