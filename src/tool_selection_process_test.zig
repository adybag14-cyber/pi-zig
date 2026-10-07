//! Actual no-Node CLI loadout transitions, not only selector helper exports.
const std = @import("std");
const Fixture = @import("native_runtime_process_test.zig").Fixture;
const source =
    \\export default pi=>{
    \\ const tool=(name,active=true)=>({name,defaultActive:active,parameters:{type:'object'},execute(){return {content:[{type:'text',text:name}]}}});
    \\ pi.registerTool(tool('always'));pi.registerTool(tool('sticky',false));
    \\ pi.registerTool({...tool('hidden'),exposure:'hidden'});pi.registerTool({...tool('deferred',false),exposure:'deferred'});
    \\ pi.registerCommand('probe',{handler(){return {message:'SNAP:'+JSON.stringify(pi.getActiveTools())}}});
    \\ pi.registerCommand('flip',{handler(){const before=pi.getActiveTools().includes('sticky');pi.registerTool(tool('sticky',true));const middle=pi.getActiveTools().includes('sticky');pi.registerTool(tool('sticky',false));return {message:'FLIP:'+JSON.stringify({before,middle,after:pi.getActiveTools().includes('sticky')})}}});
    \\ pi.registerCommand('mixed',{handler(){pi.registerTool(tool('before'));pi.setActiveTools(['sticky']);pi.registerTool(tool('after'));return {message:'MIXED:'+JSON.stringify(pi.getActiveTools())}}});
    \\ pi.registerCommand('next-tool',{handler(){pi.registerTool(tool('new'));return {message:'NEW:'+JSON.stringify(pi.getActiveTools())}}});
    \\ pi.registerCommand('reverse',{handler(){pi.setActiveTools(['sticky','always']);return {message:'REVERSE:'+JSON.stringify(pi.getActiveTools())}}});
    \\ pi.registerCommand('sdk-select',{handler(){pi.setActiveTools(['unknown','hidden','sticky','deferred']);return {message:'SDK:'+JSON.stringify(pi.getActiveTools())}}});
    \\ pi.registerCommand('hide-always',{handler(){pi.registerTool({...tool('always'),exposure:'hidden'});return {message:'HIDE:'+JSON.stringify(pi.getActiveTools())}}});
    \\}
;
const Case = struct { args: []const []const u8 = &.{}, prompts: []const []const u8, expected: []const []const u8, builtins: bool = false };
test "native CLI tool selection matches source defaults modifiers SDK ordering visibility and registration transitions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource(source);
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(io, "agent");
    try fixture.tmp.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"quietStartup\":true,\"enableInstallTelemetry\":false,\"retry\":{\"enabled\":false}}" });
    try fixture.tmp.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"done\"}]" });
    const agent_dir = try std.fs.path.join(gpa, &.{fixture.root, "agent"});
    defer gpa.free(agent_dir);
    const mock = try std.fs.path.join(gpa, &.{fixture.root, "mock.json"});
    defer gpa.free(mock);
    try fixture.environment.put("PI_AGENT_DIR", agent_dir);
    try fixture.environment.put("HOME", fixture.root);
    try fixture.environment.put("USERPROFILE", fixture.root);
    try fixture.environment.put("PI_EXTENSION_BACKEND", "native");
    try fixture.environment.put("PI_SKIP_VERSION_CHECK", "1");
    try fixture.environment.put("PI_TELEMETRY", "0");
    const cases = [_]Case{
        .{ .prompts = &.{"/probe", "/flip", "/probe"}, .expected = &.{ "SNAP:[\"always\"]", "FLIP:{\"before\":false,\"middle\":true,\"after\":true}", "SNAP:[\"always\",\"sticky\"]" } },
        .{ .args = &.{"--tools", "+sticky,-always"}, .prompts = &.{"/probe"}, .expected = &.{"SNAP:[\"sticky\"]"} },
        .{ .prompts = &.{"/mixed", "/probe", "/next-tool", "/probe"}, .expected = &.{ "MIXED:[\"sticky\",\"after\"]", "SNAP:[\"sticky\",\"after\"]", "NEW:[\"sticky\",\"after\",\"new\"]", "SNAP:[\"sticky\",\"after\",\"new\"]" } },
        .{ .args = &.{"--tools", "-sticky"}, .prompts = &.{"/flip", "/probe"}, .expected = &.{"FLIP:{\"before\":false,\"middle\":false,\"after\":false}", "SNAP:[\"always\"]"} },
        .{ .prompts = &.{"/reverse", "/probe"}, .expected = &.{"REVERSE:[\"sticky\",\"always\"]", "SNAP:[\"sticky\",\"always\"]"} },
        .{ .prompts = &.{"/sdk-select", "/probe"}, .expected = &.{"SDK:[\"sticky\",\"deferred\"]", "SNAP:[\"sticky\",\"deferred\"]"} },
        .{ .args = &.{"--no-tools", "--tools", "+sticky"}, .prompts = &.{"/probe"}, .expected = &.{"SNAP:[\"sticky\"]"} },
        .{ .args = &.{"--exclude-tools", "sti*"}, .prompts = &.{"/flip", "/probe"}, .expected = &.{"FLIP:{\"before\":false,\"middle\":false,\"after\":false}", "SNAP:[\"always\"]"} },
        .{ .args = &.{"--tools", "+deferred"}, .prompts = &.{"/probe"}, .expected = &.{"SNAP:[\"always\"]"} },
        .{ .prompts = &.{"/hide-always", "/probe"}, .expected = &.{"HIDE:[]", "SNAP:[]"} },
        .{ .prompts = &.{"/probe"}, .expected = &.{"SNAP:[\"read\",\"bash\",\"edit\",\"write\",\"always\"]"}, .builtins = true },
    };
    for (cases, 0..) |case, index| {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, &.{fixture.executable, "--offline", "--print", "--mock-script", mock, "--no-session", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve", "-e", fixture.source_path});
        if (!case.builtins) try argv.append(gpa, "--no-builtin-tools");
        try argv.appendSlice(gpa, case.args);
        try argv.appendSlice(gpa, case.prompts);
        const result = try std.process.run(gpa, io, .{ .argv = argv.items, .cwd = .{ .path = fixture.root }, .environ_map = &fixture.environment, .stdout_limit = .limited(1024 * 1024), .stderr_limit = .limited(1024 * 1024), .timeout = .{ .duration = .{ .raw = .fromSeconds(20), .clock = .awake } } });
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            std.debug.print("Selection case {d}: {s}\n{s}\n", .{index, result.stdout, result.stderr});
            return error.NativeSelectionCliFailed;
        }
        for (case.expected) |expected| if (std.mem.indexOf(u8, result.stdout, expected) == null) {
            std.debug.print("Selection case {d} expected {s}\nactual: {s}\n", .{index, expected, result.stdout});
            return error.NativeSelectionCliMismatch;
        };
    }
}
