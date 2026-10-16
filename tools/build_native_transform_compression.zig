//! Link only the selected upstream direct-C streaming codec bodies.
const std = @import("std");
pub fn link(b: *std.Build, module: *std.Build.Module) void {
    module.addIncludePath(b.path("vendor/native-zlib-1.3.1"));
    module.addCSourceFiles(.{
        .files = &.{ "vendor/native-zlib-1.3.1/adler32.c", "vendor/native-zlib-1.3.1/crc32.c", "vendor/native-zlib-1.3.1/deflate.c", "vendor/native-zlib-1.3.1/trees.c", "vendor/native-zlib-1.3.1/inflate.c", "vendor/native-zlib-1.3.1/inftrees.c", "vendor/native-zlib-1.3.1/inffast.c", "vendor/native-zlib-1.3.1/zutil.c" },
        .flags = &.{ "-std=c99", "-DZ_PREFIX=1", "-DZ_SOLO=1" },
    });
    module.link_libc = true;
}
