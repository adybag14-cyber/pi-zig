//! Generated local llama/runtime glue shard 7.
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

pub fn local_model_7_0_id() []const u8 { return "local-7-0"; }
pub fn local_model_7_0_gguf() []const u8 { return "models/local-7-0.gguf"; }
pub fn local_model_7_0_ctx() u32 { return 2048; }
pub fn local_model_7_0_threads() u32 { return 1; }
pub fn local_model_7_0_gpu_layers() i32 { return 0; }
pub fn local_model_7_0_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_0_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_7_0_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_0_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_0(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_1_id() []const u8 { return "local-7-1"; }
pub fn local_model_7_1_gguf() []const u8 { return "models/local-7-1.gguf"; }
pub fn local_model_7_1_ctx() u32 { return 4096; }
pub fn local_model_7_1_threads() u32 { return 1; }
pub fn local_model_7_1_gpu_layers() i32 { return 1; }
pub fn local_model_7_1_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_1_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_7_1_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_1_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_1(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_2_id() []const u8 { return "local-7-2"; }
pub fn local_model_7_2_gguf() []const u8 { return "models/local-7-2.gguf"; }
pub fn local_model_7_2_ctx() u32 { return 6144; }
pub fn local_model_7_2_threads() u32 { return 2; }
pub fn local_model_7_2_gpu_layers() i32 { return 2; }
pub fn local_model_7_2_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_2_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_7_2_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_2_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_2(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_3_id() []const u8 { return "local-7-3"; }
pub fn local_model_7_3_gguf() []const u8 { return "models/local-7-3.gguf"; }
pub fn local_model_7_3_ctx() u32 { return 8192; }
pub fn local_model_7_3_threads() u32 { return 3; }
pub fn local_model_7_3_gpu_layers() i32 { return 3; }
pub fn local_model_7_3_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_3_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_7_3_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_3_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_3(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_4_id() []const u8 { return "local-7-4"; }
pub fn local_model_7_4_gguf() []const u8 { return "models/local-7-4.gguf"; }
pub fn local_model_7_4_ctx() u32 { return 10240; }
pub fn local_model_7_4_threads() u32 { return 4; }
pub fn local_model_7_4_gpu_layers() i32 { return 4; }
pub fn local_model_7_4_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_4_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_7_4_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_4_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_4(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_5_id() []const u8 { return "local-7-5"; }
pub fn local_model_7_5_gguf() []const u8 { return "models/local-7-5.gguf"; }
pub fn local_model_7_5_ctx() u32 { return 12288; }
pub fn local_model_7_5_threads() u32 { return 5; }
pub fn local_model_7_5_gpu_layers() i32 { return 5; }
pub fn local_model_7_5_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_5_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_7_5_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_5_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_5(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_6_id() []const u8 { return "local-7-6"; }
pub fn local_model_7_6_gguf() []const u8 { return "models/local-7-6.gguf"; }
pub fn local_model_7_6_ctx() u32 { return 14336; }
pub fn local_model_7_6_threads() u32 { return 6; }
pub fn local_model_7_6_gpu_layers() i32 { return 6; }
pub fn local_model_7_6_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_6_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_7_6_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_6_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_6(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_7_id() []const u8 { return "local-7-7"; }
pub fn local_model_7_7_gguf() []const u8 { return "models/local-7-7.gguf"; }
pub fn local_model_7_7_ctx() u32 { return 16384; }
pub fn local_model_7_7_threads() u32 { return 7; }
pub fn local_model_7_7_gpu_layers() i32 { return 7; }
pub fn local_model_7_7_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_7_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_7_7_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_7_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_7(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_8_id() []const u8 { return "local-7-8"; }
pub fn local_model_7_8_gguf() []const u8 { return "models/local-7-8.gguf"; }
pub fn local_model_7_8_ctx() u32 { return 18432; }
pub fn local_model_7_8_threads() u32 { return 8; }
pub fn local_model_7_8_gpu_layers() i32 { return 8; }
pub fn local_model_7_8_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_8_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_7_8_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_8_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_8(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_9_id() []const u8 { return "local-7-9"; }
pub fn local_model_7_9_gguf() []const u8 { return "models/local-7-9.gguf"; }
pub fn local_model_7_9_ctx() u32 { return 20480; }
pub fn local_model_7_9_threads() u32 { return 9; }
pub fn local_model_7_9_gpu_layers() i32 { return 9; }
pub fn local_model_7_9_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_9_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_7_9_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_9_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_9(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_10_id() []const u8 { return "local-7-10"; }
pub fn local_model_7_10_gguf() []const u8 { return "models/local-7-10.gguf"; }
pub fn local_model_7_10_ctx() u32 { return 22528; }
pub fn local_model_7_10_threads() u32 { return 10; }
pub fn local_model_7_10_gpu_layers() i32 { return 10; }
pub fn local_model_7_10_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_10_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_7_10_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_10_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_10(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_11_id() []const u8 { return "local-7-11"; }
pub fn local_model_7_11_gguf() []const u8 { return "models/local-7-11.gguf"; }
pub fn local_model_7_11_ctx() u32 { return 24576; }
pub fn local_model_7_11_threads() u32 { return 11; }
pub fn local_model_7_11_gpu_layers() i32 { return 11; }
pub fn local_model_7_11_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_11_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_7_11_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_11_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_11(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_12_id() []const u8 { return "local-7-12"; }
pub fn local_model_7_12_gguf() []const u8 { return "models/local-7-12.gguf"; }
pub fn local_model_7_12_ctx() u32 { return 26624; }
pub fn local_model_7_12_threads() u32 { return 12; }
pub fn local_model_7_12_gpu_layers() i32 { return 12; }
pub fn local_model_7_12_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_12_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_7_12_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_12_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_12(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_13_id() []const u8 { return "local-7-13"; }
pub fn local_model_7_13_gguf() []const u8 { return "models/local-7-13.gguf"; }
pub fn local_model_7_13_ctx() u32 { return 28672; }
pub fn local_model_7_13_threads() u32 { return 13; }
pub fn local_model_7_13_gpu_layers() i32 { return 13; }
pub fn local_model_7_13_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_13_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_7_13_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_13_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_13(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_14_id() []const u8 { return "local-7-14"; }
pub fn local_model_7_14_gguf() []const u8 { return "models/local-7-14.gguf"; }
pub fn local_model_7_14_ctx() u32 { return 30720; }
pub fn local_model_7_14_threads() u32 { return 14; }
pub fn local_model_7_14_gpu_layers() i32 { return 14; }
pub fn local_model_7_14_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_14_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_7_14_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_14_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_14(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_15_id() []const u8 { return "local-7-15"; }
pub fn local_model_7_15_gguf() []const u8 { return "models/local-7-15.gguf"; }
pub fn local_model_7_15_ctx() u32 { return 32768; }
pub fn local_model_7_15_threads() u32 { return 15; }
pub fn local_model_7_15_gpu_layers() i32 { return 15; }
pub fn local_model_7_15_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_15_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_7_15_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_15_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_15(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_16_id() []const u8 { return "local-7-16"; }
pub fn local_model_7_16_gguf() []const u8 { return "models/local-7-16.gguf"; }
pub fn local_model_7_16_ctx() u32 { return 2048; }
pub fn local_model_7_16_threads() u32 { return 1; }
pub fn local_model_7_16_gpu_layers() i32 { return 16; }
pub fn local_model_7_16_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_16_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_7_16_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_16_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_16(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_17_id() []const u8 { return "local-7-17"; }
pub fn local_model_7_17_gguf() []const u8 { return "models/local-7-17.gguf"; }
pub fn local_model_7_17_ctx() u32 { return 4096; }
pub fn local_model_7_17_threads() u32 { return 1; }
pub fn local_model_7_17_gpu_layers() i32 { return 17; }
pub fn local_model_7_17_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_17_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_7_17_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_17_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_17(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_18_id() []const u8 { return "local-7-18"; }
pub fn local_model_7_18_gguf() []const u8 { return "models/local-7-18.gguf"; }
pub fn local_model_7_18_ctx() u32 { return 6144; }
pub fn local_model_7_18_threads() u32 { return 2; }
pub fn local_model_7_18_gpu_layers() i32 { return 18; }
pub fn local_model_7_18_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_18_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_7_18_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_18_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_18(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_19_id() []const u8 { return "local-7-19"; }
pub fn local_model_7_19_gguf() []const u8 { return "models/local-7-19.gguf"; }
pub fn local_model_7_19_ctx() u32 { return 8192; }
pub fn local_model_7_19_threads() u32 { return 3; }
pub fn local_model_7_19_gpu_layers() i32 { return 19; }
pub fn local_model_7_19_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_19_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_7_19_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_19_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_19(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_20_id() []const u8 { return "local-7-20"; }
pub fn local_model_7_20_gguf() []const u8 { return "models/local-7-20.gguf"; }
pub fn local_model_7_20_ctx() u32 { return 10240; }
pub fn local_model_7_20_threads() u32 { return 4; }
pub fn local_model_7_20_gpu_layers() i32 { return 20; }
pub fn local_model_7_20_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_20_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_7_20_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_20_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_20(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_21_id() []const u8 { return "local-7-21"; }
pub fn local_model_7_21_gguf() []const u8 { return "models/local-7-21.gguf"; }
pub fn local_model_7_21_ctx() u32 { return 12288; }
pub fn local_model_7_21_threads() u32 { return 5; }
pub fn local_model_7_21_gpu_layers() i32 { return 21; }
pub fn local_model_7_21_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_21_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_7_21_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_21_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_21(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_22_id() []const u8 { return "local-7-22"; }
pub fn local_model_7_22_gguf() []const u8 { return "models/local-7-22.gguf"; }
pub fn local_model_7_22_ctx() u32 { return 14336; }
pub fn local_model_7_22_threads() u32 { return 6; }
pub fn local_model_7_22_gpu_layers() i32 { return 22; }
pub fn local_model_7_22_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_22_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_7_22_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_22_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_22(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_23_id() []const u8 { return "local-7-23"; }
pub fn local_model_7_23_gguf() []const u8 { return "models/local-7-23.gguf"; }
pub fn local_model_7_23_ctx() u32 { return 16384; }
pub fn local_model_7_23_threads() u32 { return 7; }
pub fn local_model_7_23_gpu_layers() i32 { return 23; }
pub fn local_model_7_23_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_23_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_7_23_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_23_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_23(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_24_id() []const u8 { return "local-7-24"; }
pub fn local_model_7_24_gguf() []const u8 { return "models/local-7-24.gguf"; }
pub fn local_model_7_24_ctx() u32 { return 18432; }
pub fn local_model_7_24_threads() u32 { return 8; }
pub fn local_model_7_24_gpu_layers() i32 { return 24; }
pub fn local_model_7_24_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_24_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_7_24_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_24_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_24(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_25_id() []const u8 { return "local-7-25"; }
pub fn local_model_7_25_gguf() []const u8 { return "models/local-7-25.gguf"; }
pub fn local_model_7_25_ctx() u32 { return 20480; }
pub fn local_model_7_25_threads() u32 { return 9; }
pub fn local_model_7_25_gpu_layers() i32 { return 25; }
pub fn local_model_7_25_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_25_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_7_25_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_25_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_25(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_26_id() []const u8 { return "local-7-26"; }
pub fn local_model_7_26_gguf() []const u8 { return "models/local-7-26.gguf"; }
pub fn local_model_7_26_ctx() u32 { return 22528; }
pub fn local_model_7_26_threads() u32 { return 10; }
pub fn local_model_7_26_gpu_layers() i32 { return 26; }
pub fn local_model_7_26_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_26_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_7_26_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_26_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_26(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_27_id() []const u8 { return "local-7-27"; }
pub fn local_model_7_27_gguf() []const u8 { return "models/local-7-27.gguf"; }
pub fn local_model_7_27_ctx() u32 { return 24576; }
pub fn local_model_7_27_threads() u32 { return 11; }
pub fn local_model_7_27_gpu_layers() i32 { return 27; }
pub fn local_model_7_27_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_27_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_7_27_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_27_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_27(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_28_id() []const u8 { return "local-7-28"; }
pub fn local_model_7_28_gguf() []const u8 { return "models/local-7-28.gguf"; }
pub fn local_model_7_28_ctx() u32 { return 26624; }
pub fn local_model_7_28_threads() u32 { return 12; }
pub fn local_model_7_28_gpu_layers() i32 { return 28; }
pub fn local_model_7_28_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_28_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_7_28_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_28_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_28(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_29_id() []const u8 { return "local-7-29"; }
pub fn local_model_7_29_gguf() []const u8 { return "models/local-7-29.gguf"; }
pub fn local_model_7_29_ctx() u32 { return 28672; }
pub fn local_model_7_29_threads() u32 { return 13; }
pub fn local_model_7_29_gpu_layers() i32 { return 29; }
pub fn local_model_7_29_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_29_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_7_29_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_29_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_29(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_30_id() []const u8 { return "local-7-30"; }
pub fn local_model_7_30_gguf() []const u8 { return "models/local-7-30.gguf"; }
pub fn local_model_7_30_ctx() u32 { return 30720; }
pub fn local_model_7_30_threads() u32 { return 14; }
pub fn local_model_7_30_gpu_layers() i32 { return 30; }
pub fn local_model_7_30_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_30_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_7_30_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_30_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_30(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_31_id() []const u8 { return "local-7-31"; }
pub fn local_model_7_31_gguf() []const u8 { return "models/local-7-31.gguf"; }
pub fn local_model_7_31_ctx() u32 { return 32768; }
pub fn local_model_7_31_threads() u32 { return 15; }
pub fn local_model_7_31_gpu_layers() i32 { return 31; }
pub fn local_model_7_31_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_31_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_7_31_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_31_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_31(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_32_id() []const u8 { return "local-7-32"; }
pub fn local_model_7_32_gguf() []const u8 { return "models/local-7-32.gguf"; }
pub fn local_model_7_32_ctx() u32 { return 2048; }
pub fn local_model_7_32_threads() u32 { return 1; }
pub fn local_model_7_32_gpu_layers() i32 { return 32; }
pub fn local_model_7_32_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_32_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_7_32_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_32_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_32(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_33_id() []const u8 { return "local-7-33"; }
pub fn local_model_7_33_gguf() []const u8 { return "models/local-7-33.gguf"; }
pub fn local_model_7_33_ctx() u32 { return 4096; }
pub fn local_model_7_33_threads() u32 { return 1; }
pub fn local_model_7_33_gpu_layers() i32 { return 33; }
pub fn local_model_7_33_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_33_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_7_33_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_33_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_33(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_34_id() []const u8 { return "local-7-34"; }
pub fn local_model_7_34_gguf() []const u8 { return "models/local-7-34.gguf"; }
pub fn local_model_7_34_ctx() u32 { return 6144; }
pub fn local_model_7_34_threads() u32 { return 2; }
pub fn local_model_7_34_gpu_layers() i32 { return 34; }
pub fn local_model_7_34_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_34_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_7_34_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_34_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_34(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_35_id() []const u8 { return "local-7-35"; }
pub fn local_model_7_35_gguf() []const u8 { return "models/local-7-35.gguf"; }
pub fn local_model_7_35_ctx() u32 { return 8192; }
pub fn local_model_7_35_threads() u32 { return 3; }
pub fn local_model_7_35_gpu_layers() i32 { return 35; }
pub fn local_model_7_35_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_35_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_7_35_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_35_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_35(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_36_id() []const u8 { return "local-7-36"; }
pub fn local_model_7_36_gguf() []const u8 { return "models/local-7-36.gguf"; }
pub fn local_model_7_36_ctx() u32 { return 10240; }
pub fn local_model_7_36_threads() u32 { return 4; }
pub fn local_model_7_36_gpu_layers() i32 { return 36; }
pub fn local_model_7_36_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_36_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_7_36_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_36_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_36(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_37_id() []const u8 { return "local-7-37"; }
pub fn local_model_7_37_gguf() []const u8 { return "models/local-7-37.gguf"; }
pub fn local_model_7_37_ctx() u32 { return 12288; }
pub fn local_model_7_37_threads() u32 { return 5; }
pub fn local_model_7_37_gpu_layers() i32 { return 37; }
pub fn local_model_7_37_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_37_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_7_37_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_37_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_37(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_38_id() []const u8 { return "local-7-38"; }
pub fn local_model_7_38_gguf() []const u8 { return "models/local-7-38.gguf"; }
pub fn local_model_7_38_ctx() u32 { return 14336; }
pub fn local_model_7_38_threads() u32 { return 6; }
pub fn local_model_7_38_gpu_layers() i32 { return 38; }
pub fn local_model_7_38_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_38_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_7_38_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_38_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_38(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_7_39_id() []const u8 { return "local-7-39"; }
pub fn local_model_7_39_gguf() []const u8 { return "models/local-7-39.gguf"; }
pub fn local_model_7_39_ctx() u32 { return 16384; }
pub fn local_model_7_39_threads() u32 { return 7; }
pub fn local_model_7_39_gpu_layers() i32 { return 39; }
pub fn local_model_7_39_chat_template() []const u8 { return "chatml"; }
pub fn local_model_7_39_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_7_39_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_7_39_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_7_39(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

test "llama shard 7" {
    try std.testing.expectEqualStrings("ollama", runtimeName(.ollama));
    try std.testing.expectEqualStrings("local-7-0", local_model_7_0_id());
    const gpa = std.testing.allocator;
    const argv = try local_model_7_0_argv(gpa);
    defer free_argv_7_0(gpa, argv);
    try std.testing.expect(argv.len == 3);
}

