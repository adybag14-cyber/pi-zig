//! Actual package-manager command selection and npm orchestration. Execution
//! remains on the class's real command transports; no command result is made.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const af = @import("native_async_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub const Inputs = struct { basename: c.JSValue, exists_sync: c.JSValue };
pub const sync_methods = .{ "getNpmCommand", "getPackageManagerName", "getGitDependencyInstallArgs", "runNpmCommandSync", "getNpmInstallArgs" };
pub const async_methods = .{ "runNpmCommand", "installNpm", "uninstallNpm", "installNpmBatch" };
const Sync = enum(i32) { getNpmCommand, getPackageManagerName, getGitDependencyInstallArgs, runNpmCommandSync, getNpmInstallArgs };
const Async = enum(i32) { runNpmCommand, installNpm, uninstallNpm, installNpmBatch };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn define(s: *Scope, prototype: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(s.engine.context, prototype, name, c.JS_DupValue(s.engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(s.engine);
}
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    if (!c.JS_IsFunction(engine.context, inputs.basename) or !c.JS_IsFunction(engine.context, inputs.exists_sync)) return error.RequiredActualPackageCommandImports;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(imports, "basename", inputs.basename);
    try s.put(imports, "existsSync", inputs.exists_sync);
    inline for (@typeInfo(Sync).@"enum".fields) |field| {
        const length: c_int = switch (@as(Sync, @enumFromInt(field.value))) { .runNpmCommandSync => 1, .getNpmInstallArgs => 2, else => 0 };
        try define(&s, prototype, field.name, try s.own(try functions.createMethod(engine, field.name, length, sync, &.{ imports, c.JS_NewInt32(engine.context, field.value) })));
    }
    inline for (@typeInfo(Async).@"enum".fields) |field| {
        const length: c_int = if (field.value == @intFromEnum(Async.installNpm)) 3 else 2;
        try define(&s, prototype, field.name, try s.own(try af.createResumable(engine, field.name, length, asyncBody, &.{ imports, c.JS_NewInt32(engine.context, field.value) })));
    }
}
fn strings(s: *Scope, values: []const []const u8) !c.JSValue {
    const result = try s.array();
    for (values) |text| try push(s, result, try s.text(text));
    return result;
}
fn push(s: *Scope, target: c.JSValue, value: c.JSValue) !void {
    try s.index(target, try v.length(s, target), value);
}
fn append(s: *Scope, target: c.JSValue, values: c.JSValue) !void {
    var iterator = try v.iterator(s, values);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try push(s, target, value);
    }
}
fn npmCommand(s: *Scope, manager: c.JSValue) !c.JSValue {
    const configured = try s.invoke(try s.get(manager, "settingsManager"), "getNpmCommand", &.{});
    if (!s.truthy(configured) or s.equal(try s.get(configured, "length"), c.JS_NewInt32(s.engine.context, 0))) {
        const result = try s.object();
        try s.put(result, "command", try s.text("npm"));
        try s.put(result, "args", try s.array());
        return result;
    }
    var iterator = try v.iterator(s, configured);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const command = try s.own((try iterator.next()) orelse c.pi_js_undefined());
    const rest = try s.array();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try push(s, rest, value);
    }
    if (!s.truthy(command)) return v.errorText(s, try s.text("Invalid npmCommand: first array entry must be a non-empty command"));
    const result = try s.object();
    try s.put(result, "command", command);
    try s.put(result, "args", rest);
    return result;
}
fn normalized(s: *Scope, imports: c.JSValue, command: c.JSValue) !c.JSValue {
    const name = try s.call(try s.get(imports, "basename"), c.pi_js_undefined(), &.{command});
    const replace = try s.get(name, "replace");
    var regex_args = [_]c.JSValue{ try s.text("\\.(cmd|exe)$"), try s.text("i") };
    const suffix = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &regex_args)));
    return s.call(replace, name, &.{ suffix, try s.text("") });
}
fn normalizeCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_DupValue(engine.context, try normalized(&s, roots[0], arg(args, 0)));
}
fn supportedCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.js.invoke(engine, roots[0], "has", &.{arg(args, 0)});
}
fn managerName(s: *Scope, manager: c.JSValue, imports: c.JSValue) !c.JSValue {
    const command = try s.invoke(manager, "getNpmCommand", &.{});
    const supported = try s.own(try v.js.builtin(s.engine, "Set", &.{try strings(s, &.{ "npm", "pnpm", "bun" })}));
    const direct = try normalized(s, imports, try s.get(command, "command"));
    const separator = try s.invoke(try s.get(command, "args"), "lastIndexOf", &.{try s.text("--")});
    if (try arithmetic.compare(s.engine, .greater_equal, separator, c.JS_NewInt32(s.engine.context, 0))) {
        const key = try s.concat(separator, c.JS_NewInt32(s.engine.context, 1));
        const wrapped = try s.own(try v.js.getKey(s.engine, try s.get(command, "args"), key));
        return if (s.truthy(wrapped)) normalized(s, imports, wrapped) else direct;
    }
    if (s.truthy(try s.invoke(supported, "has", &.{direct}))) return direct;
    const map = try s.own(try functions.createArrow(s.engine, "normalizeCommandName", 1, normalizeCallback, &.{imports}));
    const filter = try s.own(try functions.createArrow(s.engine, "", 1, supportedCallback, &.{supported}));
    const names = try s.invoke(try s.invoke(try s.get(command, "args"), "map", &.{map}), "filter", &.{filter});
    const set = try s.own(try v.js.builtin(s.engine, "Set", &.{names}));
    const wrapped = try s.array();
    try append(s, wrapped, set);
    if (try arithmetic.compare(s.engine, .greater, try s.get(wrapped, "length"), c.JS_NewInt32(s.engine.context, 1))) {
        return v.errorText(s, try s.concat(try s.text("Ambiguous npmCommand package managers: "), try s.invoke(wrapped, "join", &.{try s.text(", ")})));
    }
    const first = try v.at(s, wrapped, 0);
    return if (v.nullish(first)) direct else first;
}
fn dependencyArgs(s: *Scope, manager: c.JSValue) !c.JSValue {
    const name = try s.invoke(manager, "getPackageManagerName", &.{});
    if (try v.eq(s, name, "bun")) return strings(s, &.{ "install", "--omit=dev", "--omit=peer" });
    if (try v.eq(s, name, "pnpm")) return strings(s, &.{ "install", "--prod", "--config.auto-install-peers=false", "--config.strict-peer-dependencies=false", "--config.strict-dep-builds=false" });
    if (try v.eq(s, name, "npm")) return strings(s, &.{ "install", "--omit=dev", "--legacy-peer-deps" });
    return strings(s, &.{"install"});
}
fn installArgs(s: *Scope, manager: c.JSValue, specs: c.JSValue, root: c.JSValue) !c.JSValue {
    const name = try s.invoke(manager, "getPackageManagerName", &.{});
    const result = try strings(s, &.{"install"});
    try append(s, result, specs);
    try push(s, result, try s.text(if (try v.eq(s, name, "bun")) "--cwd" else "--prefix"));
    try push(s, result, root);
    const tail = if (try v.eq(s, name, "bun"))
        try strings(s, &.{"--omit=peer"})
    else if (try v.eq(s, name, "pnpm"))
        try strings(s, &.{ "--config.auto-install-peers=false", "--config.strict-peer-dependencies=false", "--config.strict-dep-builds=false" })
    else
        try strings(s, &.{"--legacy-peer-deps"});
    try append(s, result, tail);
    return result;
}
fn combinedArgs(s: *Scope, command: c.JSValue, args: c.JSValue) !c.JSValue {
    const result = try s.array();
    try append(s, result, try s.get(command, "args"));
    try append(s, result, args);
    return result;
}
fn sync(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    const result = switch (@as(Sync, @enumFromInt(raw))) {
        .getNpmCommand => try npmCommand(&s, manager),
        .getPackageManagerName => try managerName(&s, manager, roots[0]),
        .getGitDependencyInstallArgs => try dependencyArgs(&s, manager),
        .getNpmInstallArgs => try installArgs(&s, manager, arg(args, 0), arg(args, 1)),
        .runNpmCommandSync => value: {
            const command = try s.invoke(manager, "getNpmCommand", &.{});
            const run = try s.get(manager, "runCommandSync");
            break :value try s.call(run, manager, &.{ try s.get(command, "command"), try combinedArgs(&s, command, arg(args, 0)) });
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn asyncBody(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    if (completion == .fulfilled) return .{ .returned = c.pi_js_undefined() };
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    const pending = switch (@as(Async, @enumFromInt(raw))) {
        .runNpmCommand => value: {
            const command = try s.invoke(manager, "getNpmCommand", &.{});
            const run = try s.get(manager, "runCommand");
            break :value try s.call(run, manager, &.{ try s.get(command, "command"), try combinedArgs(&s, command, arg(args, 0)), arg(args, 1) });
        },
        .installNpm, .installNpmBatch => |kind| value: {
            if (kind == .installNpmBatch and s.equal(try s.get(arg(args, 0), "length"), c.JS_NewInt32(engine.context, 0))) return .{ .returned = c.pi_js_undefined() };
            const root = try s.invoke(manager, "getNpmInstallRoot", &.{ arg(args, 1), if (kind == .installNpm) arg(args, 2) else c.pi_js_bool(engine.context, 0) });
            _ = try s.invoke(manager, "ensureNpmProject", &.{root});
            const run = try s.get(manager, "runNpmCommand");
            const get_args = try s.get(manager, "getNpmInstallArgs");
            const specs = if (kind == .installNpm) blk: {
                const values = try s.array();
                try push(&s, values, try s.get(arg(args, 0), "spec"));
                break :blk values;
            } else arg(args, 0);
            break :value try s.call(run, manager, &.{try s.call(get_args, manager, &.{ specs, root })});
        },
        .uninstallNpm => value: {
            const root = try s.invoke(manager, "getNpmInstallRoot", &.{ arg(args, 1), c.pi_js_bool(engine.context, 0) });
            if (!s.truthy(try s.call(try s.get(roots[0], "existsSync"), c.pi_js_undefined(), &.{root}))) return .{ .returned = c.pi_js_undefined() };
            const name = try s.invoke(manager, "getPackageManagerName", &.{});
            const values = try strings(&s, &.{"uninstall"});
            try push(&s, values, try s.get(arg(args, 0), "name"));
            try push(&s, values, try s.text(if (try v.eq(&s, name, "bun")) "--cwd" else "--prefix"));
            try push(&s, values, root);
            if (!try v.eq(&s, name, "bun") and !try v.eq(&s, name, "pnpm")) try push(&s, values, try s.text("--legacy-peer-deps"));
            break :value try s.invoke(manager, "runNpmCommand", &.{values});
        },
    };
    return .{ .awaited = c.JS_DupValue(engine.context, pending) };
}
