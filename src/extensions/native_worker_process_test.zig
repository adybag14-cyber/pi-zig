//! Real native worker fixture: stripped environment has no Node executable.
const std = @import("std");
const builtin = @import("builtin");
const activation = @import("tool_activation.zig");

fn consumeMetadata(gpa: std.mem.Allocator, value: std.json.Value) !bool {
    if (value != .object) return false;
    const object = value.object;
    const kind = object.get("type") orelse return false;
    if (kind != .string or !std.mem.eql(u8, kind.string, "native_metadata")) return false;
    const version = object.get("version") orelse return error.NativeFixtureInvalidMetadata;
    if (version != .integer or version.integer != 1) return error.NativeFixtureInvalidMetadata;
    const generation = try activation.Event.identifier(object.get("ownerGeneration") orelse return error.NativeFixtureInvalidMetadata);
    const revision = try activation.Event.identifier(object.get("revision") orelse return error.NativeFixtureInvalidMetadata);
    if (generation == 0 or revision == 0) return error.NativeFixtureInvalidMetadata;
    const extensions = object.get("extensions") orelse return error.NativeFixtureInvalidMetadata;
    if (extensions != .array or extensions.array.items.len > 4096) return error.NativeFixtureInvalidMetadata;
    for (extensions.array.items) |extension| {
        if (extension != .object) return error.NativeFixtureInvalidMetadata;
        const owner = try activation.Event.identifier(extension.object.get("extensionId") orelse return error.NativeFixtureInvalidMetadata);
        const path = extension.object.get("sourcePath") orelse return error.NativeFixtureInvalidMetadata;
        if (owner == 0 or path != .string) return error.NativeFixtureInvalidMetadata;
        for ([_][]const u8{ "tools", "commands", "hooks", "flags" }) |field| {
            const records = extension.object.get(field) orelse return error.NativeFixtureInvalidMetadata;
            if (records != .array) return error.NativeFixtureInvalidMetadata;
        }
    }
    if (object.get("toolRegistrations")) |records| {
        if (records != .array or records.array.items.len > 4096) return error.NativeFixtureInvalidMetadata;
        var previous: u64 = 0;
        for (records.array.items) |record| {
            var event = try activation.Event.parse(gpa, record);
            defer event.deinit(gpa);
            if (event.owner_generation != generation or event.sequence <= previous) return error.NativeFixtureInvalidMetadata;
            previous = event.sequence;
        }
        const last = try activation.Event.identifier(object.get("registrationSequence") orelse return error.NativeFixtureInvalidMetadata);
        if (previous != 0 and previous != last) return error.NativeFixtureInvalidMetadata;
    }
    return true;
}

const TranscriptCounts = struct { responses: usize = 0, metadata: usize = 0, errors: usize = 0 };
fn transcriptCounts(gpa: std.mem.Allocator, output: []const u8) !TranscriptCounts {
    var counts: TranscriptCounts = .{};
    var transcript = std.mem.splitScalar(u8, output, 0x1e);
    _ = transcript.next();
    while (transcript.next()) |record| {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, std.mem.trim(u8, record, "\r\n"), .{});
        defer parsed.deinit();
        if (try consumeMetadata(gpa, parsed.value)) {
            counts.metadata += 1;
            continue;
        }
        if (parsed.value != .object) return error.NativeFixtureRecordMismatch;
        counts.responses += 1;
        if (parsed.value.object.get("ok")) |ok| {
            if (ok != .bool) return error.NativeFixtureRecordMismatch;
            if (!ok.bool) counts.errors += 1;
        }
    }
    return counts;
}

fn readProtocolRecord(gpa: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    while (try reader.takeByte() != 0x1e) {}
    while (true) {
        const byte = try reader.takeByte();
        if (byte == '\n') return bytes.toOwnedSlice(gpa);
        if (bytes.items.len >= 1024 * 1024) return error.NativeFixtureRecordTooLarge;
        try bytes.append(gpa, byte);
    }
}

fn expectRecordContains(gpa: std.mem.Allocator, reader: *std.Io.Reader, marker: []const u8) !void {
    while (true) {
        const bytes = try readProtocolRecord(gpa, reader);
        defer gpa.free(bytes);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
        defer parsed.deinit();
        if (try consumeMetadata(gpa, parsed.value)) continue;
        if (std.mem.indexOf(u8, bytes, marker) == null) {
            std.debug.print("Native protocol expected {s}: {s}\n", .{ marker, bytes });
            return error.NativeFixtureRecordMismatch;
        }
        try std.testing.expect(parsed.value == .object);
        return;
    }
}

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
            "const decoder=new TextDecoder('utf-8',{fatal:true}); if(decoder.decode(Uint8Array.of(239,187),{stream:true})!=='' || decoder.decode(Uint8Array.of(191,112,105))!=='pi')throw Error('native streaming decoder'); " ++
            "const encoded=new Uint8Array(4);const counts=new TextEncoder().encodeInto('pi\\u{1f600}',encoded);if(counts.read!==2||counts.written!==2||decoder.decode(encoded.subarray(0,2))!=='pi')throw Error('native encoder counts'); " ++
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
    const counts = try transcriptCounts(gpa, output);
    try std.testing.expectEqual(@as(usize, 3), counts.errors);
    try std.testing.expectEqual(@as(usize, 7), counts.responses);
    try std.testing.expect(counts.metadata >= 1);
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
        const counts = try transcriptCounts(gpa, output);
        try std.testing.expectEqual(@as(usize, 3), counts.responses);
        try std.testing.expect(counts.metadata >= 1);
    }
}

test "native provider process retains callbacks across replacement with Node absent" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{
        .sub_path = "provider.ts",
        .data = "export default function(pi:any){const closure='native-closure';pi.registerProvider('native provider',{name:'Native',key(value:string,signal:any){if(signal&&!(signal instanceof AbortSignal))throw Error('native signal brand');return this.name+':'+closure+':'+value+(signal?(signal.aborted?':aborted':':active'):'')},nested:{owner:'nested',async key(credentials:any){await new Promise(resolve=>setTimeout(resolve,2));return this.owner+':'+credentials.access}}});pi.registerCommand('rename',{handler(){pi.registerProvider('native provider',{name:'Renamed'})}});pi.registerCommand('retire',{handler(){pi.unregisterProvider('native provider')}})}",
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
            "{\"kind\":\"provider_method\",\"callbackId\":\"provider:native%20provider:3\",\"args\":[\"signal\"],\"appendSignal\":true}\n" ++
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
    for ([_][]const u8{ "nested:token", "Native:native-closure:old", "Renamed:native-closure:new", "register_provider", "unregister_provider", "Renamed:native-closure:signal:active", "UnknownNativeProviderCallback" }) |marker| {
        if (std.mem.indexOf(u8, output, marker) == null) {
            std.debug.print("Native provider process missing {s}: {s}\n", .{ marker, output });
            return error.NativeProviderProtocolMismatch;
        }
    }
    const counts = try transcriptCounts(gpa, output);
    try std.testing.expectEqual(@as(usize, 9), counts.responses);
    try std.testing.expect(counts.metadata >= 1);
}

const control_fixture =
    \\export default function(pi){let previousSignal,oldUpdate;
    \\pi.registerTool({name:'control',async execute(id,args,signal,update,ctx){
    \\ if(!(signal instanceof AbortSignal)||ctx.signal!==signal||typeof update!=='function')throw Error('native invocation ABI');
    \\ if(args.mode==='wait'){previousSignal=signal;oldUpdate=update;update({content:'waiting',details:{id}});await new Promise(resolve=>signal.addEventListener('abort',resolve,{once:true}));update({content:'abort-observed'});return {content:'aborted:'+String(signal.reason),details:{aborted:signal.aborted}}}
    \\ if(args.mode==='ignore'){update({content:'ignoring'});await new Promise(()=>{});throw Error('unreachable')}
    \\ if(args.mode==='reuse'){if(signal.aborted||signal===previousSignal||!previousSignal.aborted)throw Error('signal reuse');oldUpdate({content:'stale-update'});update({content:'reuse-start'});await new Promise(resolve=>setTimeout(resolve,20));if(signal.aborted)throw Error('late abort crossed invocation');return {content:'reuse-clean'}}
    \\ if(args.mode==='buffered'){update({content:'partial-first'});update({content:'partial-second'});return {content:'buffered-complete'}}
    \\ if(args.mode==='exception'){const original=Error('original update getter');let caught=false;try{update({get content(){throw original}})}catch(error){if(error!==original)throw Error('update exception replaced');caught=true}if(!caught)throw Error('getter not evaluated');return {content:'original-preserved'}}
    \\ return {content:'native-control'};
    \\}})}
;

test "native worker processes live aborts and updates with reusable generation-fenced callbacks without Node" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "control.mjs", .data = control_fixture });
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path);
    const source = try std.fs.path.join(gpa, &.{ path[0..length], "control.mjs" });
    defer gpa.free(source);
    const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi.exe" else "pi" });
    defer gpa.free(executable);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(executable).?);
    const stderr_file = try tmp.dir.createFile(io, "stderr.log", .{});
    defer stderr_file.close(io);
    var child = try std.process.spawn(io, .{ .argv = &.{ executable, "--internal-native-extension-worker", source }, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .{ .file = stderr_file }, .create_no_window = true });
    var reaped = false;
    defer if (!reaped) child.kill(io);
    var input_buffer: [4096]u8 = undefined;
    var input = child.stdin.?.writerStreaming(io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = child.stdout.?.readerStreaming(io, &output_buffer);
    try expectRecordContains(gpa, &output.interface, "\"type\":\"ready\"");
    try input.interface.writeAll("{\"kind\":\"tool\",\"name\":\"control\",\"invocationId\":\"first\",\"toolCallId\":\"call-first\",\"payload\":{\"mode\":\"wait\"},\"streamUpdates\":true}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "\"content\":\"waiting\"");
    try input.interface.writeAll("{\"kind\":\"abort_current\",\"invocationId\":\"unrelated\",\"reason\":\"wrong\"}\n{\"kind\":\"abort_current\",\"invocationId\":\"first\",\"reason\":\"owned-reason\"}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "\"content\":\"abort-observed\"");
    try expectRecordContains(gpa, &output.interface, "\"content\":\"aborted:owned-reason\"");
    try input.interface.writeAll("{\"kind\":\"abort_current\",\"invocationId\":\"first\"}\n{\"kind\":\"tool\",\"name\":\"control\",\"invocationId\":\"second\",\"payload\":{\"mode\":\"reuse\"},\"streamUpdates\":true}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "\"content\":\"reuse-start\"");
    try input.interface.writeAll("{\"kind\":\"abort_current\",\"invocationId\":\"first\"}\n{\"kind\":\"abort_current\",\"reason\":\"untargeted\"}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "\"content\":\"reuse-clean\"");
    try input.interface.writeAll("{\"kind\":\"tool\",\"name\":\"control\",\"invocationId\":\"second\",\"payload\":{}}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "DuplicateNativeInvocationId");
    try input.interface.writeAll("{\"kind\":\"tool\",\"name\":\"control\",\"invocationId\":\"third\",\"payload\":{\"mode\":\"buffered\"}}\n");
    try input.interface.flush();
    const buffered = try readProtocolRecord(gpa, &output.interface);
    defer gpa.free(buffered);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, buffered, .{});
    defer parsed.deinit();
    const result = parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("buffered-complete", result.get("content").?.string);
    const updates = result.get("updates").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), updates.len);
    try std.testing.expectEqualStrings("partial-first", updates[0].object.get("content").?.string);
    try std.testing.expectEqualStrings("partial-second", updates[1].object.get("content").?.string);
    try input.interface.writeAll("{\"kind\":\"tool\",\"name\":\"control\",\"invocationId\":\"fourth\",\"payload\":{\"mode\":\"exception\"}}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "\"content\":\"original-preserved\"");
    try input.interface.writeAll("{\"kind\":\"shutdown\"}\n");
    try input.interface.flush();
    try expectRecordContains(gpa, &output.interface, "\"ok\":true");
    // Keep stdin open: shutdown must cancel/reap its blocked reader task,
    // rather than depending on the parent closing the pipe to finish teardown.
    const status = try child.wait(io);
    reaped = true;
    try std.testing.expect(status == .exited and status.exited == 0);
    const errors = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
}

test "native worker EOF settles cooperative abort or retires an uncooperative await without Node" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "eof.mjs", .data = control_fixture });
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path);
    const source = try std.fs.path.join(gpa, &.{ path[0..length], "eof.mjs" });
    defer gpa.free(source);
    const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi.exe" else "pi" });
    defer gpa.free(executable);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(executable).?);
    for ([_][]const u8{ "wait", "ignore" }) |mode| {
        var child = try std.process.spawn(io, .{ .argv = &.{ executable, "--internal-native-extension-worker", source }, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .ignore, .create_no_window = true });
        var reaped = false;
        defer if (!reaped) child.kill(io);
        var input_buffer: [4096]u8 = undefined;
        var input = child.stdin.?.writerStreaming(io, &input_buffer);
        var output_buffer: [4096]u8 = undefined;
        var output = child.stdout.?.readerStreaming(io, &output_buffer);
        try expectRecordContains(gpa, &output.interface, "\"type\":\"ready\"");
        try input.interface.print("{{\"kind\":\"tool\",\"name\":\"control\",\"invocationId\":\"eof\",\"payload\":{{\"mode\":{f}}},\"streamUpdates\":true}}\n", .{std.json.fmt(mode, .{})});
        try input.interface.flush();
        try expectRecordContains(gpa, &output.interface, if (std.mem.eql(u8, mode, "wait")) "\"content\":\"waiting\"" else "\"content\":\"ignoring\"");
        child.stdin.?.close(io);
        child.stdin = null;
        if (std.mem.eql(u8, mode, "wait")) {
            try expectRecordContains(gpa, &output.interface, "\"content\":\"abort-observed\"");
            try expectRecordContains(gpa, &output.interface, "aborted:Native extension transport closed");
        } else try expectRecordContains(gpa, &output.interface, "NativeWorkerInputClosed");
        const status = try child.wait(io);
        reaped = true;
        try std.testing.expect(status == .exited and status.exited == 0);
    }
}

test "native worker protocol fixture skips only validated metadata and rejects other unexpected records" {
    const gpa = std.testing.allocator;
    const valid = "{\"type\":\"native_metadata\",\"version\":1,\"ownerGeneration\":\"42\",\"revision\":\"1\",\"extensions\":[]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, valid, .{});
    defer parsed.deinit();
    try std.testing.expect(try consumeMetadata(gpa, parsed.value));
    var invalid = try std.json.parseFromSlice(std.json.Value, gpa, "{\"type\":\"native_metadata\",\"version\":2}", .{});
    defer invalid.deinit();
    try std.testing.expectError(error.NativeFixtureInvalidMetadata, consumeMetadata(gpa, invalid.value));
    var unrelated = try std.json.parseFromSlice(std.json.Value, gpa, "{\"type\":\"native_owner_error\",\"error\":\"unexpected\"}", .{});
    defer unrelated.deinit();
    try std.testing.expect(!try consumeMetadata(gpa, unrelated.value));
}
