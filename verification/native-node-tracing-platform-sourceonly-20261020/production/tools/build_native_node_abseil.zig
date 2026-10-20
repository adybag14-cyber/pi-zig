//! Unchanged Abseil cohort from Node v24.13.0's original abseil.gyp.
//! SOURCE-MANIFEST.json pins every source/header byte. This recipe does not
//! force a waiter or thread-identity mode and does not run a source generator.
const std = @import("std");

pub const root = "vendor/node-v24.13.0/abseil-cpp";
pub const base_flags = [_][]const u8{
    "-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing",
};

pub fn flags(target: std.Build.ResolvedTarget) []const []const u8 {
    return switch (target.result.os.tag) {
        // Match the original Node/V8 toolchain's Windows 10 API selection.
        .windows => &(base_flags ++ [_][]const u8{"-D_WIN32_WINNT=0x0A00"}),
        .linux => &(base_flags ++ [_][]const u8{"-D_GNU_SOURCE"}),
        .macos => &base_flags,
        else => std.debug.panic("No selected original Abseil tracing composition for {s}", .{@tagName(target.result.os.tag)}),
    };
}

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const library = b.addLibrary(.{
        .name = "pi-node-abseil",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target, .optimize = optimize,
            .link_libc = true, .link_libcpp = true,
        }),
    });
    const module = library.root_module;
    module.addIncludePath(b.path(root));
    module.addCSourceFiles(.{
        .root = b.path(root),
        .files = &sources,
        .flags = flags(target),
    });
    switch (target.result.os.tag) {
        .windows => {
            module.linkSystemLibrary("advapi32", .{});
            module.linkSystemLibrary("dbghelp", .{});
            // Original MinGW ThreadIdentity uses pthread keys. Pinned Zig
            // classifies pthread as libc for MinGW; this reuses that owner.
            if (target.result.isMinGW()) module.linkSystemLibrary("pthread", .{});
        },
        .linux => {
            inline for (.{ "pthread", "m", "dl", "rt" }) |name|
                module.linkSystemLibrary(name, .{});
        },
        .macos => {
            module.linkFramework("CoreFoundation", .{});
        },
        else => unreachable,
    }
    return library;
}

// Exact 110 C++ compilation members of tools/v8_gypfiles/abseil.gyp.
// Platform guards in these original files choose their own implementations.
pub const sources = [_][]const u8{
    "absl/base/internal/cycleclock.cc",
    "absl/base/internal/low_level_alloc.cc",
    "absl/base/internal/poison.cc",
    "absl/base/internal/raw_logging.cc",
    "absl/base/internal/scoped_set_env.cc",
    "absl/base/internal/spinlock.cc",
    "absl/base/internal/spinlock_wait.cc",
    "absl/base/internal/strerror.cc",
    "absl/base/internal/sysinfo.cc",
    "absl/base/internal/thread_identity.cc",
    "absl/base/internal/throw_delegate.cc",
    "absl/base/internal/tracing.cc",
    "absl/base/internal/unscaledcycleclock.cc",
    "absl/base/log_severity.cc",
    "absl/container/internal/hashtablez_sampler.cc",
    "absl/container/internal/hashtablez_sampler_force_weak_definition.cc",
    "absl/container/internal/raw_hash_set.cc",
    "absl/crc/crc32c.cc",
    "absl/crc/internal/cpu_detect.cc",
    "absl/crc/internal/crc.cc",
    "absl/crc/internal/crc_cord_state.cc",
    "absl/crc/internal/crc_memcpy_fallback.cc",
    "absl/crc/internal/crc_memcpy_x86_arm_combined.cc",
    "absl/crc/internal/crc_non_temporal_memcpy.cc",
    "absl/crc/internal/crc_x86_arm_combined.cc",
    "absl/debugging/failure_signal_handler.cc",
    "absl/debugging/internal/address_is_readable.cc",
    "absl/debugging/internal/decode_rust_punycode.cc",
    "absl/debugging/internal/demangle.cc",
    "absl/debugging/internal/demangle_rust.cc",
    "absl/debugging/internal/elf_mem_image.cc",
    "absl/debugging/internal/examine_stack.cc",
    "absl/debugging/internal/stack_consumption.cc",
    "absl/debugging/internal/utf8_for_code_point.cc",
    "absl/debugging/internal/vdso_support.cc",
    "absl/debugging/leak_check.cc",
    "absl/debugging/stacktrace.cc",
    "absl/debugging/symbolize.cc",
    "absl/hash/internal/city.cc",
    "absl/hash/internal/hash.cc",
    "absl/hash/internal/low_level_hash.cc",
    "absl/numeric/int128.cc",
    "absl/profiling/internal/exponential_biased.cc",
    "absl/profiling/internal/periodic_sampler.cc",
    "absl/strings/ascii.cc",
    "absl/strings/charconv.cc",
    "absl/strings/cord.cc",
    "absl/strings/cord_analysis.cc",
    "absl/strings/escaping.cc",
    "absl/strings/internal/charconv_bigint.cc",
    "absl/strings/internal/charconv_parse.cc",
    "absl/strings/internal/cord_internal.cc",
    "absl/strings/internal/cord_rep_btree.cc",
    "absl/strings/internal/cord_rep_btree_navigator.cc",
    "absl/strings/internal/cord_rep_btree_reader.cc",
    "absl/strings/internal/cord_rep_consume.cc",
    "absl/strings/internal/cord_rep_crc.cc",
    "absl/strings/internal/cordz_functions.cc",
    "absl/strings/internal/cordz_handle.cc",
    "absl/strings/internal/cordz_info.cc",
    "absl/strings/internal/cordz_sample_token.cc",
    "absl/strings/internal/damerau_levenshtein_distance.cc",
    "absl/strings/internal/escaping.cc",
    "absl/strings/internal/memutil.cc",
    "absl/strings/internal/ostringstream.cc",
    "absl/strings/internal/pow10_helper.cc",
    "absl/strings/internal/str_format/arg.cc",
    "absl/strings/internal/str_format/bind.cc",
    "absl/strings/internal/str_format/extension.cc",
    "absl/strings/internal/str_format/float_conversion.cc",
    "absl/strings/internal/str_format/output.cc",
    "absl/strings/internal/str_format/parser.cc",
    "absl/strings/internal/stringify_sink.cc",
    "absl/strings/internal/utf8.cc",
    "absl/strings/match.cc",
    "absl/strings/numbers.cc",
    "absl/strings/str_cat.cc",
    "absl/strings/str_replace.cc",
    "absl/strings/str_split.cc",
    "absl/strings/string_view.cc",
    "absl/strings/substitute.cc",
    "absl/synchronization/barrier.cc",
    "absl/synchronization/blocking_counter.cc",
    "absl/synchronization/internal/create_thread_identity.cc",
    "absl/synchronization/internal/futex_waiter.cc",
    "absl/synchronization/internal/graphcycles.cc",
    "absl/synchronization/internal/kernel_timeout.cc",
    "absl/synchronization/internal/per_thread_sem.cc",
    "absl/synchronization/internal/pthread_waiter.cc",
    "absl/synchronization/internal/sem_waiter.cc",
    "absl/synchronization/internal/stdcpp_waiter.cc",
    "absl/synchronization/internal/waiter_base.cc",
    "absl/synchronization/internal/win32_waiter.cc",
    "absl/synchronization/mutex.cc",
    "absl/synchronization/notification.cc",
    "absl/time/civil_time.cc",
    "absl/time/clock.cc",
    "absl/time/duration.cc",
    "absl/time/format.cc",
    "absl/time/internal/cctz/src/civil_time_detail.cc",
    "absl/time/internal/cctz/src/time_zone_fixed.cc",
    "absl/time/internal/cctz/src/time_zone_format.cc",
    "absl/time/internal/cctz/src/time_zone_if.cc",
    "absl/time/internal/cctz/src/time_zone_impl.cc",
    "absl/time/internal/cctz/src/time_zone_info.cc",
    "absl/time/internal/cctz/src/time_zone_libc.cc",
    "absl/time/internal/cctz/src/time_zone_lookup.cc",
    "absl/time/internal/cctz/src/time_zone_posix.cc",
    "absl/time/internal/cctz/src/zone_info_source.cc",
    "absl/time/time.cc",
};
