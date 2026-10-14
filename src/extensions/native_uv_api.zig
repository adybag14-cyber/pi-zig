//! C ABI from Node24.14.0's exact pinned libuv1.51.0 subtree, with no Node runtime.
pub const c = @cImport({
    // The same Zig0.16 MinGW translate-c declaration bug is already guarded
    // in engine.zig. Compiled vendor C retains all normal safety flags.
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("uv.h");
});
