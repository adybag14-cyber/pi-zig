//! Build unchanged Node v24.13.0 libuv/llhttp and shared TCP/file I/O owners.
//! SOURCE-MANIFEST.json pins every imported byte. No source generator is run.
const std = @import("std");
const uv_root = "vendor/node-v24.13.0/uv";
const llhttp_root = "vendor/node-v24.13.0/llhttp";

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode,
    native_memory: ?*std.Build.Step.Compile) *std.Build.Step.Compile {
    const library = b.addLibrary(.{
        .name = "pi-node-network",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = native_memory != null }),
    });
    const module = library.root_module;
    module.addIncludePath(b.path(uv_root ++ "/include"));
    module.addIncludePath(b.path(uv_root ++ "/src"));
    module.addIncludePath(b.path(llhttp_root ++ "/include"));
    module.addIncludePath(b.path("src/extensions"));
    module.addIncludePath(b.path("vendor/quickjs"));
    const flags: []const []const u8 = switch (target.result.os.tag) {
        .windows => &.{ "-std=gnu11", "-D_WIN32_WINNT=0x0602", "-D_GNU_SOURCE", "-fno-strict-aliasing" },
        .linux => &.{ "-std=gnu11", "-D_GNU_SOURCE", "-D_LARGEFILE_SOURCE", "-D_FILE_OFFSET_BITS=64", "-fno-strict-aliasing" },
        else => std.debug.panic("The real Node TCP backend has no admitted source set for {s}", .{@tagName(target.result.os.tag)}),
    };
    module.addCSourceFiles(.{ .root = b.path(uv_root), .files = &common_sources, .flags = flags });
    switch (target.result.os.tag) {
        .windows => {
            module.addCSourceFiles(.{ .root = b.path(uv_root), .files = &windows_sources, .flags = flags });
            inline for (.{ "advapi32", "dbghelp", "ole32", "iphlpapi", "psapi", "shell32", "user32", "userenv", "uuid", "ws2_32" }) |name|
                module.linkSystemLibrary(name, .{});
        },
        .linux => {
            module.addCSourceFiles(.{ .root = b.path(uv_root), .files = &unix_sources, .flags = flags });
            module.addCSourceFiles(.{ .root = b.path(uv_root), .files = &linux_sources, .flags = flags });
            inline for (.{ "pthread", "m", "dl", "rt" }) |name| module.linkSystemLibrary(name, .{});
        },
        else => unreachable,
    }
    module.addCSourceFiles(.{
        .root = b.path(llhttp_root),
        .files = &.{ "src/llhttp.c", "src/api.c", "src/http.c" },
        .flags = &.{"-std=gnu11"},
    });
    module.addCSourceFile(.{ .file = b.path("src/extensions/native_uv_tcp.c"), .flags = flags });
    module.addCSourceFile(.{ .file = b.path("src/extensions/native_uv_file_handle.c"), .flags = flags });
    module.addCSourceFile(.{ .file = b.path("src/extensions/native_uv_fs_write.c"), .flags = flags });
    module.addCSourceFile(.{ .file = b.path("src/extensions/native_node_options_environment.c"), .flags = flags });
    module.addCSourceFile(.{ .file = b.path("src/extensions/native_node_check_failure.c"), .flags = flags });
    if (native_memory) |memory| {
        module.linkLibrary(memory);
        module.addCSourceFile(.{
            .file = b.path("src/extensions/native_node_environment_map.cpp"),
            .flags = &.{ "-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing" },
        });
        module.addCSourceFile(.{
            .file = b.path("src/extensions/native_node_managed_buffers.cpp"),
            .flags = &.{ "-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing" },
        });
        module.addCSourceFile(.{
            .file = b.path("src/extensions/native_node_environment_paths.cpp"),
            .flags = &.{ "-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing" },
        });
    }
    return library;
}

// Exact C source membership of deps/uv/uv.gyp for Windows/Linux. Header-only
// entries remain vendored and included normally; no unrelated platform body is
// compiled as a substitute for the selected target.
const common_sources = [_][]const u8{
    "src/fs-poll.c", "src/idna.c", "src/inet.c", "src/random.c",
    "src/strscpy.c", "src/strtok.c", "src/thread-common.c", "src/threadpool.c",
    "src/timer.c", "src/uv-data-getter-setters.c", "src/uv-common.c", "src/version.c",
};
const windows_sources = [_][]const u8{
    "src/win/async.c", "src/win/core.c", "src/win/detect-wakeup.c", "src/win/dl.c",
    "src/win/error.c", "src/win/fs.c", "src/win/fs-event.c", "src/win/getaddrinfo.c",
    "src/win/getnameinfo.c", "src/win/handle.c", "src/win/loop-watcher.c", "src/win/pipe.c",
    "src/win/thread.c", "src/win/poll.c", "src/win/process.c", "src/win/process-stdio.c",
    "src/win/signal.c", "src/win/snprintf.c", "src/win/stream.c", "src/win/tcp.c",
    "src/win/tty.c", "src/win/udp.c", "src/win/util.c", "src/win/winapi.c", "src/win/winsock.c",
};
const unix_sources = [_][]const u8{
    "src/unix/async.c", "src/unix/core.c", "src/unix/dl.c", "src/unix/fs.c",
    "src/unix/getaddrinfo.c", "src/unix/getnameinfo.c", "src/unix/loop.c",
    "src/unix/loop-watcher.c", "src/unix/pipe.c", "src/unix/poll.c",
    "src/unix/process.c", "src/unix/random-devurandom.c", "src/unix/signal.c",
    "src/unix/stream.c", "src/unix/tcp.c", "src/unix/thread.c", "src/unix/tty.c", "src/unix/udp.c",
};
const linux_sources = [_][]const u8{
    "src/unix/linux.c", "src/unix/procfs-exepath.c", "src/unix/random-getrandom.c",
    "src/unix/random-sysctl-linux.c", "src/unix/proctitle.c",
};
