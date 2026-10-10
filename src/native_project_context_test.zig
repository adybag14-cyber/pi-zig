const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
test "Source f1 SDK resource loader and CLI share global deduplication and ancestor ordering" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try scratch.dir.realPath(io, &buffer);
    try scratch.dir.createDirPath(io, "project/src");
    try scratch.dir.writeFile(io, .{ .sub_path = "AGENTS.md", .data = "ancestor" });
    try scratch.dir.writeFile(io, .{ .sub_path = "project/AGENTS.override.md", .data = "\xef\xbb\xbfglobal once" });
    try scratch.dir.writeFile(io, .{ .sub_path = "project/src/CLAUDE.md", .data = "child" });
    const cwd = try std.fs.path.resolve(gpa, &.{ buffer[0..n], "project/src" });
    defer gpa.free(cwd);
    const agent = try std.fs.path.resolve(gpa, &.{ buffer[0..n], "project" });
    defer gpa.free(agent);
    const options = try std.json.Stringify.valueAlloc(gpa, .{ .cwd = cwd, .agentDir = agent, .noExtensions = true, .noSkills = true, .noPromptTemplates = true, .noThemes = true }, .{});
    defer gpa.free(options);
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("context-sdk", exports);
    const source = try std.fmt.allocPrint(gpa, "import {{DefaultResourceLoader}} from 'context-sdk';const loader=new DefaultResourceLoader({s});await loader.reload();globalThis.contextFiles=loader.getAgentsFiles().agentsFiles;export const proof=true;", .{options});
    defer gpa.free(source);
    const evaluation = try engine.evalModule(source, "source-f1-context-sdk");
    defer engine.freeValue(evaluation);
    const value = try engine.eval("JSON.stringify(contextFiles)", "source-f1-context-result", engine_mod.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const text = try engine.toString(value);
    defer gpa.free(text);
    var result = try json.Owned.parse(gpa, text);
    defer result.deinit();
    var cli = try @import("coding_agent/context.zig").discoverTrusted(gpa, io, cwd, agent, true);
    defer cli.deinit(gpa);
    try std.testing.expectEqual(cli.files.len, result.value.array.items.len);
    for (cli.files, result.value.array.items) |file, row| {
        try std.testing.expectEqualStrings(file.path, row.object.get("path").?.string);
        try std.testing.expectEqualStrings(file.content, row.object.get("content").?.string);
    }
    try std.testing.expectEqualStrings("global once", cli.files[0].content);
    try std.testing.expectEqualStrings("ancestor", cli.files[1].content);
    try std.testing.expectEqualStrings("child", cli.files[cli.files.len - 1].content);
}
