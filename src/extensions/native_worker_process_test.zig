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
            "const input=fs.readFileSync(import.meta.filename); if(!Buffer.isBuffer(input)||!input.toString('utf8').includes('native-worker'))throw Error('native binary filesystem'); " ++
            "export default (pi: any) => { console.log('native-console',{safe:true}); pi.on('input', async (event: any) => ({action:'transform',text:event.text+':'+marker})); " ++
            "pi.registerTool({name:'echo', parameters:Type.Object({text:Type.String()}), async execute(id:string,args:any,signal:any,update:any,ctx:any) {return {content:[{type:'text',text:id+':'+args.text}],details:{marker,dependency,session:ctx.sessionManager.getSessionId(),trusted:ctx.isProjectTrusted(),nativeTools:pi.getAllTools().map(tool=>tool.name),settings:pi.getSettings()}};}}); };",
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
            "{\"kind\":\"tool\",\"name\":\"echo\",\"toolCallId\":\"call-real\",\"payload\":{\"text\":\"pi\"},\"context\":{\"sessionId\":\"worker-session\",\"projectTrusted\":true,\"settings\":{\"mode\":\"native\"}}}\n" ++
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
    try std.testing.expect(std.mem.indexOf(u8, output, "\"nativeTools\":[\"echo\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"settings\":{\"mode\":\"native\"}") != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, output, "\"ok\":false"));
    var records: usize = 0;
    for (output) |byte| if (byte == 0x1e) {
        records += 1;
    };
    try std.testing.expectEqual(@as(usize, 7), records);
}

test "native worker loads CommonJS TypeScript JSON cycles and conditional require dependencies" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "node_modules/native-dual");
    try tmp.dir.writeFile(io, .{ .sub_path = "package.json", .data = "{\"type\":\"module\",\"imports\":{\"#fs\":\"node:fs\",\"#dual\":\"native-dual\"}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-dual/package.json", .data = "{\"type\":\"commonjs\",\"exports\":{\"require\":\"./require.js\",\"import\":\"./esm.mjs\"}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-dual/require.js", .data = "globalThis.dualLoads=(globalThis.dualLoads||0)+1; exports.branch='require'; exports.cycle=require('./a.cjs').saw; exports.json=require('./value.json').marker;" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-dual/esm.mjs", .data = "export const branch='import'; export default {branch};" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-dual/a.cjs", .data = "exports.name='a'; exports.saw=require('./b.cjs').saw;" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-dual/b.cjs", .data = "exports.saw=require('./a.cjs').name;" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/native-dual/value.json", .data = "{\"marker\":\"native-json\"}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "percent%20data.json", .data = "{\"literal\":true}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "changing.cjs", .data = "module.exports={value:1,change(){module.exports={value:2}}};" });
    try tmp.dir.writeFile(io, .{ .sub_path = "failure.cjs", .data = "globalThis.failureLoads=(globalThis.failureLoads||0)+1; exports.partial=true; throw Error('owned failure');" });
    try tmp.dir.writeFile(io, .{
        .sub_path = "extension.cts",
        .data = "const fs=require('#fs'); const dual=require('#dual'); const again=require('native-dual'); const path=require('node:path'); " ++
            "if (dual!==again || globalThis.dualLoads!==1 || dual.branch!=='require' || dual.cycle!=='a' || !require('./percent%20data').literal) throw Error('resolution/cache'); " ++
            "if (require.resolve('./changing.cjs')!==path.join(__dirname,'changing.cjs') || module.filename!==__filename || require.cache[__filename]!==module || module.loaded || typeof require.main!=='undefined') throw Error('module metadata'); " ++
            "const changing=require('./changing.cjs'); changing.change(); if(require('./changing.cjs').value!==2)throw Error('exports replacement'); delete require.cache[require.resolve('./changing.cjs')]; if(require('./changing.cjs').value!==1)throw Error('cache deletion'); " ++
            "for(let n=0;n<2;n++){let failed=false;try{require('./failure.cjs');}catch(error){failed=String(error).includes('owned failure');}if(!failed || require.cache[require.resolve('./failure.cjs')])throw Error('failure cache');}if(globalThis.failureLoads!==2)throw Error('failure retry'); " ++
            "module.exports=(pi: any)=>pi.registerTool({name:'cjs_echo',execute(id: string,args: any){return {content:[{type:'text',text:dual.json+':'+dual.cycle+':'+module.loaded}],details:{exists:fs.existsSync(__filename)}};}});",
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "extension.mjs", .data = "import dual,{branch} from 'native-dual'; import factory from './extension.cts'; import {createRequire} from 'node:module'; const require=createRequire(import.meta.url); if(branch!=='import' || dual.branch!=='import' || require('native-dual').branch!=='require')throw Error('conditional import/createRequire'); export default factory;" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi.exe" else "pi" });
    defer gpa.free(executable);
    for ([_][]const u8{ "extension.cts", "extension.mjs" }, 0..) |entry, index| {
        const source = try std.fs.path.join(gpa, &.{ buffer[0..length], entry });
        defer gpa.free(source);
        const stderr_name = try std.fmt.allocPrint(gpa, "stderr-{d}.log", .{index});
        defer gpa.free(stderr_name);
        const stderr_file = try tmp.dir.createFile(io, stderr_name, .{});
        var closed = false;
        defer if (!closed) stderr_file.close(io);
        var environment: std.process.Environ.Map = .init(gpa);
        defer environment.deinit();
        try environment.put("PATH", std.fs.path.dirname(executable).?);
        var child = try std.process.spawn(io, .{ .argv = &.{ executable, "--internal-native-extension-worker", source }, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .{ .file = stderr_file }, .create_no_window = true });
        var reaped = false;
        defer if (!reaped) child.kill(io);
        var write_buffer: [1024]u8 = undefined;
        var stdin = child.stdin.?.writerStreaming(io, &write_buffer);
        try stdin.interface.writeAll("{\"kind\":\"tool\",\"name\":\"cjs_echo\",\"payload\":{}}\n{\"kind\":\"shutdown\"}\n");
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
        closed = true;
        const errors = try tmp.dir.readFileAlloc(io, stderr_name, gpa, .limited(1024 * 1024));
        defer gpa.free(errors);
        if (status != .exited or status.exited != 0) {
            std.debug.print("Native CommonJS worker {s} failed: {s}\n", .{ entry, errors });
            return error.NativeCommonJsWorkerFailed;
        }
        try std.testing.expectEqualStrings("", errors);
        try std.testing.expect(std.mem.indexOf(u8, output, "native-json:a:true") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "\"exists\":true") != null);
        try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, output, "\x1e"));
    }
}

test "native provider process retains callbacks across replacement with Node absent" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{
        .sub_path = "provider.ts",
        .data = "export default function(pi:any){const closure='native-closure';pi.registerProvider('native provider',{name:'Native',key(value:string){return this.name+':'+closure+':'+value},nested:{owner:'nested',async key(credentials:any){return this.owner+':'+credentials.access}}});pi.registerCommand('rename',{handler(){pi.registerProvider('native provider',{name:'Renamed'})}});pi.registerCommand('retire',{handler(){pi.unregisterProvider('native provider')}})}",
    });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "provider.ts" });
    defer gpa.free(source);
    const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi.exe" else "pi" });
    defer gpa.free(executable);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(executable).?);
    const stderr_file = try tmp.dir.createFile(io, "stderr.log", .{});
    var closed = false;
    defer if (!closed) stderr_file.close(io);
    var child = try std.process.spawn(io, .{ .argv = &.{ executable, "--internal-native-extension-worker", source }, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .{ .file = stderr_file }, .create_no_window = true });
    var reaped = false;
    defer if (!reaped) child.kill(io);
    var write_buffer: [2048]u8 = undefined;
    var stdin = child.stdin.?.writerStreaming(io, &write_buffer);
    try stdin.interface.writeAll(
        "{\"kind\":\"provider_method\",\"callbackId\":\"provider:native%20provider:2\",\"args\":[{\"access\":\"token\"}]}\n" ++
            "{\"kind\":\"command\",\"name\":\"rename\"}\n" ++
            "{\"kind\":\"provider_method\",\"callbackId\":\"provider:native%20provider:1\",\"args\":[\"old\"]}\n" ++
            "{\"kind\":\"provider_method\",\"callbackId\":\"provider:native%20provider:3\",\"args\":[\"new\"]}\n" ++
            "{\"kind\":\"provider_method\",\"callbackId\":\"provider:native%20provider:3\",\"args\":[],\"appendSignal\":true}\n" ++
            "{\"kind\":\"command\",\"name\":\"retire\"}\n" ++
            "{\"kind\":\"provider_method\",\"callbackId\":\"provider:native%20provider:3\",\"args\":[]}\n" ++
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
    closed = true;
    const errors = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    if (status != .exited or status.exited != 0) {
        std.debug.print("Native provider worker failed: {s}\n", .{errors});
        return error.NativeProviderWorkerFailed;
    }
    try std.testing.expectEqualStrings("", errors);
    for ([_][]const u8{ "nested:token", "Native:native-closure:old", "Renamed:native-closure:new", "register_provider", "unregister_provider", "NativeProviderAbortSignalUnsupported", "UnknownNativeProviderCallback" }) |marker| {
        if (std.mem.indexOf(u8, output, marker) == null) {
            std.debug.print("Native provider process missing {s}: {s}\n", .{ marker, output });
            return error.NativeProviderProtocolMismatch;
        }
    }
    try std.testing.expectEqual(@as(usize, 9), std.mem.count(u8, output, "\x1e"));
}
