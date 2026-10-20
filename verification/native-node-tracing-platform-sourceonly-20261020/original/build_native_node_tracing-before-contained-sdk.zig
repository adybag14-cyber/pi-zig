//! Concrete native tracing dependency composition, source-only until admitted.
//! The caller constructs each shared owner once. Nothing here installs process
//! hooks, starts tracing, executes a generator, runs a target, or changes Main.
const std = @import("std");
const abseil = @import("build_native_node_abseil.zig");

pub const Owners = struct {
    network: *std.Build.Step.Compile,
    native_memory: *std.Build.Step.Compile,
    diagnostic: *std.Build.Step.Compile,
    abseil: *std.Build.Step.Compile,
};

pub const Options = struct {
    // Genuine installed Windows SDK header. Only this file is copied to the
    // build include directory, so SDK shared headers do not shadow MinGW's
    // complete Windows header set. Its exact bytes are an integration input.
    windows_tracelogging_header: ?std.Build.LazyPath = null,
};

// This is the sole proposed production owner of the existing borrowed TLS
// context and the separately reviewed V8 fatal / clock diagnostic sources.
// An integrated diagnostic-context control must link this owner instead of
// compiling a second native_node_diagnostic_context.c translation unit.
pub fn addDiagnosticOwner(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    requireTarget(target);
    const library = b.addLibrary(.{
        .name = "pi-node-tracing-diagnostic",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target, .optimize = optimize,
            .link_libc = true, .link_libcpp = true,
        }),
    });
    const module = library.root_module;
    module.addIncludePath(b.path("src/extensions"));
    module.addCSourceFile(.{
        .file = b.path("src/extensions/native_node_diagnostic_context.c"),
        .flags = &.{"-std=gnu11"},
    });
    module.addCSourceFiles(.{
        .files = &.{
            "src/extensions/native_v8_base_fatal.cpp",
            "src/extensions/native_node_tracing_clock_diagnostics.cpp",
        },
        .flags = abseil.flags(target),
    });
    return library;
}

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, owners: Owners, options: Options) *std.Build.Step.Compile {
    requireTarget(target);
    const library = b.addLibrary(.{
        .name = "pi-node-tracing",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target, .optimize = optimize,
            .link_libc = true, .link_libcpp = true,
        }),
    });
    const module = library.root_module;
    module.addIncludePath(b.path("src/extensions"));
    module.addIncludePath(b.path("vendor/quickjs"));
    module.addIncludePath(b.path("vendor/node-v24.13.0/uv/include"));
    module.addIncludePath(b.path(abseil.root));
    module.linkLibrary(owners.network);
    module.linkLibrary(owners.native_memory);
    module.linkLibrary(owners.diagnostic);
    module.linkLibrary(owners.abseil);
    module.addCSourceFiles(.{
        .files = &sources,
        .flags = abseil.flags(target),
    });

    switch (target.result.os.tag) {
        .windows => {
            const sdk_header = options.windows_tracelogging_header orelse
                std.debug.panic("The original Windows Recorder requires an explicit genuine Windows SDK TraceLoggingProvider.h", .{});
            const sdk_copy = b.addWriteFiles();
            _ = sdk_copy.addCopyFile(sdk_header, "TraceLoggingProvider.h");
            module.addIncludePath(sdk_copy.getDirectory());
            module.addIncludePath(b.path("vendor/node-v24.13.0/v8-tracing"));
            module.addCSourceFiles(.{
                .files = &.{
                    "src/extensions/native_node_tracing_recorder.cpp",
                    "src/extensions/native_node_tracing_recorder_win.cpp",
                },
                .flags = &(abseil.base_flags ++ [_][]const u8{
                    "-D_WIN32_WINNT=0x0A00",
                    "-DV8_ENABLE_SYSTEM_INSTRUMENTATION",
                    "-fms-extensions",
                }),
            });
            // ETW registry / native handle symbols and the selected clock APIs.
            inline for (.{ "advapi32", "dbghelp", "winmm" }) |name|
                module.linkSystemLibrary(name, .{});
        },
        .linux => {
            inline for (.{ "pthread", "dl", "m", "rt" }) |name|
                module.linkSystemLibrary(name, .{});
        },
        .macos => {
            module.addCSourceFiles(.{
                .files = &.{
                    "src/extensions/native_node_tracing_recorder.cpp",
                    "src/extensions/native_node_tracing_recorder_mac.cpp",
                },
                .flags = &(abseil.base_flags ++ [_][]const u8{
                    "-DV8_ENABLE_SYSTEM_INSTRUMENTATION",
                }),
            });
        },
        else => unreachable,
    }
    return library;
}

fn requireTarget(target: std.Build.ResolvedTarget) void {
    if (target.result.ptrBitWidth() != 64)
        std.debug.panic("The admitted tracing native-memory owner requires a 64-bit target", .{});
    switch (target.result.os.tag) {
        .windows, .linux, .macos => {},
        else => std.debug.panic("No selected original tracing composition for {s}", .{@tagName(target.result.os.tag)}),
    }
}

// Main currently supplies real network and native-memory owners for Windows
// and Linux. Darwin Recorder/clock/Abseil source is retained, but a complete
// Darwin Agent composition still requires admitted Darwin versions of those
// actual owners. The caller must supply them; no substitute is provided here.
pub const sources = [_][]const u8{
    "src/extensions/native_node_tracing_core.cpp",
    "src/extensions/native_node_tracing_controller.cpp",
    "src/extensions/native_node_tracing_buffer.cpp",
    "src/extensions/native_node_tracing_writer.cpp",
    "src/extensions/native_node_tracing_agent.cpp",
    "src/extensions/native_node_tracing_clock.cpp",
    "src/extensions/native_node_tracing_api.cpp",
    "src/extensions/native_node_tracing_platform.cpp",
    "src/extensions/native_node_tracing_loop.cpp",
};
