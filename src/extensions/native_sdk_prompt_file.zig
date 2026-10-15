//! Actual Source prompt-file parsing, description fallback and YAML diagnostics.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const fm = @import("native_sdk_frontmatter_values.zig");
const c = em.c;
pub fn create(engine: *em.Engine) !c.JSValue {
    const io = engine.native_io orelse return error.NativePromptFileRequiresIo;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return @import("native_node_function.zig").create(engine, "loadTemplateFromFile", 2, invoke, &.{ try scope.get(engine.native_module_values.get("node:fs").?, "readFileSync"), try scope.get(engine.native_module_values.get("node:path").?, "basename") });
}
fn warning(scope: *Scope, diagnostics: c.JSValue, path: c.JSValue, message: c.JSValue) !void {
    const push = try scope.get(diagnostics, "push");
    const row = try scope.object();
    try scope.put(row, "type", try scope.text("warning"));
    try scope.put(row, "message", message);
    try scope.put(row, "path", path);
    _ = try scope.call(push, diagnostics, &.{row});
}
fn failure(scope: *Scope, diagnostics: c.JSValue, path: c.JSValue, err: anyerror, generation: u64, fallback: []const u8) !void {
    const original = scope.engine.nativeAllocationError(err, generation);
    if (original == error.OutOfMemory) return original;
    const reason = try scope.own(flow.reason(scope.engine, original));
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return js.capture(scope.engine);
    try warning(scope, diagnostics, path, if (instance != 0) try scope.get(reason, "message") else try scope.text(fallback));
}
fn result(scope: *Scope, template: c.JSValue, diagnostics: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "template", template);
    try scope.put(value, "diagnostics", diagnostics);
    return value;
}
fn parse(scope: *Scope, raw: c.JSValue) !fm.Result {
    return fm.parseValue(scope, raw);
}
fn nonempty(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "trim", &.{}) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = if (args.len > 0) args[0] else c.pi_js_undefined();
    const source_info = if (args.len > 1) args[1] else c.pi_js_undefined();
    const diagnostics = try scope.array();
    const read_generation = engine.native_allocation_generation;
    const raw = scope.call(roots[0], c.pi_js_undefined(), &.{ path, try scope.text("utf-8") }) catch |err| {
        try failure(&scope, diagnostics, path, err, read_generation, "failed to read prompt template file");
        return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_null(), diagnostics));
    };
    const parse_generation = engine.native_allocation_generation;
    const parsed = parse(&scope, raw) catch |err| {
        try failure(&scope, diagnostics, path, err, parse_generation, "failed to parse prompt template file");
        return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_null(), diagnostics));
    };
    const basename = try scope.call(roots[1], c.pi_js_undefined(), &.{path});
    const replace = try scope.get(basename, "replace");
    var regex_args = [_]c.JSValue{try scope.text("\\.md$")};
    const regex = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, regex_args.len, &regex_args)));
    const name = try scope.call(replace, basename, &.{ regex, try scope.text("") });
    const maybe_description = try scope.get(parsed.frontmatter, "description");
    var description = if (c.JS_IsString(maybe_description)) try scope.get(parsed.frontmatter, "description") else try scope.text("");
    if (!scope.truthy(description)) {
        const lines = try scope.invoke(parsed.body, "split", &.{try scope.text("\n")});
        const find = try scope.get(lines, "find");
        const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, nonempty, "", 1)));
        const first = try scope.call(find, lines, &.{predicate});
        if (scope.truthy(first)) {
            description = try scope.invoke(first, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 60) });
            if (scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, try scope.get(first, "length"), c.JS_NewInt32(engine.context, 60)))))) description = try scope.concat(description, try scope.text("..."));
        }
    }
    const maybe_hint = try scope.get(parsed.frontmatter, "argument-hint");
    const hint = if (c.JS_IsString(maybe_hint)) try scope.get(parsed.frontmatter, "argument-hint") else c.pi_js_undefined();
    const template = try scope.object();
    try scope.put(template, "name", name);
    try scope.put(template, "description", description);
    if (scope.truthy(hint)) try scope.put(template, "argumentHint", hint);
    try scope.put(template, "content", parsed.body);
    try scope.put(template, "sourceInfo", source_info);
    try scope.put(template, "filePath", path);
    return c.JS_DupValue(engine.context, try result(&scope, template, diagnostics));
}
