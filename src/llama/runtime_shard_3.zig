//! Generated local llama/runtime glue shard 3.
const std = @import("std");

pub const RuntimeKind = enum { ollama, lmstudio, vllm, llama_cpp, mlc, localai };

pub fn runtimeName(k: RuntimeKind) []const u8 {
    return switch (k) {
        .ollama => "ollama",
        .lmstudio => "lmstudio",
        .vllm => "vllm",
        .llama_cpp => "llama_cpp",
        .mlc => "mlc",
        .localai => "localai",
    };
}

pub fn local_model_3_0_id() []const u8 { return "local-3-0"; }
pub fn local_model_3_0_gguf() []const u8 { return "models/local-3-0.gguf"; }
pub fn local_model_3_0_ctx() u32 { return 2048; }
pub fn local_model_3_0_threads() u32 { return 1; }
pub fn local_model_3_0_gpu_layers() i32 { return 0; }
pub fn local_model_3_0_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_0_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_3_0_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_0_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_0(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_1_id() []const u8 { return "local-3-1"; }
pub fn local_model_3_1_gguf() []const u8 { return "models/local-3-1.gguf"; }
pub fn local_model_3_1_ctx() u32 { return 4096; }
pub fn local_model_3_1_threads() u32 { return 1; }
pub fn local_model_3_1_gpu_layers() i32 { return 1; }
pub fn local_model_3_1_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_1_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_3_1_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_1_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_1(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_2_id() []const u8 { return "local-3-2"; }
pub fn local_model_3_2_gguf() []const u8 { return "models/local-3-2.gguf"; }
pub fn local_model_3_2_ctx() u32 { return 6144; }
pub fn local_model_3_2_threads() u32 { return 2; }
pub fn local_model_3_2_gpu_layers() i32 { return 2; }
pub fn local_model_3_2_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_2_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_3_2_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_2_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_2(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_3_id() []const u8 { return "local-3-3"; }
pub fn local_model_3_3_gguf() []const u8 { return "models/local-3-3.gguf"; }
pub fn local_model_3_3_ctx() u32 { return 8192; }
pub fn local_model_3_3_threads() u32 { return 3; }
pub fn local_model_3_3_gpu_layers() i32 { return 3; }
pub fn local_model_3_3_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_3_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_3_3_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_3_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_3(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_4_id() []const u8 { return "local-3-4"; }
pub fn local_model_3_4_gguf() []const u8 { return "models/local-3-4.gguf"; }
pub fn local_model_3_4_ctx() u32 { return 10240; }
pub fn local_model_3_4_threads() u32 { return 4; }
pub fn local_model_3_4_gpu_layers() i32 { return 4; }
pub fn local_model_3_4_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_4_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_3_4_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_4_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_4(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_5_id() []const u8 { return "local-3-5"; }
pub fn local_model_3_5_gguf() []const u8 { return "models/local-3-5.gguf"; }
pub fn local_model_3_5_ctx() u32 { return 12288; }
pub fn local_model_3_5_threads() u32 { return 5; }
pub fn local_model_3_5_gpu_layers() i32 { return 5; }
pub fn local_model_3_5_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_5_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_3_5_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_5_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_5(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_6_id() []const u8 { return "local-3-6"; }
pub fn local_model_3_6_gguf() []const u8 { return "models/local-3-6.gguf"; }
pub fn local_model_3_6_ctx() u32 { return 14336; }
pub fn local_model_3_6_threads() u32 { return 6; }
pub fn local_model_3_6_gpu_layers() i32 { return 6; }
pub fn local_model_3_6_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_6_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_3_6_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_6_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_6(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_7_id() []const u8 { return "local-3-7"; }
pub fn local_model_3_7_gguf() []const u8 { return "models/local-3-7.gguf"; }
pub fn local_model_3_7_ctx() u32 { return 16384; }
pub fn local_model_3_7_threads() u32 { return 7; }
pub fn local_model_3_7_gpu_layers() i32 { return 7; }
pub fn local_model_3_7_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_7_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_3_7_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_7_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_7(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_8_id() []const u8 { return "local-3-8"; }
pub fn local_model_3_8_gguf() []const u8 { return "models/local-3-8.gguf"; }
pub fn local_model_3_8_ctx() u32 { return 18432; }
pub fn local_model_3_8_threads() u32 { return 8; }
pub fn local_model_3_8_gpu_layers() i32 { return 8; }
pub fn local_model_3_8_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_8_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_3_8_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_8_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_8(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_9_id() []const u8 { return "local-3-9"; }
pub fn local_model_3_9_gguf() []const u8 { return "models/local-3-9.gguf"; }
pub fn local_model_3_9_ctx() u32 { return 20480; }
pub fn local_model_3_9_threads() u32 { return 9; }
pub fn local_model_3_9_gpu_layers() i32 { return 9; }
pub fn local_model_3_9_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_9_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_3_9_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_9_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_9(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_10_id() []const u8 { return "local-3-10"; }
pub fn local_model_3_10_gguf() []const u8 { return "models/local-3-10.gguf"; }
pub fn local_model_3_10_ctx() u32 { return 22528; }
pub fn local_model_3_10_threads() u32 { return 10; }
pub fn local_model_3_10_gpu_layers() i32 { return 10; }
pub fn local_model_3_10_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_10_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_3_10_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_10_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_10(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_11_id() []const u8 { return "local-3-11"; }
pub fn local_model_3_11_gguf() []const u8 { return "models/local-3-11.gguf"; }
pub fn local_model_3_11_ctx() u32 { return 24576; }
pub fn local_model_3_11_threads() u32 { return 11; }
pub fn local_model_3_11_gpu_layers() i32 { return 11; }
pub fn local_model_3_11_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_11_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_3_11_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_11_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_11(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_12_id() []const u8 { return "local-3-12"; }
pub fn local_model_3_12_gguf() []const u8 { return "models/local-3-12.gguf"; }
pub fn local_model_3_12_ctx() u32 { return 26624; }
pub fn local_model_3_12_threads() u32 { return 12; }
pub fn local_model_3_12_gpu_layers() i32 { return 12; }
pub fn local_model_3_12_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_12_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_3_12_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_12_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_12(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_13_id() []const u8 { return "local-3-13"; }
pub fn local_model_3_13_gguf() []const u8 { return "models/local-3-13.gguf"; }
pub fn local_model_3_13_ctx() u32 { return 28672; }
pub fn local_model_3_13_threads() u32 { return 13; }
pub fn local_model_3_13_gpu_layers() i32 { return 13; }
pub fn local_model_3_13_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_13_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_3_13_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_13_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_13(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_14_id() []const u8 { return "local-3-14"; }
pub fn local_model_3_14_gguf() []const u8 { return "models/local-3-14.gguf"; }
pub fn local_model_3_14_ctx() u32 { return 30720; }
pub fn local_model_3_14_threads() u32 { return 14; }
pub fn local_model_3_14_gpu_layers() i32 { return 14; }
pub fn local_model_3_14_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_14_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_3_14_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_14_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_14(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_15_id() []const u8 { return "local-3-15"; }
pub fn local_model_3_15_gguf() []const u8 { return "models/local-3-15.gguf"; }
pub fn local_model_3_15_ctx() u32 { return 32768; }
pub fn local_model_3_15_threads() u32 { return 15; }
pub fn local_model_3_15_gpu_layers() i32 { return 15; }
pub fn local_model_3_15_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_15_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_3_15_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_15_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_15(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_16_id() []const u8 { return "local-3-16"; }
pub fn local_model_3_16_gguf() []const u8 { return "models/local-3-16.gguf"; }
pub fn local_model_3_16_ctx() u32 { return 2048; }
pub fn local_model_3_16_threads() u32 { return 1; }
pub fn local_model_3_16_gpu_layers() i32 { return 16; }
pub fn local_model_3_16_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_16_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_3_16_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_16_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_16(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_17_id() []const u8 { return "local-3-17"; }
pub fn local_model_3_17_gguf() []const u8 { return "models/local-3-17.gguf"; }
pub fn local_model_3_17_ctx() u32 { return 4096; }
pub fn local_model_3_17_threads() u32 { return 1; }
pub fn local_model_3_17_gpu_layers() i32 { return 17; }
pub fn local_model_3_17_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_17_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_3_17_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_17_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_17(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_18_id() []const u8 { return "local-3-18"; }
pub fn local_model_3_18_gguf() []const u8 { return "models/local-3-18.gguf"; }
pub fn local_model_3_18_ctx() u32 { return 6144; }
pub fn local_model_3_18_threads() u32 { return 2; }
pub fn local_model_3_18_gpu_layers() i32 { return 18; }
pub fn local_model_3_18_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_18_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_3_18_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_18_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_18(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_19_id() []const u8 { return "local-3-19"; }
pub fn local_model_3_19_gguf() []const u8 { return "models/local-3-19.gguf"; }
pub fn local_model_3_19_ctx() u32 { return 8192; }
pub fn local_model_3_19_threads() u32 { return 3; }
pub fn local_model_3_19_gpu_layers() i32 { return 19; }
pub fn local_model_3_19_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_19_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_3_19_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_19_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_19(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_20_id() []const u8 { return "local-3-20"; }
pub fn local_model_3_20_gguf() []const u8 { return "models/local-3-20.gguf"; }
pub fn local_model_3_20_ctx() u32 { return 10240; }
pub fn local_model_3_20_threads() u32 { return 4; }
pub fn local_model_3_20_gpu_layers() i32 { return 20; }
pub fn local_model_3_20_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_20_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_3_20_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_20_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_20(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_21_id() []const u8 { return "local-3-21"; }
pub fn local_model_3_21_gguf() []const u8 { return "models/local-3-21.gguf"; }
pub fn local_model_3_21_ctx() u32 { return 12288; }
pub fn local_model_3_21_threads() u32 { return 5; }
pub fn local_model_3_21_gpu_layers() i32 { return 21; }
pub fn local_model_3_21_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_21_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_3_21_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_21_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_21(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_22_id() []const u8 { return "local-3-22"; }
pub fn local_model_3_22_gguf() []const u8 { return "models/local-3-22.gguf"; }
pub fn local_model_3_22_ctx() u32 { return 14336; }
pub fn local_model_3_22_threads() u32 { return 6; }
pub fn local_model_3_22_gpu_layers() i32 { return 22; }
pub fn local_model_3_22_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_22_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_3_22_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_22_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_22(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_23_id() []const u8 { return "local-3-23"; }
pub fn local_model_3_23_gguf() []const u8 { return "models/local-3-23.gguf"; }
pub fn local_model_3_23_ctx() u32 { return 16384; }
pub fn local_model_3_23_threads() u32 { return 7; }
pub fn local_model_3_23_gpu_layers() i32 { return 23; }
pub fn local_model_3_23_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_23_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_3_23_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_23_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_23(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_24_id() []const u8 { return "local-3-24"; }
pub fn local_model_3_24_gguf() []const u8 { return "models/local-3-24.gguf"; }
pub fn local_model_3_24_ctx() u32 { return 18432; }
pub fn local_model_3_24_threads() u32 { return 8; }
pub fn local_model_3_24_gpu_layers() i32 { return 24; }
pub fn local_model_3_24_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_24_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_3_24_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_24_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_24(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_25_id() []const u8 { return "local-3-25"; }
pub fn local_model_3_25_gguf() []const u8 { return "models/local-3-25.gguf"; }
pub fn local_model_3_25_ctx() u32 { return 20480; }
pub fn local_model_3_25_threads() u32 { return 9; }
pub fn local_model_3_25_gpu_layers() i32 { return 25; }
pub fn local_model_3_25_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_25_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_3_25_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_25_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_25(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_26_id() []const u8 { return "local-3-26"; }
pub fn local_model_3_26_gguf() []const u8 { return "models/local-3-26.gguf"; }
pub fn local_model_3_26_ctx() u32 { return 22528; }
pub fn local_model_3_26_threads() u32 { return 10; }
pub fn local_model_3_26_gpu_layers() i32 { return 26; }
pub fn local_model_3_26_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_26_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_3_26_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_26_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_26(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_27_id() []const u8 { return "local-3-27"; }
pub fn local_model_3_27_gguf() []const u8 { return "models/local-3-27.gguf"; }
pub fn local_model_3_27_ctx() u32 { return 24576; }
pub fn local_model_3_27_threads() u32 { return 11; }
pub fn local_model_3_27_gpu_layers() i32 { return 27; }
pub fn local_model_3_27_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_27_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_3_27_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_27_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_27(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_28_id() []const u8 { return "local-3-28"; }
pub fn local_model_3_28_gguf() []const u8 { return "models/local-3-28.gguf"; }
pub fn local_model_3_28_ctx() u32 { return 26624; }
pub fn local_model_3_28_threads() u32 { return 12; }
pub fn local_model_3_28_gpu_layers() i32 { return 28; }
pub fn local_model_3_28_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_28_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_3_28_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_28_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_28(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_29_id() []const u8 { return "local-3-29"; }
pub fn local_model_3_29_gguf() []const u8 { return "models/local-3-29.gguf"; }
pub fn local_model_3_29_ctx() u32 { return 28672; }
pub fn local_model_3_29_threads() u32 { return 13; }
pub fn local_model_3_29_gpu_layers() i32 { return 29; }
pub fn local_model_3_29_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_29_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_3_29_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_29_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_29(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_30_id() []const u8 { return "local-3-30"; }
pub fn local_model_3_30_gguf() []const u8 { return "models/local-3-30.gguf"; }
pub fn local_model_3_30_ctx() u32 { return 30720; }
pub fn local_model_3_30_threads() u32 { return 14; }
pub fn local_model_3_30_gpu_layers() i32 { return 30; }
pub fn local_model_3_30_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_30_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_3_30_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_30_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_30(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_31_id() []const u8 { return "local-3-31"; }
pub fn local_model_3_31_gguf() []const u8 { return "models/local-3-31.gguf"; }
pub fn local_model_3_31_ctx() u32 { return 32768; }
pub fn local_model_3_31_threads() u32 { return 15; }
pub fn local_model_3_31_gpu_layers() i32 { return 31; }
pub fn local_model_3_31_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_31_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_3_31_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_31_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_31(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_32_id() []const u8 { return "local-3-32"; }
pub fn local_model_3_32_gguf() []const u8 { return "models/local-3-32.gguf"; }
pub fn local_model_3_32_ctx() u32 { return 2048; }
pub fn local_model_3_32_threads() u32 { return 1; }
pub fn local_model_3_32_gpu_layers() i32 { return 32; }
pub fn local_model_3_32_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_32_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_3_32_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_32_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_32(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_33_id() []const u8 { return "local-3-33"; }
pub fn local_model_3_33_gguf() []const u8 { return "models/local-3-33.gguf"; }
pub fn local_model_3_33_ctx() u32 { return 4096; }
pub fn local_model_3_33_threads() u32 { return 1; }
pub fn local_model_3_33_gpu_layers() i32 { return 33; }
pub fn local_model_3_33_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_33_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_3_33_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_33_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_33(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_34_id() []const u8 { return "local-3-34"; }
pub fn local_model_3_34_gguf() []const u8 { return "models/local-3-34.gguf"; }
pub fn local_model_3_34_ctx() u32 { return 6144; }
pub fn local_model_3_34_threads() u32 { return 2; }
pub fn local_model_3_34_gpu_layers() i32 { return 34; }
pub fn local_model_3_34_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_34_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_3_34_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_34_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_34(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_35_id() []const u8 { return "local-3-35"; }
pub fn local_model_3_35_gguf() []const u8 { return "models/local-3-35.gguf"; }
pub fn local_model_3_35_ctx() u32 { return 8192; }
pub fn local_model_3_35_threads() u32 { return 3; }
pub fn local_model_3_35_gpu_layers() i32 { return 35; }
pub fn local_model_3_35_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_35_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_3_35_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_35_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_35(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_36_id() []const u8 { return "local-3-36"; }
pub fn local_model_3_36_gguf() []const u8 { return "models/local-3-36.gguf"; }
pub fn local_model_3_36_ctx() u32 { return 10240; }
pub fn local_model_3_36_threads() u32 { return 4; }
pub fn local_model_3_36_gpu_layers() i32 { return 36; }
pub fn local_model_3_36_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_36_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_3_36_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_36_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_36(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_37_id() []const u8 { return "local-3-37"; }
pub fn local_model_3_37_gguf() []const u8 { return "models/local-3-37.gguf"; }
pub fn local_model_3_37_ctx() u32 { return 12288; }
pub fn local_model_3_37_threads() u32 { return 5; }
pub fn local_model_3_37_gpu_layers() i32 { return 37; }
pub fn local_model_3_37_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_37_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_3_37_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_37_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_37(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_38_id() []const u8 { return "local-3-38"; }
pub fn local_model_3_38_gguf() []const u8 { return "models/local-3-38.gguf"; }
pub fn local_model_3_38_ctx() u32 { return 14336; }
pub fn local_model_3_38_threads() u32 { return 6; }
pub fn local_model_3_38_gpu_layers() i32 { return 38; }
pub fn local_model_3_38_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_38_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_3_38_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_38_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_38(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_3_39_id() []const u8 { return "local-3-39"; }
pub fn local_model_3_39_gguf() []const u8 { return "models/local-3-39.gguf"; }
pub fn local_model_3_39_ctx() u32 { return 16384; }
pub fn local_model_3_39_threads() u32 { return 7; }
pub fn local_model_3_39_gpu_layers() i32 { return 39; }
pub fn local_model_3_39_chat_template() []const u8 { return "chatml"; }
pub fn local_model_3_39_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_3_39_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_3_39_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_3_39(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

test "llama shard 3" {
    try std.testing.expectEqualStrings("ollama", runtimeName(.ollama));
    try std.testing.expectEqualStrings("local-3-0", local_model_3_0_id());
    const gpa = std.testing.allocator;
    const argv = try local_model_3_0_argv(gpa);
    defer free_argv_3_0(gpa, argv);
    try std.testing.expect(argv.len == 3);
}

