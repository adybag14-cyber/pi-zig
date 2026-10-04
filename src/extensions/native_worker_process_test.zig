//! Real native worker fixture: stripped environment has no Node executable.
const std = @import("std");
const builtin = @import("builtin");

test "native extension process loads TypeScript imports and exchanges real protocol records" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "node_modules/native-fixture/lib");
    try tmp.dir.writeFile(io, .{ .sub_path = "package.json", .data = "{\"name\":\"native-project\",\"imports\":{\"#dep\":\"native-fixture\",\"#fs\":\"node:fs\"}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-fixture/package.json", .data = "{\"type\":\"module\",\"exports\":{\".\":{\"import\":\"./lib/index.js\"}}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-fixture/lib/value file.js", .data = "export const dependency='esm-dependency'; export const metadata=import.meta;" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-fixture/lib/index.js", .data = "export {dependency,metadata} from './value%20file.js';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "marker.ts", .data = "export const marker: string = 'native-worker';" });
    try tmp.dir.writeFile(io, .{
        .sub_path = "extension.ts",
        .data = "import { Type } from 'typebox'; import { marker } from './marker'; import {dependency,metadata} from '#dep'; import fs from '#fs'; " ++
            "import {dirname,join,relative} from 'node:path'; import {fileURLToPath} from 'node:url'; " ++
            "if (import.meta.main!==false || metadata.main!==false || !metadata.url.endsWith('/value%20file.js') || !metadata.filename.endsWith('value file.js') || !fs.existsSync(import.meta.filename)) throw Error('native metadata'); " ++
            "if (fileURLToPath(import.meta.url)!==import.meta.filename || dirname(import.meta.filename)!==import.meta.dirname || relative(import.meta.dirname,join(import.meta.dirname,'marker.ts'))!=='marker.ts') throw Error('native paths'); " ++
            "export default (pi: any) => { console.log('native-console',{safe:true}); pi.on('input', async (event: any) => ({action:'transform',text:event.text+':'+marker})); " ++
            "pi.registerTool({name:'echo', parameters:Type.Object({text:Type.String()}), async execute(id:string,args:any,signal:any,update:any,ctx:any) {return {content:[{type:'text',text:id+':'+args.text}],details:{marker,dependency,session:ctx.sessionManager.getSessionId(),trusted:ctx.isProjectTrusted()}};}}); };",
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
        "{\n[]\n{\"kind\":\"unsupported\"}\n" ++
            "{\"kind\":\"hook\",\"name\":\"before_prompt\",\"payload\":{\"prompt\":\"hello\"}}\n" ++
            "{\"kind\":\"tool\",\"name\":\"echo\",\"toolCallId\":\"call-real\",\"payload\":{\"text\":\"pi\"},\"context\":{\"sessionId\":\"worker-session\",\"projectTrusted\":true}}\n" ++
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
    try std.testing.expectEqualStrings("native-console {\"safe\":true}\n", errors);
    try std.testing.expect(std.mem.indexOf(u8, output, "native-console") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\":\"ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hello:native-worker") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"content\":\"call-real:pi\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"session\":\"worker-session\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"trusted\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"dependency\":\"esm-dependency\"") != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, output, "\"ok\":false"));
    var records: usize = 0;
    for (output) |byte| if (byte == 0x1e) {
        records += 1;
    };
    try std.testing.expectEqual(@as(usize, 7), records);
}
