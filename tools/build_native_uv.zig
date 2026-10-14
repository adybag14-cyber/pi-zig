//! Complete libuv C library from the exact Node24.14.0 deps/uv subtree.
//! One C translation unit per build step keeps -j1 effective for peak memory.
const std = @import("std");
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const library = b.addLibrary(.{ .name = "pi-native-uv", .linkage = .static, .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }) });
    const common = [_][]const u8{ "src/fs-poll.c", "src/idna.c", "src/inet.c", "src/random.c", "src/strscpy.c", "src/strtok.c", "src/thread-common.c", "src/threadpool.c", "src/timer.c", "src/uv-common.c", "src/uv-data-getter-setters.c", "src/version.c" };
    const windows = [_][]const u8{ "src/win/async.c", "src/win/core.c", "src/win/detect-wakeup.c", "src/win/dl.c", "src/win/error.c", "src/win/fs.c", "src/win/fs-event.c", "src/win/getaddrinfo.c", "src/win/getnameinfo.c", "src/win/handle.c", "src/win/loop-watcher.c", "src/win/pipe.c", "src/win/thread.c", "src/win/poll.c", "src/win/process.c", "src/win/process-stdio.c", "src/win/signal.c", "src/win/snprintf.c", "src/win/stream.c", "src/win/tcp.c", "src/win/tty.c", "src/win/udp.c", "src/win/util.c", "src/win/winapi.c", "src/win/winsock.c" };
    const unix = [_][]const u8{ "src/unix/async.c", "src/unix/core.c", "src/unix/dl.c", "src/unix/fs.c", "src/unix/getaddrinfo.c", "src/unix/getnameinfo.c", "src/unix/loop-watcher.c", "src/unix/loop.c", "src/unix/pipe.c", "src/unix/poll.c", "src/unix/process.c", "src/unix/random-devurandom.c", "src/unix/signal.c", "src/unix/stream.c", "src/unix/tcp.c", "src/unix/thread.c", "src/unix/tty.c", "src/unix/udp.c" };
    const linux = [_][]const u8{ "src/unix/proctitle.c", "src/unix/linux.c", "src/unix/procfs-exepath.c", "src/unix/random-getrandom.c", "src/unix/random-sysctl-linux.c" };
    const macos = [_][]const u8{ "src/unix/proctitle.c", "src/unix/bsd-ifaddrs.c", "src/unix/kqueue.c", "src/unix/random-getentropy.c", "src/unix/darwin-proctitle.c", "src/unix/darwin.c", "src/unix/fsevents.c" };
    const flags = if (target.result.os.tag == .windows) &[_][]const u8{ "-std=gnu11", "-DWIN32_LEAN_AND_MEAN", "-D_WIN32_WINNT=0x0A00", "-D_CRT_DECLARE_NONSTDC_NAMES=0", "-fno-strict-aliasing" } else if (target.result.os.tag == .macos) &[_][]const u8{ "-std=gnu11", "-D_FILE_OFFSET_BITS=64", "-D_LARGEFILE_SOURCE", "-D_DARWIN_UNLIMITED_SELECT=1", "-D_DARWIN_USE_64_BIT_INODE=1", "-fno-strict-aliasing" } else &[_][]const u8{ "-std=gnu11", "-D_FILE_OFFSET_BITS=64", "-D_LARGEFILE_SOURCE", "-D_GNU_SOURCE", "-D_POSIX_C_SOURCE=200112", "-fno-strict-aliasing" };
    for (common, 0..) |file, index| addObject(b, library, target, optimize, file, index, flags);
    const platform: []const []const u8 = if (target.result.os.tag == .windows) &windows else &unix;
    for (platform, 0..) |file, index| addObject(b, library, target, optimize, file, common.len + index, flags);
    const extra: []const []const u8 = switch (target.result.os.tag) {
        .windows => &.{},
        .linux => &linux,
        .macos => &macos,
        else => @panic("Native libuv build requires a qualified supported platform source set"),
    };
    for (extra, 0..) |file, index| addObject(b, library, target, optimize, file, common.len + platform.len + index, flags);
    if (target.result.os.tag == .windows) {
        for ([_][]const u8{ "psapi", "user32", "advapi32", "iphlpapi", "userenv", "ws2_32", "dbghelp", "ole32", "shell32" }) |name| library.root_module.linkSystemLibrary(name, .{});
    } else {
        library.root_module.linkSystemLibrary("pthread", .{});
        if (target.result.os.tag == .linux) {
            library.root_module.linkSystemLibrary("dl", .{});
            library.root_module.linkSystemLibrary("rt", .{});
        }
    }
    const api = b.addModule("native_uv_api", .{ .root_source_file = b.path("src/extensions/native_uv_api.zig"), .target = target, .optimize = optimize, .link_libc = true });
    api.addIncludePath(b.path("vendor/libuv/include"));
    api.linkLibrary(library);
    return api;
}
fn addObject(b: *std.Build, library: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, file: []const u8, index: usize, flags: []const []const u8) void {
    const object = b.addObject(.{ .name = b.fmt("pi-uv-{d}", .{index}), .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }) });
    object.root_module.addIncludePath(b.path("vendor/libuv/include"));
    object.root_module.addIncludePath(b.path("vendor/libuv/src"));
    object.root_module.addCSourceFile(.{ .file = b.path(b.fmt("vendor/libuv/{s}", .{file})), .flags = flags });
    library.root_module.addObject(object);
}
