//! Actual config.ts package/user asset paths and startup package metadata.
//! Self-update/worker launch exports are outside this scoped SDK dependency.
//! The bootstrap supplies its genuine config module URL and actual imported
//! filesystem/path/OS/process namespaces. No hard-coded version or package root.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const functions = @import("native_node_function.zig");
const c = em.c;
pub const Inputs = struct { process: c.JSValue, paths: c.JSValue, filesystem: c.JSValue, os: c.JSValue, url: c.JSValue, path_utilities: c.JSValue, module_url: c.JSValue };
const Method = enum(c_int) { findNodePackageDir, getPackageDir, getThemesDir, getExportTemplateDir, getPackageJsonPath, getReadmePath, getDocsPath, getExamplesPath, getChangelogPath, getInteractiveAssetsDir, getBundledInteractiveAssetPath, expandTildePath, getShareViewerUrl, getAgentDir, getCustomThemesDir, getModelsPath, getAuthPath, getSettingsPath, getToolsDir, getBinDir, getPromptsDir, getSessionsDir, getDebugLogPath, getDefaultSessionDir, getPiUserAgent };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn capture(scope: *Scope, bindings: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| {
        const function = try scope.get(namespace, name);
        if (!c.JS_IsFunction(scope.engine.context, function)) return error.RequiredActualSdkConfigurationImport;
        try scope.put(bindings, name, function);
    }
}
pub fn create(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    const module_name = "pi-native:sdk-configuration";
    if (engine.native_module_values.get(module_name)) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsString(inputs.module_url)) return error.RequiredActualSdkConfigurationModuleUrl;
    const bindings = try scope.object();
    try capture(&scope, bindings, inputs.paths, .{ "dirname", "basename", "join", "resolve" });
    try capture(&scope, bindings, inputs.filesystem, .{ "existsSync", "readFileSync", "mkdirSync" });
    try capture(&scope, bindings, inputs.os, .{"homedir"});
    try capture(&scope, bindings, inputs.path_utilities, .{ "normalizePath", "resolvePath" });
    try scope.put(bindings, "process", inputs.process);
    const file_url_to_path = try scope.get(inputs.url, "fileURLToPath");
    if (!c.JS_IsFunction(engine.context, file_url_to_path)) return error.RequiredActualSdkConfigurationImport;
    const filename = try scope.call(file_url_to_path, c.pi_js_undefined(), &.{inputs.module_url});
    try scope.put(bindings, "__dirname", try imported(&scope, bindings, "dirname", &.{filename}));
    const is_bun_binary = scope.truthy(try scope.invoke(inputs.module_url, "includes", &.{try scope.text("$bunfs")})) or scope.truthy(try scope.invoke(inputs.module_url, "includes", &.{try scope.text("~BUN")})) or scope.truthy(try scope.invoke(inputs.module_url, "includes", &.{try scope.text("%7EBUN")}));
    try scope.put(bindings, "isBunBinary", c.pi_js_bool(engine.context, @intFromBool(is_bun_binary)));
    try scope.put(bindings, "isBunRuntime", c.pi_js_bool(engine.context, @intFromBool(scope.truthy(try scope.get(try scope.get(inputs.process, "versions"), "bun")))));
    const text = try scope.own(try @import("native_sdk_model_text_production.zig").create(engine));
    try capture(&scope, bindings, text, .{"stripBom"});
    const path = try execute(&scope, bindings, .getPackageJsonPath, &.{});
    const generation = engine.native_allocation_generation;
    const pkg = readPackage(&scope, bindings, path) catch |err| value: {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const reason = try scope.own(@import("native_agent_async.zig").reason(engine, err));
        if (!scope.equal(try scope.get(reason, "code"), try scope.text("ENOENT"))) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        break :value try scope.object();
    };
    const pi_config = try scope.get(pkg, "piConfig");
    const config_name = if (temp.nullish(pi_config)) c.pi_js_undefined() else try scope.get(pi_config, "name");
    const config_dir = if (temp.nullish(pi_config)) c.pi_js_undefined() else try scope.get(pi_config, "configDir");
    const package_name = try scope.get(pkg, "name");
    const version = try scope.get(pkg, "version");
    const app_name = if (scope.truthy(config_name)) config_name else try scope.text("pi");
    try scope.put(bindings, "APP_NAME", app_name);
    try scope.put(bindings, "CONFIG_DIR_NAME", if (scope.truthy(config_dir)) config_dir else try scope.text(".pi"));
    try scope.put(bindings, "ENV_AGENT_DIR", try scope.concat(try scope.invoke(app_name, "toUpperCase", &.{}), try scope.text("_CODING_AGENT_DIR")));
    const namespace = try scope.object();
    try scope.put(namespace, "PACKAGE_NAME", if (scope.truthy(package_name)) package_name else try scope.text("@earendil-works/pi-coding-agent"));
    try scope.put(namespace, "APP_NAME", app_name);
    try scope.put(namespace, "APP_TITLE", if (scope.truthy(config_name)) app_name else try scope.text("\xcf\x80"));
    try scope.put(namespace, "CONFIG_DIR_NAME", try scope.get(bindings, "CONFIG_DIR_NAME"));
    try scope.put(namespace, "VERSION", if (scope.truthy(version)) version else try scope.text("0.0.0"));
    try scope.put(namespace, "ENV_AGENT_DIR", try scope.get(bindings, "ENV_AGENT_DIR"));
    try scope.put(namespace, "ENV_SESSION_DIR", try scope.concat(try scope.invoke(app_name, "toUpperCase", &.{}), try scope.text("_CODING_AGENT_SESSION_DIR")));
    try scope.put(namespace, "isBunBinary", try scope.get(bindings, "isBunBinary"));
    try scope.put(namespace, "isBunRuntime", try scope.get(bindings, "isBunRuntime"));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const length: c_int = switch (method) {
            .findNodePackageDir, .getBundledInteractiveAssetPath, .expandTildePath, .getShareViewerUrl, .getDefaultSessionDir, .getPiUserAgent => 1,
            else => 0,
        };
        try scope.put(namespace, field.name, try scope.own(try functions.create(engine, field.name, length, callback, &.{ bindings, c.JS_NewInt32(engine.context, field.value) })));
    }
    try engine.registerValueModule(module_name, namespace);
    return c.JS_DupValue(engine.context, namespace);
}
fn readPackage(scope: *Scope, bindings: c.JSValue, path: c.JSValue) !c.JSValue {
    const json = try scope.global("JSON");
    const parse = try scope.get(json, "parse");
    return scope.call(parse, json, &.{try imported(scope, bindings, "stripBom", &.{try imported(scope, bindings, "readFileSync", &.{ path, try scope.text("utf-8") })})});
}
fn callback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, roots[1]) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, try execute(&scope, roots[0], @enumFromInt(operation), args));
}
fn findPackage(scope: *Scope, bindings: c.JSValue, start: c.JSValue) !c.JSValue {
    var directory = start;
    while (!scope.equal(directory, try imported(scope, bindings, "dirname", &.{directory}))) {
        if (scope.truthy(try imported(scope, bindings, "existsSync", &.{try imported(scope, bindings, "join", &.{ directory, try scope.text("package.json") })}))) {
            const parent = try imported(scope, bindings, "dirname", &.{directory});
            if (scope.equal(try imported(scope, bindings, "basename", &.{directory}), try scope.text("dist")) and scope.truthy(try imported(scope, bindings, "existsSync", &.{try imported(scope, bindings, "join", &.{ parent, try scope.text("package.json") })}))) return parent;
            return directory;
        }
        directory = try imported(scope, bindings, "dirname", &.{directory});
    }
    return start;
}
fn packageDir(scope: *Scope, bindings: c.JSValue) !c.JSValue {
    const env = try scope.get(try scope.get(bindings, "process"), "env");
    const directory = try scope.get(env, "PI_PACKAGE_DIR");
    if (scope.truthy(directory)) return imported(scope, bindings, "normalizePath", &.{directory});
    if (scope.truthy(try scope.get(bindings, "isBunBinary"))) return imported(scope, bindings, "dirname", &.{try scope.get(try scope.get(bindings, "process"), "execPath")});
    return findPackage(scope, bindings, try scope.get(bindings, "__dirname"));
}
fn agentDir(scope: *Scope, bindings: c.JSValue) !c.JSValue {
    const env = try scope.get(try scope.get(bindings, "process"), "env");
    const directory = try scope.own(try js.getKey(scope.engine, env, try scope.get(bindings, "ENV_AGENT_DIR")));
    if (scope.truthy(directory)) return imported(scope, bindings, "normalizePath", &.{directory});
    return imported(scope, bindings, "join", &.{ try imported(scope, bindings, "homedir", &.{}), try scope.get(bindings, "CONFIG_DIR_NAME"), try scope.text("agent") });
}
fn assetDirectory(scope: *Scope, bindings: c.JSValue, suffix: []const u8, interactive: bool) !c.JSValue {
    if (scope.truthy(try scope.get(bindings, "isBunBinary"))) return imported(scope, bindings, "join", &.{ try packageDir(scope, bindings), try scope.text(suffix) });
    const directory = try packageDir(scope, bindings);
    const mode = if (scope.truthy(try imported(scope, bindings, "existsSync", &.{try imported(scope, bindings, "join", &.{ directory, try scope.text("src") })}))) try scope.text("src") else try scope.text("dist");
    return if (interactive) imported(scope, bindings, "join", &.{ directory, mode, try scope.text("modes"), try scope.text("interactive"), try scope.text(suffix) }) else imported(scope, bindings, "join", &.{ directory, mode, try scope.text("core"), try scope.text(suffix) });
}
fn regexp(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    const args = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, @constCast(&args))));
}
fn execute(scope: *Scope, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    return switch (method) {
        .findNodePackageDir => findPackage(scope, bindings, arg(args, 0)),
        .getPackageDir => packageDir(scope, bindings),
        .getThemesDir => assetDirectory(scope, bindings, "theme", true),
        .getExportTemplateDir => assetDirectory(scope, bindings, "export-html", false),
        .getInteractiveAssetsDir => assetDirectory(scope, bindings, "assets", true),
        .getBundledInteractiveAssetPath => imported(scope, bindings, "join", &.{ try assetDirectory(scope, bindings, "assets", true), arg(args, 0) }),
        .getPackageJsonPath => imported(scope, bindings, "join", &.{ try packageDir(scope, bindings), try scope.text("package.json") }),
        .getReadmePath, .getDocsPath, .getExamplesPath, .getChangelogPath => blk: {
            const name = switch (method) {
                .getReadmePath => "README.md",
                .getDocsPath => "docs",
                .getExamplesPath => "examples",
                else => "CHANGELOG.md",
            };
            break :blk try imported(scope, bindings, "resolve", &.{try imported(scope, bindings, "join", &.{ try packageDir(scope, bindings), try scope.text(name) })});
        },
        .expandTildePath => imported(scope, bindings, "normalizePath", &.{arg(args, 0)}),
        .getShareViewerUrl => blk: {
            const base = try scope.get(try scope.get(try scope.get(bindings, "process"), "env"), "PI_SHARE_VIEWER_URL");
            break :blk try scope.concat(try scope.concat(try scope.stringify(if (scope.truthy(base)) base else try scope.text("https://pi.dev/session/")), try scope.text("#")), try scope.stringify(arg(args, 0)));
        },
        .getAgentDir => agentDir(scope, bindings),
        .getCustomThemesDir, .getModelsPath, .getAuthPath, .getSettingsPath, .getToolsDir, .getBinDir, .getPromptsDir, .getSessionsDir, .getDebugLogPath => blk: {
            const name = switch (method) {
                .getCustomThemesDir => try scope.text("themes"),
                .getModelsPath => try scope.text("models.json"),
                .getAuthPath => try scope.text("auth.json"),
                .getSettingsPath => try scope.text("settings.json"),
                .getToolsDir => try scope.text("tools"),
                .getBinDir => try scope.text("bin"),
                .getPromptsDir => try scope.text("prompts"),
                .getSessionsDir => try scope.text("sessions"),
                else => try scope.concat(try scope.stringify(try scope.get(bindings, "APP_NAME")), try scope.text("-debug.log")),
            };
            break :blk try imported(scope, bindings, "join", &.{ try agentDir(scope, bindings), name });
        },
        .getDefaultSessionDir => blk: {
            const agent = if (c.JS_IsUndefined(arg(args, 1))) try agentDir(scope, bindings) else arg(args, 1);
            const cwd = try imported(scope, bindings, "resolvePath", &.{arg(args, 0)});
            const directory = try imported(scope, bindings, "resolvePath", &.{agent});
            const safe = try scope.invoke(try scope.invoke(cwd, "replace", &.{ try regexp(scope, "^[/\\\\]", ""), try scope.text("") }), "replace", &.{ try regexp(scope, "[/\\\\:]", "g"), try scope.text("-") });
            const encoded = try scope.concat(try scope.concat(try scope.text("--"), try scope.stringify(safe)), try scope.text("--"));
            const path = try imported(scope, bindings, "join", &.{ directory, try scope.text("sessions"), encoded });
            if (!scope.truthy(try imported(scope, bindings, "existsSync", &.{path}))) {
                const options = try scope.object();
                try scope.put(options, "recursive", c.pi_js_bool(scope.engine.context, 1));
                _ = try imported(scope, bindings, "mkdirSync", &.{ path, options });
            }
            break :blk path;
        },
        .getPiUserAgent => blk: {
            const process = try scope.get(bindings, "process");
            const bun = try scope.get(try scope.get(process, "versions"), "bun");
            const runtime = if (scope.truthy(bun)) try scope.concat(try scope.text("bun/"), try scope.stringify(try scope.get(try scope.get(process, "versions"), "bun"))) else try scope.concat(try scope.text("node/"), try scope.stringify(try scope.get(process, "version")));
            var text = try scope.concat(try scope.concat(try scope.text("pi/"), try scope.stringify(arg(args, 0))), try scope.text(" ("));
            text = try scope.concat(try scope.concat(text, try scope.stringify(try scope.get(process, "platform"))), try scope.text("; "));
            text = try scope.concat(try scope.concat(text, try scope.stringify(runtime)), try scope.text("; "));
            break :blk try scope.concat(try scope.concat(text, try scope.stringify(try scope.get(process, "arch"))), try scope.text(")"));
        },
    };
}
