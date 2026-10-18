//! Actual branch-summary collector, preparation and generation. The completion
//! binding is shared with ordinary compaction; no provider fallback is invented.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const math = @import("native_image_arithmetic.zig");
const files = @import("native_sdk_compaction_files.zig");
const text = @import("native_sdk_compaction_text.zig");
const replay = @import("native_sdk_transcript_replay.zig");
const c = em.c;
const Callback = enum(c_int) { id, tool };

pub fn exports(engine: *em.Engine, complete_request: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, complete_request)) return error.RequiredSharedNativeSummarizationBinding;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (.{ "collectEntriesForBranchSummary", "prepareBranchEntries" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return if (index == 0) collect(host, argument(args, 0), argument(args, 1), argument(args, 2)) else prepare(host, argument(args, 0), argument(args, 1));
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (index == 0) 3 else 1, Adapter.call, &.{})));
    }
    const converter = try scope.own(try @import("native_sdk_messages.zig").create(engine));
    var roots = [_]c.JSValue{ complete_request, converter };
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, generateCallback, "generateBranchSummary", 2, 0, roots.len, &roots)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    try scope.put(result, "generateBranchSummary", function);
    return c.JS_DupValue(engine.context, result);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn is(scope: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return scope.equal(value, try scope.text(expected));
}
fn at(scope: *Scope, array: c.JSValue, index: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, array, index));
}
fn binary(scope: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try math.binary(scope.engine, operation, left, right));
}
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
}
fn budget(engine: *em.Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: {
        engine.interrupts +|= 1;
        break :blk engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return predicateBody(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn predicateBody(engine: *em.Engine, kind: Callback, value: c.JSValue) !c.JSValue {
    if (kind == .id) return sdk.get(engine, value, "id");
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(try is(&scope, try scope.get(value, "type"), "toolCall")));
}
pub fn collect(engine: *em.Engine, session: c.JSValue, old_leaf: c.JSValue, target: c.JSValue) !c.JSValue {
    return @import("native_sdk_public_branch_entries.zig").collect(engine, session, old_leaf, target);
}
fn messageFromEntry(scope: *Scope, entry: c.JSValue) !c.JSValue {
    const kind = try scope.get(entry, "type");
    if (try is(scope, kind, "message")) {
        if (try is(scope, try scope.get(try scope.get(entry, "message"), "role"), "toolResult")) return c.pi_js_undefined();
        return scope.get(entry, "message");
    }
    var fields: [5]c.JSValue = undefined;
    const custom = try is(scope, kind, "custom_message");
    const branch = try is(scope, kind, "branch_summary");
    const compaction = try is(scope, kind, "compaction");
    if (!custom and !branch and !compaction) return c.pi_js_undefined();
    if (custom) {
        inline for (.{ "customType", "content", "display", "details", "timestamp" }, 0..) |name, i| fields[i] = try scope.get(entry, name);
    } else {
        fields[0] = try scope.get(entry, "summary");
        fields[1] = try scope.get(entry, if (branch) "fromId" else "tokensBefore");
        fields[2] = try scope.get(entry, "timestamp");
    }
    const result = try scope.object();
    try scope.put(result, "role", try scope.text(if (custom) "custom" else if (branch) "branchSummary" else "compactionSummary"));
    if (custom) {
        inline for (.{ "customType", "content", "display", "details" }, 0..) |name, i| try scope.put(result, name, fields[i]);
    } else {
        try scope.put(result, "summary", fields[0]);
        try scope.put(result, if (branch) "fromId" else "tokensBefore", fields[1]);
    }
    const date_class = try scope.global("Date");
    var input = [_]c.JSValue{fields[if (custom) 4 else 2]};
    const date = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, date_class, input.len, &input)));
    try scope.put(result, "timestamp", try scope.invoke(date, "getTime", &.{}));
    return result;
}
fn isArray(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !bool {
    const array = try scope.global("Array");
    const method = try scope.get(array, "isArray");
    return scope.truthy(try scope.call(method, array, &.{try scope.get(object, name)}));
}
pub fn prepare(engine: *em.Engine, entries: c.JSValue, supplied_budget: c.JSValue) !c.JSValue {
    return @import("native_sdk_public_branch_entries.zig").prepare(engine, entries, supplied_budget);
}
fn generateCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return generate(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn generate(engine: *em.Engine, entries: c.JSValue, options: c.JSValue, complete: c.JSValue, converter: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    generateStart(engine, pending.owner, entries, options, complete, converter) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn generateStart(engine: *em.Engine, owner: c.JSValue, entries: c.JSValue, options: c.JSValue, complete: c.JSValue, converter: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "model", "apiKey", "headers", "env", "signal", "customInstructions", "replaceInstructions", "reserveTokens", "streamFn", "retry", "callbacks" }) |name| try scope.put(owner, name, try scope.get(options, name));
    var reserve = try scope.get(owner, "reserveTokens");
    if (c.JS_IsUndefined(reserve)) reserve = c.JS_NewInt32(engine.context, 16384);
    var window = try scope.get(try scope.get(owner, "model"), "contextWindow");
    if (!scope.truthy(window)) window = c.JS_NewInt32(engine.context, 128000);
    const prepared = try scope.own(try prepare(engine, entries, try binary(&scope, .subtract, window, reserve)));
    const messages = try scope.get(prepared, "messages");
    const operations = try scope.get(prepared, "fileOps");
    if (scope.equal(try scope.get(messages, "length"), c.JS_NewInt32(engine.context, 0))) {
        const result = try scope.object();
        try scope.put(result, "summary", try scope.text("No content to summarize"));
        return flow.settle(engine, owner, false, result);
    }
    try scope.put(owner, "fileOps", operations);
    const llm = try scope.call(converter, c.pi_js_undefined(), &.{messages});
    const conversation = try scope.own(try text.serialize(engine, llm));
    const custom = try scope.get(owner, "customInstructions");
    const replace = try scope.get(owner, "replaceInstructions");
    var instructions = try scope.text(@embedFile("branch_summary_prompt_5ab.txt"));
    if (scope.truthy(replace) and scope.truthy(custom)) instructions = custom else if (scope.truthy(custom)) instructions = try scope.concat(try scope.concat(instructions, try scope.text("\n\nAdditional focus: ")), try scope.stringify(custom));
    var prompt = try scope.concat(try scope.text("<conversation>\n"), try scope.stringify(conversation));
    prompt = try scope.concat(prompt, try scope.text("\n</conversation>\n\n"));
    prompt = try scope.concat(prompt, try scope.stringify(instructions));
    const summary_messages = try scope.array();
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("user"));
    const content = try scope.array();
    const block = try scope.object();
    try scope.put(block, "type", try scope.text("text"));
    try scope.put(block, "text", prompt);
    try scope.index(content, 0, block);
    try scope.put(message, "content", content);
    try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.index(summary_messages, 0, message);
    const model = try scope.get(owner, "model");
    const raw_context = try scope.object();
    try scope.put(raw_context, "systemPrompt", try scope.text(@embedFile("compaction_system_prompt_b45.txt")));
    try scope.put(raw_context, "messages", summary_messages);
    const context = try scope.own(try @import("native_ai_transcript_context.zig").normalize(engine, raw_context));
    const request = try scope.object();
    inline for (.{ "apiKey", "headers", "env", "signal" }) |name| try scope.put(request, name, try scope.get(owner, name));
    try flow.wait(generated, engine, owner, try scope.call(complete, c.pi_js_undefined(), &.{ model, context, request, try scope.get(owner, "streamFn"), try scope.get(owner, "retry"), try scope.get(owner, "callbacks") }), 0);
}
fn generated(engine: *em.Engine, owner: c.JSValue, response: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, response);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    if (try is(&scope, try scope.get(response, "stopReason"), "aborted")) {
        try scope.put(result, "aborted", c.pi_js_bool(engine.context, 1));
        return flow.settle(engine, owner, false, result);
    }
    const failure = try scope.own(try text.failure(engine, response, try scope.text("Branch summarization")));
    if (scope.truthy(failure)) {
        try scope.put(result, "error", failure);
        return flow.settle(engine, owner, false, result);
    }
    const blocks = try scope.get(response, "content");
    const some = try scope.get(blocks, "some");
    const callback = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, predicate, "", 1, @intFromEnum(Callback.tool))));
    if (scope.truthy(try scope.call(some, blocks, &.{callback}))) {
        try scope.put(result, "error", try scope.text("Branch summarization attempted to call a tool"));
        return flow.settle(engine, owner, false, result);
    }
    var summary = try scope.own(try replay.contentText(engine, try scope.get(response, "content")));
    const preamble = try scope.concat(try scope.text(@embedFile("branch_summary_preamble_5ab.txt")), try scope.text("\n\n"));
    summary = try scope.concat(preamble, summary);
    const lists = try scope.own(try files.lists(engine, try scope.get(owner, "fileOps")));
    const read = try scope.get(lists, "readFiles");
    const modified = try scope.get(lists, "modifiedFiles");
    summary = try scope.concat(summary, try scope.own(try files.format(engine, read, modified)));
    try scope.put(result, "summary", if (scope.truthy(summary)) summary else try scope.text("No summary generated"));
    try scope.put(result, "usage", try scope.get(response, "usage"));
    try scope.put(result, "readFiles", read);
    try scope.put(result, "modifiedFiles", modified);
    try flow.settle(engine, owner, false, result);
}
