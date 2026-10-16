//! Original context/prompt input bodies over captured real Node fs/path imports.
//! Warning rendering requires the actual chalk default dependency explicitly.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const spread = @import("native_sdk_resource_spread.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Import = enum(usize) { join, dirname, basename, resolve, sep, exists, stat, read, realpath, chalk };
pub fn create(engine: *em.Engine, chalk_default: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(chalk_default)) return error.NativeResourceContextRequiresChalk;
    const io = engine.native_io orelse return error.NativeResourceContextRequiresIo;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = engine.native_module_values.get("node:path").?;
    const fs = engine.native_module_values.get("node:fs").?;
    const roots = [_]c.JSValue{ try scope.get(path, "join"), try scope.get(path, "dirname"), try scope.get(path, "basename"), try scope.get(path, "resolve"), try scope.get(path, "sep"), try scope.get(fs, "existsSync"), try scope.get(fs, "statSync"), try scope.get(fs, "readFileSync"), try scope.get(fs, "realpathSync"), chalk_default };
    const exports = try scope.object();
    try scope.put(exports, "findGitPaths", try scope.own(try @import("native_node_function.zig").create(engine, "findGitPaths", 1, gitPaths, &roots)));
    try scope.put(exports, "loadProjectContextFiles", try scope.own(try @import("native_node_function.zig").create(engine, "loadProjectContextFiles", 1, contextFiles, &roots)));
    try scope.put(exports, "resolvePromptInput", try scope.own(try @import("native_node_function.zig").create(engine, "resolvePromptInput", 2, promptInput, &roots)));
    return c.JS_DupValue(engine.context, exports);
}
fn imported(scope: *Scope, roots: []const c.JSValue, kind: Import, args: []const c.JSValue) !c.JSValue {
    return scope.call(roots[@intFromEnum(kind)], c.pi_js_undefined(), args);
}
fn stripBom(scope: *Scope, input: c.JSValue) !c.JSValue {
    return if (scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("\xef\xbb\xbf")}))) scope.invoke(input, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}) else input;
}
fn clearException(engine: *em.Engine) void {
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
}
fn suppress(scope: *Scope, err: anyerror, generation: u64) !void {
    if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    clearException(scope.engine);
}
fn warn(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, description: ?c.JSValue, err: anyerror, generation: u64) !void {
    if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    const reason = try scope.own(flow.reason(scope.engine, err));
    clearException(scope.engine);
    const console = try scope.global("console");
    const log = try scope.get(console, "error");
    const chalk = roots[@intFromEnum(Import.chalk)];
    const yellow = try scope.get(chalk, "yellow");
    const prefix = if (description) |label| try scope.concat(try scope.concat(try scope.concat(try scope.text("Warning: Could not read "), try scope.stringify(label)), try scope.text(" file ")), try scope.concat(try scope.stringify(path), try scope.text(": "))) else try scope.concat(try scope.concat(try scope.text("Warning: Could not read "), try scope.stringify(path)), try scope.text(": "));
    const message = try scope.concat(prefix, try scope.stringify(reason));
    _ = try scope.call(log, console, &.{try scope.call(yellow, chalk, &.{message})});
}
fn promptInput(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = if (args.len > 0) args[0] else c.pi_js_undefined();
    const description = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (!scope.truthy(input)) return c.pi_js_undefined();
    if (scope.truthy(try imported(&scope, roots, .exists, &.{input}))) {
        const generation = engine.native_allocation_generation;
        const value = readPrompt(&scope, roots, input) catch |err| {
            try warn(&scope, roots, input, description, err, generation);
            return c.JS_DupValue(engine.context, input);
        };
        return c.JS_DupValue(engine.context, value);
    }
    return c.JS_DupValue(engine.context, input);
}
fn readPrompt(scope: *Scope, roots: []const c.JSValue, input: c.JSValue) !c.JSValue {
    return stripBom(scope, try imported(scope, roots, .read, &.{ input, try scope.text("utf-8") }));
}
fn contextFromDirectory(scope: *Scope, roots: []const c.JSValue, directory: c.JSValue) !c.JSValue {
    const candidates = try scope.array();
    inline for (.{ "AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD" }, 0..) |name, index| try scope.index(candidates, index, try scope.text(name));
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, candidates, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |name| {
        defer scope.engine.freeValue(name);
        const path = try imported(scope, roots, .join, &.{ directory, name });
        if (scope.truthy(try imported(scope, roots, .exists, &.{path}))) {
            const generation = scope.engine.native_allocation_generation;
            const value = readContext(scope, roots, path) catch |err| {
                try warn(scope, roots, path, null, err, generation);
                continue;
            };
            if (!c.JS_IsNull(value)) {
                // Source's return from inside for-of performs IteratorClose.
                try iterator.close();
                return value;
            }
        }
    }
    return c.JS_NULL;
}
fn readContext(scope: *Scope, roots: []const c.JSValue, path: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.invoke(try imported(scope, roots, .stat, &.{path}), "isFile", &.{}))) return c.JS_NULL;
    const result = try scope.object();
    try scope.put(result, "path", path);
    try scope.put(result, "content", try readPrompt(scope, roots, path));
    return result;
}
fn gitFound(scope: *Scope, roots: []const c.JSValue, directory: c.JSValue, git: c.JSValue) !c.JSValue {
    const stat = try imported(scope, roots, .stat, &.{git});
    var common: c.JSValue = undefined;
    var head: c.JSValue = undefined;
    if (scope.truthy(try scope.invoke(stat, "isFile", &.{}))) {
        const content = try scope.invoke(try imported(scope, roots, .read, &.{ git, try scope.text("utf8") }), "trim", &.{});
        if (!scope.truthy(try scope.invoke(content, "startsWith", &.{try scope.text("gitdir: ")}))) return c.pi_js_undefined();
        const git_dir = try imported(scope, roots, .resolve, &.{ directory, try scope.invoke(try scope.invoke(content, "slice", &.{c.JS_NewInt32(scope.engine.context, 8)}), "trim", &.{}) });
        head = try imported(scope, roots, .join, &.{ git_dir, try scope.text("HEAD") });
        if (!scope.truthy(try imported(scope, roots, .exists, &.{head}))) return c.JS_NULL;
        const common_path = try imported(scope, roots, .join, &.{ git_dir, try scope.text("commondir") });
        common = if (scope.truthy(try imported(scope, roots, .exists, &.{common_path}))) try imported(scope, roots, .resolve, &.{ git_dir, try scope.invoke(try imported(scope, roots, .read, &.{ common_path, try scope.text("utf8") }), "trim", &.{}) }) else git_dir;
    } else if (scope.truthy(try scope.invoke(stat, "isDirectory", &.{}))) {
        head = try imported(scope, roots, .join, &.{ git, try scope.text("HEAD") });
        if (!scope.truthy(try imported(scope, roots, .exists, &.{head}))) return c.JS_NULL;
        common = git;
    } else return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "repoDir", directory);
    try scope.put(result, "commonGitDir", common);
    try scope.put(result, "headPath", head);
    return result;
}
fn gitPaths(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try findGit(&scope, roots, if (args.len > 0) args[0] else c.pi_js_undefined()));
}
fn findGit(scope: *Scope, roots: []const c.JSValue, cwd: c.JSValue) !c.JSValue {
    var directory = cwd;
    while (true) {
        const git = try imported(scope, roots, .join, &.{ directory, try scope.text(".git") });
        if (scope.truthy(try imported(scope, roots, .exists, &.{git}))) {
            const generation = scope.engine.native_allocation_generation;
            const result = gitFound(scope, roots, directory, git) catch |err| {
                try suppress(scope, err, generation);
                return c.JS_NULL;
            };
            if (!c.JS_IsUndefined(result)) return result;
        }
        const parent = try imported(scope, roots, .dirname, &.{directory});
        if (scope.equal(parent, directory)) return c.JS_NULL;
        directory = parent;
    }
}
fn canonical(scope: *Scope, roots: []const c.JSValue, path: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return imported(scope, roots, .realpath, &.{path}) catch |err| {
        try suppress(scope, err, generation);
        return path;
    };
}
fn shadowed(scope: *Scope, roots: []const c.JSValue, cwd: c.JSValue) !c.JSValue {
    const git = try findGit(scope, roots, cwd);
    if (!scope.truthy(git)) return c.pi_js_undefined();
    const common = try canonical(scope, roots, try scope.get(git, "commonGitDir"));
    const worktree = try canonical(scope, roots, try scope.get(git, "repoDir"));
    const main = try imported(scope, roots, .dirname, &.{common});
    if (!scope.truthy(try scope.invoke(worktree, "startsWith", &.{try scope.concat(try scope.stringify(main), try scope.stringify(roots[@intFromEnum(Import.sep)]))}))) return c.pi_js_undefined();
    if (!scope.equal(try canonical(scope, roots, try imported(scope, roots, .join, &.{ main, try scope.text(".git") })), common)) return c.pi_js_undefined();
    const context = try contextFromDirectory(scope, roots, worktree);
    return if (scope.truthy(context)) imported(scope, roots, .join, &.{ main, try imported(scope, roots, .basename, &.{try scope.get(context, "path")}) }) else c.pi_js_undefined();
}
fn contextFiles(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (args.len > 0) args[0] else c.pi_js_undefined();
    const cwd = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "cwd"), c.pi_js_undefined(), c.pi_js_undefined()));
    const agent = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "agentDir"), c.pi_js_undefined(), c.pi_js_undefined()));
    const result = try scope.array();
    const seen = try scope.own(try js.builtin(engine, "Set", &.{}));
    const global_context = try contextFromDirectory(&scope, roots, agent);
    if (scope.truthy(global_context)) {
        _ = try scope.invoke(result, "push", &.{global_context});
        _ = try scope.invoke(seen, "add", &.{try scope.get(global_context, "path")});
    }
    const ancestors = try scope.array();
    const hidden = try shadowed(&scope, roots, cwd);
    var directory = cwd;
    while (true) {
        const context = try contextFromDirectory(&scope, roots, directory);
        var is_shadowed = false;
        if (!c.JS_IsUndefined(hidden) and !c.JS_IsNull(context)) {
            is_shadowed = scope.equal(try imported(&scope, roots, .join, &.{ try canonical(&scope, roots, directory), try imported(&scope, roots, .basename, &.{try scope.get(context, "path")}) }), hidden);
        }
        if (scope.truthy(context) and !is_shadowed and !scope.truthy(try scope.invoke(seen, "has", &.{try scope.get(context, "path")}))) {
            _ = try scope.invoke(ancestors, "unshift", &.{context});
            _ = try scope.invoke(seen, "add", &.{try scope.get(context, "path")});
        }
        const parent = try imported(&scope, roots, .dirname, &.{directory});
        if (scope.equal(parent, directory)) break;
        directory = parent;
    }
    _ = try spread.call(&scope, try scope.get(result, "push"), result, ancestors);
    return c.JS_DupValue(engine.context, result);
}
