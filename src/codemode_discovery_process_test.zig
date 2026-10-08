//! Production CLI discovery/declaration/nested execution without Node on PATH.
const std = @import("std");
test "actual codemode discovers selected native and namespaced extension tools without Node" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.testing.environ.createMap(gpa);
    defer environ.deinit();
    const binary = try gpa.dupe(u8, environ.get("PI_CODEMODE_BINARY") orelse return error.MissingCodemodeBinary);
    defer gpa.free(binary);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const directory = buffer[0..length];
    try tmp.dir.createDir(io, "agent", .default_dir);
    try tmp.dir.createDir(io, "home", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "input.txt", .data = "DECLARED_READ_BODY" });
    try tmp.dir.writeFile(io, .{ .sub_path = "extension.mjs", .data = "export default pi=>pi.registerTool({name:'issues-list',description:'List repository issues',parameters:{type:'object',properties:{repo:{type:'string'}},required:['repo']},outputSchema:{type:'string'},namespace:{name:'mcp__dev-radius',description:'Repository tracker',instructions:'Track issues'},promptGuidelines:['Use repo name'],execute(){return {content:[{type:'text',text:'NAMESPACED_TOOL_BODY'}]}}})" });
    const code = "const found=await searchTools('read');if(!found.some(tool=>tool.name==='read'))throw Error('not found');const declaration=await describeTool('read');if(!declaration.includes('read(args:')||!declaration.includes('Promise<string>'))throw Error('bad declaration');const namespace=await describeNamespace('dev_radius');if(namespace.name!=='mcp__dev-radius'||namespace.tools[0]!=='issues_list')throw Error('namespace');const issue=await describeTool('issues_list');if(!issue.includes('- Use repo name')||!issue.includes('repo: string'))throw Error('metadata');text('DISCOVERY_OK');text(await tools.read({path:'input.txt'}));text(await tools.issues_list({repo:'native'}));";
    const arguments = try std.json.Stringify.valueAlloc(gpa, .{ .code = code }, .{});
    defer gpa.free(arguments);
    const mock = try std.json.Stringify.valueAlloc(gpa, .{ .{ .content = "", .tool_calls = .{.{ .id = "outer", .name = "codemode", .arguments = arguments }} }, .{ .content = "final" } }, .{});
    defer gpa.free(mock);
    try tmp.dir.writeFile(io, .{ .sub_path = "mock.json", .data = mock });
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("SystemRoot", "C:/Windows");
    try environment.put("WINDIR", "C:/Windows");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    try environment.put("PI_EXTENSION_BACKEND", "native");
    const home = try std.fs.path.join(gpa, &.{ directory, "home" });
    defer gpa.free(home);
    const agent = try std.fs.path.join(gpa, &.{ directory, "agent" });
    defer gpa.free(agent);
    try environment.put("HOME", home);
    try environment.put("USERPROFILE", home);
    try environment.put("PI_AGENT_DIR", agent);
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ binary, "-p", "--mode", "json", "--mock-script", "mock.json", "--tools", "read,codemode,issues-list", "--extension", "extension.mjs", "--no-context-files", "--no-skills", "--no-themes", "--no-prompt-templates", "--approve", "discover and read" },
        .cwd = .{ .path = directory },
        .environ_map = &environment,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0 or std.mem.indexOf(u8, result.stdout, "DISCOVERY_OK") == null) std.debug.print("Codemode discovery CLI stdout:\n{s}\nstderr:\n{s}\n", .{ result.stdout, result.stderr });
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "DISCOVERY_OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "DECLARED_READ_BODY") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NAMESPACED_TOOL_BODY") != null);
}
