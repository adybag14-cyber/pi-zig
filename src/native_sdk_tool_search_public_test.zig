//! Genuine complete c268 tool-search controls. Each Source/native run has a
//! fresh Engine and the same real TypeBox import graph. No Source capture or
//! native execution is claimed by this authored test root.
const std = @import("std");
const t = @import("extensions/native_sdk_tool_search_values.zig");
const h = t.h;
const v = t.v;
const c = t.c;
const subject = @import("extensions/native_sdk_tool_search.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-tool-search-observer.mjs");

// Actual C sole-holder finalizers, used only to compare the order of the
// destructuring opcode's receiver/next roots and prior lexical bindings.
const OrderRecord = struct {
    engine: *t.Engine,
    holder_class: c.JSClassID,
    items: [16]u32 = @splat(0),
    count: usize = 0,
    overflow: bool = false,
};
const OrderHolder = struct { record: c.JSValue, slot: u32 };
fn orderRecord(value: c.JSValue) *OrderRecord {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn orderRecordFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const record: *OrderRecord = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    record.engine.gpa.destroy(record);
}
fn orderHolderMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const holder: *OrderHolder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, holder.record, visit);
}
fn orderHolderFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const holder: *OrderHolder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const record = orderRecord(holder.record);
    const engine = record.engine;
    if (record.count < record.items.len) {
        record.items[record.count] = holder.slot;
        record.count += 1;
    } else record.overflow = true;
    c.JS_FreeValueRT(runtime, holder.record);
    engine.gpa.destroy(holder);
}
fn orderMakeBody(s: *t.Scope, index: c.JSValue, owner: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(index)) return v.typeError(s, "order slot must be a number");
    var slot: u32 = 0;
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    try boundary.finishStatus(c.JS_ToUint32(s.engine.context, &slot, index));
    if (slot >= 16) return v.typeError(s, "order slot out of range");
    const record = orderRecord(owner);
    const value = try v.objectClass(s, record.holder_class);
    const holder = try s.engine.gpa.create(OrderHolder);
    holder.* = .{ .record = v.duplicate(s, owner), .slot = slot };
    _ = c.JS_SetOpaque(value, holder);
    return v.duplicate(s, value);
}
fn orderMake(engine: *t.Engine, _: c.JSValue, args: *t.Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, orderMakeBody, .{args.get(0), roots[0]});
}
fn orderReadBody(s: *t.Scope, owner: c.JSValue) !c.JSValue {
    const record = orderRecord(owner);
    if (record.overflow) return error.ToolSearchOrderRecordOverflow;
    const result = try v.array(s);
    for (record.items[0..record.count], 0..) |slot, index| try v.index(s, result, @intCast(index), c.JS_NewUint32(s.engine.context, slot));
    return v.duplicate(s, result);
}
fn orderRead(engine: *t.Engine, _: c.JSValue, _: *t.Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, orderReadBody, .{roots[0]});
}
fn createOrderHooks(s: *t.Scope) !c.JSValue {
    const engine = s.engine;
    var record_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &record_class);
    const record_definition: c.JSClassDef = .{ .class_name = "Actual tool-search order record", .finalizer = orderRecordFinalizer };
    if (c.JS_NewClass(engine.runtime, record_class, &record_definition) < 0) return error.OutOfMemory;
    var holder_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &holder_class);
    const holder_definition: c.JSClassDef = .{ .class_name = "Actual tool-search order holder", .finalizer = orderHolderFinalizer, .gc_mark = orderHolderMark };
    if (c.JS_NewClass(engine.runtime, holder_class, &holder_definition) < 0) return error.OutOfMemory;
    const owner = try v.objectClass(s, record_class);
    const record = try engine.gpa.create(OrderRecord); record.* = .{ .engine = engine, .holder_class = holder_class };
    _ = c.JS_SetOpaque(owner, record);
    const result = try v.object(s);
    try v.put(s, result, "make", try t.function(s, "make", 1, .{ .formal_count = 1, .callback = orderMake }, &.{owner}));
    try v.put(s, result, "read", try t.function(s, "read", 0, .{ .formal_count = 0, .callback = orderRead }, &.{owner}));
    return v.duplicate(s, result);
}

fn publish(s: *t.Scope, name: [*:0]const u8, input: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, input);
}
fn asyncBrand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn prepare(engine: *t.Engine) !void { return h.statement(engine, prepareBody, .{}); }
fn prepareBody(s: *t.Scope) !void {
    const engine = s.engine;
    const native = try v.own(s, try subject.create(engine));
    try std.testing.expect(v.equal(s, native, try v.own(s, try subject.create(engine))));
    const typebox = try v.own(s, try @import("extensions/native_typebox_production_graph.zig").create(engine));
    const types = try v.get(s, typebox, "Type");
    const factory = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-tool-search-c268-source.mjs"),
        "actual-c268-tool-search-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{types});
    try publish(s, "toolSearchNative", native);
    try publish(s, "toolSearchSource", reference);
    try publish(s, "toolSearchHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
    try publish(s, "toolSearchOrder", try v.own(s, try createOrderHooks(s)));
    try publish(s, "toolSearchIsAsync", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, asyncBrand, "toolSearchIsAsync", 1))));
}
fn run(engine: *t.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-tool-search-control.mjs"));
}
fn clean(engine: *t.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime extra: []const u8) !void {
    inline for (.{ "toolSearchSource", "toolSearchNative" }) |which| {
        const engine = try t.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ which ++ ",toolSearchHooks" ++ extra ++ ");\n");
        try clean(engine);
    }
}
fn recordBody(s: *t.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "toolSearchHooks"), "record"));
}
fn expectOwnFalse(engine: *t.Engine, record: c.JSValue, name: [*:0]const u8) !void {
    // The retained control record has a known own Boolean data property.
    // Read it directly without a guest callback or a post-fatal entry check.
    const value = c.JS_GetPropertyStr(engine.context, record, name);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, c.JS_NewBool(engine.context, false)));
}
const FatalKind = enum { current, retirement, cancelled };
fn fatal(comptime name: []const u8, comptime extra: []const u8, comptime kind: FatalKind) !void {
    const engine = try t.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit(); try prepare(engine);
    const original = try h.expression(engine, recordBody, .{}); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait " ++ name ++
        "(toolSearchNative,toolSearchHooks" ++ extra ++ ");\n"));
    switch (kind) {
        .current => try retirement.verifyRecordedActualNativeFatal(engine, original),
        .retirement => try retirement.verifyActualRetirementFatal(engine, original, 0),
        .cancelled => try retirement.verifyActualCancellationNoGuestClose(engine, original),
    }
    try retirement.verifyNoVisits(original, .{1,2,3});
    try expectOwnFalse(engine, original, "guestReached");
    try std.testing.expect(engine.native_fatal_invocation == null);
}
fn explicitReason(s: *t.Scope) !c.JSValue {
    const hooks = try v.global(s, "toolSearchHooks");
    const reason = try v.call(s, try v.get(s, hooks, "freshPrivateData"), hooks, &.{});
    // Controlled successful native DATA, flagged without creating a pending
    // throw. Only the subject's later Source throw may normalize this value.
    c.JS_SetUncatchableError(s.engine.context, reason);
    try publish(s, "toolSearchExplicitReason", reason);
    return v.duplicate(s, reason);
}
test "SDK public tool search actual declarations async methods and extension shapes" { try both("observeToolSearchShapes", ""); }
test "SDK public tool search genuine TypeBox schema and emitted class field order" { try both("observeToolSearchSchemaAndClass", ""); }
test "SDK public tool search actual tokenizer stop words camel case and stemming" { try both("observeToolSearchTokenize", ""); }
test "SDK public tool search live tokenizer literals receiver and callee retirement" { try both("observeToolSearchTokenChain", ""); }
test "SDK public tool search retained filter callback retires comparison operand" { try both("observeToolSearchFilterPredicate", ""); }
test "SDK public tool search actual recursive schema document and namespace" { try both("observeToolSearchDocument", ""); }
test "SDK public tool search repeated document fields and typeof short circuit" { try both("observeToolSearchDocumentOrder", ""); }
test "SDK public tool search real schema destructuring and outer IteratorClose" {
    try both("observeToolSearchSchemaIteratorClose", "");
    try both("observeToolSearchSchemaPairRetirement", ",false");
    try both("observeToolSearchSchemaPairRetirement", ",true");
}
test "SDK public tool search genuine BM25 scores unique query terms and stable ties" { try both("observeToolSearchRanking", ""); }
test "SDK public tool search actual idf parameter and counts captures survive return" { try both("observeToolSearchIdfCapture", ""); }
test "SDK public tool search escaped scorer keeps only its original lexical cells" { try both("observeToolSearchScoreCapture", ""); }
test "SDK public tool search searches inactive tools and updates the real active set" { try both("observeToolSearchActivation", ""); }
test "SDK public tool search repeated tools getter and escaped active predicate" { try both("observeToolSearchLiveTools", ""); }
test "SDK public tool search actual query integer and destructuring validation" { try both("observeToolSearchValidation", ""); }
test "SDK public tool search one boxed binding and immediate integer predicate" { try both("observeToolSearchBindingAndPredicates", ""); }
test "SDK public tool search zero Await keeps original arguments and locals through adoption" { try both("observeToolSearchZeroAwaitLifetime", ""); }
test "SDK public tool search options use actual parameter ref without unrelated captures" { try both("observeToolSearchOptionCapture", ""); }
test "SDK public tool search intrinsic response templates and abrupt string conversion" { try both("observeToolSearchTemplates", ""); }
test "SDK public tool search description call chain retires before template conversion" { try both("observeToolSearchDescriptionRetirement", ""); }
test "SDK public tool search genuine extension registration spread and default factory" { try both("observeToolSearchExtension", ""); }
test "SDK public tool search ordinary private DATA survives all real public routes" {
    try both("observeToolSearchPrivateData", ",\"token\"");
    try both("observeToolSearchPrivateData", ",\"schema\"");
    try both("observeToolSearchPrivateData", ",\"rank\"");
    try both("observeToolSearchPrivateData", ",\"execute\"");
    try both("observeToolSearchPrivateData", ",\"extension\"");
}
test "SDK public tool search current fatal prevents later validation tools and catch" { try fatal("observeToolSearchCurrentFatal", "", .current); }
test "SDK public tool search trim callee retirement fatal prevents later fields" { try fatal("observeToolSearchCalleeStop", ",false", .retirement); }
test "SDK public tool search trim callee cancellation prevents later guest work" { try fatal("observeToolSearchCalleeStop", ",true", .cancelled); }
test "SDK public tool search actual rank callback fatal prevents later work and catch" { try fatal("observeToolSearchRankFatal", "", .current); }
test "SDK public tool search explicit Error throw normalizes successful flagged DATA" {
    inline for (.{ "toolSearchSource", "toolSearchNative" }) |which| {
        inline for (.{ "query", "limit" }) |kind| {
            const engine = try t.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
            defer engine.deinit(); try prepare(engine);
            const original = try h.expression(engine, recordBody, .{}); defer engine.freeValue(original);
            const reason = try h.expression(engine, explicitReason, .{}); defer engine.freeValue(reason);
            try std.testing.expect(!c.JS_HasException(engine.context));
            try std.testing.expect(c.JS_IsUncatchableError(reason));
            try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
            try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
                "\nawait observeToolSearchExplicitThrow(" ++ which ++ ",toolSearchHooks,\"" ++ kind ++ "\");"));
            const captured = engine.captured_exception orelse return error.MissingActualExplicitToolSearchThrow;
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, captured));
            try std.testing.expect(c.JS_IsUncatchableError(captured));
            try retirement.verifyNoVisits(original, .{1,2,3});
            try expectOwnFalse(engine, original, "guestReached");
            try std.testing.expect(engine.native_fatal_invocation == null);
        }
    }
}
