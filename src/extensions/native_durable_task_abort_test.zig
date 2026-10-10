const std = @import("std");
const em = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const json = @import("../durable/backend/json.zig");
const c = em.c;
fn compare(program: []const u8, expected_json: []const u8, name: [:0]const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const result = engine.evalModule(program, name) catch |err| {
        std.debug.print("Actual Source task abort {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no diagnostic" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "taskAbortTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, expected_json);
    defer expected.deinit();
    if (!json.equal(expected.value, actual.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual Source task abort trace: {s}\n", .{encoded});
        return error.SourceTaskAbortMismatch;
    }
}
test "native durable VM public task abort actual Storage protocol missing task and cancellation match Source" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source27-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source27.json"), "actual-task-abort-protocol");
}
test "native durable VM public task abort joins observed run while cleanup and unrelated task remain held" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source28-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source28.json"), "actual-task-abort-run-join");
}
test "native durable VM terminal task settlement retires unread actual Storage documents with empty public operations" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source29-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source29.json"), "actual-task-document-retirement");
}
test "native durable VM task abort observed-run cancellation uses Source AbortError for object reason and preserves Error identity" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source32-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source32.json"), "actual-task-abort-object-cancellation");
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source33-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source33.json"), "actual-task-abort-error-cancellation");
}
test "native durable VM task abort observed run ends with SessionFailed and original uncoerced Storage cause" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source31-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source31.json"), "actual-task-abort-failed-session");
}
test "native durable VM owned abort actual read keeps immutable owner bound Context and terminal cancellation bypass" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source38-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source38.json"), "actual-owned-abort-read-context");
}
test "native durable VM admitted runtime record reads retain original identities Context and invocation conversation" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source39-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source39.json"), "actual-runtime-read-identity");
}
test "native durable VM owned abort marks actual child then waits for terminal cleanup outside Session line" {
    try compare(@embedFile("../durable/fixtures/durable-custom-storage-source40-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source40.json"), "actual-owned-abort-live-child");
}
