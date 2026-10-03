//! Real native worker fixture: stripped environment has no Node executable.
const std = @import("std");
const builtin = @import("builtin");

test "native extension process loads TypeScript imports and exchanges real protocol records" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "marker.ts", .data = "export const marker: string = 'native-worker';" });
    try tmp.dir.writeFile(io, .{
        .sub_path = "extension.ts",
        .data = "import { Type } from 'typebox'; import { marker } from './marker.ts'; " ++
            "export default (pi: any) => { pi.on('input', async (event: any) => ({action:'transform',text:event.text+':'+marker})); " ++
            "pi.registerTool({name:'echo', parameters:Type.Object({text:Type.String()}), async execute(id:string,args:any) {return {content:[{type:'text',text:id+':'+args.text}],details:{marker}};}}); };",
    });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path_buffer);
    const source = try std.fs.path.join(gpa, &.{ path_buffer[0..length], "extension.ts" });
    defer gpa.free(source);
    const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi.exe" else "pi" });
    defer gpa.free(executable);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(executable).?);
    const stderr_file = try tmp.dir.createFile(io, "stderr.log", .{});
    var stderr_closed = false;
    defer if (!stderr_closed) stderr_file.close(io);
    var child = try std.process.spawn(io, .{
        .argv = &.{ executable, "--internal-native-extension-worker", source },
        .environ_map = &environment,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .{ .file = stderr_file },
        .create_no_window = true,
    });
    var reaped = false;
    defer if (!reaped) child.kill(io);
    var write_buffer: [2048]u8 = undefined;
    var stdin = child.stdin.?.writerStreaming(io, &write_buffer);
    try stdin.interface.writeAll(
        "{\"kind\":\"hook\",\"name\":\"before_prompt\",\"payload\":{\"prompt\":\"hello\"}}\n" ++
            "{\"kind\":\"tool\",\"name\":\"echo\",\"toolCallId\":\"call-real\",\"payload\":{\"text\":\"pi\"}}\n" ++
            "{\"kind\":\"shutdown\"}\n",
    );
    try stdin.interface.flush();
    child.stdin.?.close(io);
    child.stdin = null;
    var read_buffer: [4096]u8 = undefined;
    var stdout = child.stdout.?.readerStreaming(io, &read_buffer);
    const output = try stdout.interface.allocRemaining(gpa, .limited(1024 * 1024));
    defer gpa.free(output);
    const status = try child.wait(io);
    reaped = true;
    stderr_file.close(io);
    stderr_closed = true;
    const errors = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    if (status != .exited or status.exited != 0) {
        std.debug.print("Native worker failed: {s}\n", .{errors});
        return error.NativeWorkerFailed;
    }
    try std.testing.expectEqual(@as(usize, 0), errors.len);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\":\"ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hello:native-worker") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"content\":\"call-real:pi\"") != null);
    var records: usize = 0;
    for (output) |byte| if (byte == 0x1e) {
        records += 1;
    };
    try std.testing.expectEqual(@as(usize, 4), records);
}
