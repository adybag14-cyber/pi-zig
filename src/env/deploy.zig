//! Verified, atomic pi-env deployment commands generated natively in Zig.
const std = @import("std");
const ssh = @import("ssh.zig");
pub const Plan = struct {
    gpa: std.mem.Allocator,
    path: []u8,
    sha256: [64]u8,
    check_command: []u8,
    upload_command: []u8,
    start_program: []u8,
    upload_input: []u8,
    pub fn deinit(self: *Plan) void {
        self.gpa.free(self.path);
        self.gpa.free(self.check_command);
        self.gpa.free(self.upload_command);
        self.gpa.free(self.start_program);
        self.gpa.free(self.upload_input);
    }
};
pub fn powershell(gpa: std.mem.Allocator, script: []const u8) ![]u8 {
    const utf16 = try std.unicode.utf8ToUtf16LeAlloc(gpa, script);
    defer gpa.free(utf16);
    const bytes = std.mem.sliceAsBytes(utf16);
    const codec = std.base64.standard.Encoder;
    const encoded = try gpa.alloc(u8, codec.calcSize(bytes.len));
    defer gpa.free(encoded);
    _ = codec.encode(encoded, bytes);
    return std.fmt.allocPrint(gpa, "powershell -NoProfile -NonInteractive -EncodedCommand {s}", .{encoded});
}
fn quotePowerShell(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidDeploymentPath;
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(gpa);
    try bytes.append(gpa, '\'');
    for (text) |byte| try bytes.appendSlice(gpa, if (byte == '\'') "''" else &.{byte});
    try bytes.append(gpa, '\'');
    return bytes.toOwnedSlice(gpa);
}
const hash_function = "hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum \"$1\" | cut -d' ' -f1; elif command -v shasum >/dev/null 2>&1; then shasum -a 256 \"$1\" | cut -d' ' -f1; elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 \"$1\" | sed 's/.*= //'; else echo none; fi; }";
fn shell(gpa: std.mem.Allocator, script: []const u8) ![]u8 {
    const quoted = try ssh.quotePosix(gpa, script);
    defer gpa.free(quoted);
    return std.fmt.allocPrint(gpa, "sh -c {s}", .{quoted});
}
pub fn prepare(gpa: std.mem.Allocator, remote: ssh.Remote, binary: []const u8) !Plan {
    if (remote.home.len == 0 or std.mem.indexOfScalar(u8, remote.home, 0) != null) return error.InvalidDeploymentPath;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(binary, &digest, .{});
    const sha = std.fmt.bytesToHex(digest, .lower);
    const path = if (remote.platform == .windows)
        try std.fmt.allocPrint(gpa, "{s}\\.pi\\mobile\\tools\\pi-env-{s}.exe", .{ remote.home, sha[0..32] })
    else
        try std.fmt.allocPrint(gpa, "{s}/.pi/mobile/tools/pi-env-{s}", .{ remote.home, sha[0..32] });
    errdefer gpa.free(path);
    const literal = try (if (remote.platform == .windows) quotePowerShell(gpa, path) else ssh.quotePosix(gpa, path));
    defer gpa.free(literal);
    const check_script = if (remote.platform == .windows)
        try std.fmt.allocPrint(gpa, "$f = {s}; if ((Test-Path -LiteralPath $f) -and ((Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower() -eq '{s}')) {{ 'present' }} else {{ 'missing' }}", .{ literal, sha })
    else
        try std.fmt.allocPrint(gpa, "{s}; f={s}; if [ -f \"$f\" ] && [ \"$(hash \"$f\")\" = {s} ]; then echo present; elif [ \"$(hash /dev/null)\" = none ]; then echo nohash; else echo missing; fi", .{ hash_function, literal, sha });
    defer gpa.free(check_script);
    const check_command = try (if (remote.platform == .windows) powershell(gpa, check_script) else shell(gpa, check_script));
    errdefer gpa.free(check_command);
    const upload_script = if (remote.platform == .windows)
        try std.fmt.allocPrint(gpa, "$ErrorActionPreference = 'Stop'; $f = {s}; $d = Split-Path -Parent $f; " ++
            "New-Item -ItemType Directory -Force -Path $d | Out-Null; " ++
            "$t = Join-Path $d ('.pi-env-' + [guid]::NewGuid().ToString() + '.tmp'); " ++
            "$text = New-Object System.Text.StringBuilder; " ++
            "foreach ($line in $input) {{ if ($line -eq 'PI-ENV-END') {{ break }}; [void]$text.Append($line) }}; " ++
            "$bytes = [Convert]::FromBase64String($text.ToString()); " ++
            "$out = [IO.File]::Open($t, 'CreateNew', 'Write', 'None'); try {{ $out.Write($bytes, 0, $bytes.Length) }} finally {{ $out.Close() }}; " ++
            "if ((Get-FileHash -Algorithm SHA256 -LiteralPath $t).Hash.ToLower() -ne '{s}') {{ Remove-Item -LiteralPath $t; throw 'pi-env upload is corrupt' }}; " ++
            "for ($i = 0; ; $i++) {{ try {{ Move-Item -Force -LiteralPath $t -Destination $f; break }} catch {{ if ($i -ge 20) {{ throw }}; Start-Sleep -Milliseconds 250 }} }}; " ++
            "Get-ChildItem -LiteralPath $d -Filter 'pi-env-*.exe' | Where-Object {{ $_.FullName -ne $f }} | ForEach-Object {{ Remove-Item -LiteralPath $_.FullName -ErrorAction SilentlyContinue }}; 'deployed'", .{ literal, sha })
    else
        try std.fmt.allocPrint(gpa, "set -e\n{s}\nf={s}\nd=$(dirname \"$f\")\nmkdir -p \"$d\"\nchmod 700 \"$d\"\n" ++
            "t=$(mktemp \"$d/.pi-env.XXXXXX\")\ntrap 'rm -f \"$t\"' EXIT HUP INT TERM\ncat > \"$t\"\n" ++
            "if [ \"$(hash \"$t\")\" != {s} ]; then echo \"pi-env upload is corrupt\" >&2; exit 1; fi\n" ++
            "chmod 700 \"$t\"\nmv -f \"$t\" \"$f\"\nfor old in \"$d\"/pi-env-*; do [ \"$old\" = \"$f\" ] || rm -f \"$old\"; done\necho deployed", .{ hash_function, literal, sha });
    defer gpa.free(upload_script);
    const upload_command = try (if (remote.platform == .windows) powershell(gpa, upload_script) else shell(gpa, upload_script));
    errdefer gpa.free(upload_command);
    const program = if (remote.platform == .windows) blk: {
        if (std.mem.indexOfAny(u8, path, "\"\r\n") != null) return error.InvalidWindowsProgramPath;
        break :blk if (std.mem.indexOfScalar(u8, path, ' ') != null) try std.fmt.allocPrint(gpa, "\"{s}\"", .{path}) else try gpa.dupe(u8, path);
    } else try ssh.quotePosix(gpa, path);
    errdefer gpa.free(program);
    const input = if (remote.platform == .windows) try windowsUploadInput(gpa, binary) else try gpa.dupe(u8, binary);
    return .{ .gpa = gpa, .path = path, .sha256 = sha, .check_command = check_command, .upload_command = upload_command, .start_program = program, .upload_input = input };
}
pub fn windowsUploadInput(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const base64 = try gpa.alloc(u8, encoder.calcSize(bytes.len));
    defer gpa.free(base64);
    _ = encoder.encode(base64, bytes);
    var lines: std.ArrayList(u8) = .empty;
    errdefer lines.deinit(gpa);
    var offset: usize = 0;
    while (offset < base64.len) {
        const size = @min(76, base64.len - offset);
        try lines.appendSlice(gpa, base64[offset..][0..size]);
        try lines.append(gpa, '\n');
        offset += size;
    }
    try lines.appendSlice(gpa, "PI-ENV-END\n");
    return lines.toOwnedSlice(gpa);
}
test "deployment hashes payload and verifies private atomic upload before execution" {
    var plan = try prepare(std.testing.allocator, .{ .platform = .linux, .arch = .x64, .home = "/home/o'neil" }, "abc");
    defer plan.deinit();
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &plan.sha256);
    try std.testing.expectEqualStrings("/home/o'neil/.pi/mobile/tools/pi-env-ba7816bf8f01cfea414140de5dae2223", plan.path);
    try std.testing.expect(std.mem.indexOf(u8, plan.upload_command, &plan.sha256) != null);
    try std.testing.expect(std.mem.indexOf(u8, plan.upload_command, "chmod 700") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan.upload_command, "mv -f") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan.check_command, "nohash") != null);
    try std.testing.expect(std.mem.startsWith(u8, plan.start_program, "'/home/o'\\''neil/"));
}
test "Windows deployment command uses UTF16 encoded PowerShell literal paths and verified replacement" {
    var plan = try prepare(std.testing.allocator, .{ .platform = .windows, .arch = .arm64, .home = "C:\\Users\\o'neil space🚀" }, "abc");
    defer plan.deinit();
    const prefix = "powershell -NoProfile -NonInteractive -EncodedCommand ";
    try std.testing.expect(std.mem.startsWith(u8, plan.upload_command, prefix));
    const decoder = std.base64.standard.Decoder;
    const encoded = plan.upload_command[prefix.len..];
    const bytes = try std.testing.allocator.alloc(u8, try decoder.calcSizeForSlice(encoded));
    defer std.testing.allocator.free(bytes);
    try decoder.decode(bytes, encoded);
    const aligned = try std.testing.allocator.alloc(u16, bytes.len / 2);
    defer std.testing.allocator.free(aligned);
    @memcpy(std.mem.sliceAsBytes(aligned), bytes);
    const text = try std.unicode.utf16LeToUtf8Alloc(std.testing.allocator, aligned);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "o''neil space🚀") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Get-FileHash -Algorithm SHA256 -LiteralPath $t") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Move-Item -Force -LiteralPath $t") != null);
    try std.testing.expect(plan.start_program[0] == '"');
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    for ([_]ssh.Platform{ .linux, .windows }) |platform| {
        var plan = try prepare(gpa, .{ .platform = platform, .arch = .x64, .home = "/owned/home space" }, "binary\x00\xff");
        defer plan.deinit();
    }
}
test "deployment allocation failures release paths scripts encoded commands and program" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
    try std.testing.expectError(error.InvalidDeploymentPath, prepare(std.testing.allocator, .{ .platform = .linux, .arch = .x64, .home = "bad\x00path" }, "x"));
}
extern "kernel32" fn GetSystemDirectoryW([*]u16, u32) callconv(.winapi) u32;
fn localWindowsPowerShell(gpa: std.mem.Allocator) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u16 = undefined;
    const length = GetSystemDirectoryW(&buffer, buffer.len);
    if (length == 0 or length >= buffer.len) return error.WindowsSystemDirectoryUnavailable;
    const directory = try std.unicode.wtf16LeToWtf8Alloc(gpa, buffer[0..length]);
    defer gpa.free(directory);
    return std.fs.path.join(gpa, &.{ directory, "WindowsPowerShell", "v1.0", "powershell.exe" });
}
fn executePlan(gpa: std.mem.Allocator, io: std.Io, command: []const u8, input: []const u8) !@import("ssh_process.zig").Result {
    const runner = @import("ssh_process.zig");
    if (@import("builtin").os.tag == .windows) {
        const prefix = "powershell -NoProfile -NonInteractive -EncodedCommand ";
        if (!std.mem.startsWith(u8, command, prefix)) return error.InvalidWindowsDeploymentCommand;
        var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
        defer environment.deinit();
        // A local PowerShell 7 host may inject its module path into this test.
        // Real SSH uses the remote environment, where Windows PowerShell builds
        // its own native module path. Preserve that boundary in this fixture.
        _ = environment.swapRemove("PSModulePath");
        const program = try localWindowsPowerShell(gpa);
        defer gpa.free(program);
        const timeout_ms = (runner.Options{}).timeout_ms;
        const began = std.Io.Clock.awake.now(io).toMilliseconds();
        return runner.runProgram(gpa, io, &.{ program, "-NoProfile", "-NonInteractive", "-EncodedCommand", command[prefix.len..] }, .{ .stdin = input, .timeout_ms = timeout_ms, .environ_map = &environment }) catch |err| {
            // This helper is a local test fixture. Preserve the actual error
            // and disclose neither encoded commands nor upload payloads.
            std.debug.print("Local deployment execution failure: error={s}, elapsed_ms={d}, engine={s}, deadline_ms={d}\n", .{ @errorName(err), std.Io.Clock.awake.now(io).toMilliseconds() - began, program, timeout_ms });
            return err;
        };
    }
    return runner.runProgram(gpa, io, &.{ "/bin/sh", "-c", command }, .{ .stdin = input, .timeout_ms = 10_000 });
}
test "actual platform deployment verifies reuses rejects corrupt input and repairs tampering inside owned home" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const name = "o'neil space🚀";
    try tmp.dir.createDir(io, name, .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = try tmp.dir.realPath(io, &buffer);
    const home = try std.fs.path.join(gpa, &.{ buffer[0..size], name });
    defer gpa.free(home);
    const payload = "native-verified-upload-🚀\x00\xff";
    var plan = try prepare(gpa, .{ .platform = if (@import("builtin").os.tag == .windows) .windows else .linux, .arch = .x64, .home = home }, payload);
    defer plan.deinit();
    var missing = try executePlan(gpa, io, plan.check_command, "");
    defer missing.deinit();
    try missing.check();
    try std.testing.expectEqualStrings("missing", std.mem.trim(u8, missing.stdout, "\r\n "));
    var upload_result = try executePlan(gpa, io, plan.upload_command, plan.upload_input);
    defer upload_result.deinit();
    if (upload_result.term != .exited or upload_result.term.exited != 0) std.debug.print("Deployment upload diagnostics: {s}\n", .{upload_result.stderr});
    try upload_result.check();
    try std.testing.expectEqualStrings("deployed", std.mem.trim(u8, upload_result.stdout, "\r\n "));
    var present = try executePlan(gpa, io, plan.check_command, "");
    defer present.deinit();
    try present.check();
    try std.testing.expectEqualStrings("present", std.mem.trim(u8, present.stdout, "\r\n "));
    const exact = try std.Io.Dir.cwd().readFileAlloc(io, plan.path, gpa, .limited(65536));
    defer gpa.free(exact);
    try std.testing.expectEqualSlices(u8, payload, exact);
    const deployed = try std.Io.Dir.cwd().openFile(io, plan.path, .{ .mode = .read_write });
    try deployed.writePositionalAll(io, "tamper", 0);
    deployed.close(io);
    var changed = try executePlan(gpa, io, plan.check_command, "");
    defer changed.deinit();
    try changed.check();
    try std.testing.expectEqualStrings("missing", std.mem.trim(u8, changed.stdout, "\r\n "));
    const corrupt_input = if (@import("builtin").os.tag == .windows) try windowsUploadInput(gpa, "corrupt") else try gpa.dupe(u8, "corrupt");
    defer gpa.free(corrupt_input);
    var corrupt = try executePlan(gpa, io, plan.upload_command, corrupt_input);
    defer corrupt.deinit();
    try std.testing.expectError(error.SshFailed, corrupt.check());
    const unchanged = try std.Io.Dir.cwd().readFileAlloc(io, plan.path, gpa, .limited(65536));
    defer gpa.free(unchanged);
    try std.testing.expect(std.mem.startsWith(u8, unchanged, "tamper"));
    var repaired = try executePlan(gpa, io, plan.upload_command, plan.upload_input);
    defer repaired.deinit();
    try repaired.check();
    const final_bytes = try std.Io.Dir.cwd().readFileAlloc(io, plan.path, gpa, .limited(65536));
    defer gpa.free(final_bytes);
    try std.testing.expectEqualSlices(u8, payload, final_bytes);
}
