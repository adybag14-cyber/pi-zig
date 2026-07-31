//! Generated local llama/runtime glue shard 4.
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

pub fn local_model_4_0_id() []const u8 { return "local-4-0"; }
pub fn local_model_4_0_gguf() []const u8 { return "models/local-4-0.gguf"; }
pub fn local_model_4_0_ctx() u32 { return 2048; }
pub fn local_model_4_0_threads() u32 { return 1; }
pub fn local_model_4_0_gpu_layers() i32 { return 0; }
pub fn local_model_4_0_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_0_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_4_0_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_0_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_0(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_1_id() []const u8 { return "local-4-1"; }
pub fn local_model_4_1_gguf() []const u8 { return "models/local-4-1.gguf"; }
pub fn local_model_4_1_ctx() u32 { return 4096; }
pub fn local_model_4_1_threads() u32 { return 1; }
pub fn local_model_4_1_gpu_layers() i32 { return 1; }
pub fn local_model_4_1_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_1_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_4_1_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_1_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_1(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_2_id() []const u8 { return "local-4-2"; }
pub fn local_model_4_2_gguf() []const u8 { return "models/local-4-2.gguf"; }
pub fn local_model_4_2_ctx() u32 { return 6144; }
pub fn local_model_4_2_threads() u32 { return 2; }
pub fn local_model_4_2_gpu_layers() i32 { return 2; }
pub fn local_model_4_2_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_2_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_4_2_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_2_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_2(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_3_id() []const u8 { return "local-4-3"; }
pub fn local_model_4_3_gguf() []const u8 { return "models/local-4-3.gguf"; }
pub fn local_model_4_3_ctx() u32 { return 8192; }
pub fn local_model_4_3_threads() u32 { return 3; }
pub fn local_model_4_3_gpu_layers() i32 { return 3; }
pub fn local_model_4_3_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_3_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_4_3_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_3_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_3(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_4_id() []const u8 { return "local-4-4"; }
pub fn local_model_4_4_gguf() []const u8 { return "models/local-4-4.gguf"; }
pub fn local_model_4_4_ctx() u32 { return 10240; }
pub fn local_model_4_4_threads() u32 { return 4; }
pub fn local_model_4_4_gpu_layers() i32 { return 4; }
pub fn local_model_4_4_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_4_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_4_4_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_4_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_4(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_5_id() []const u8 { return "local-4-5"; }
pub fn local_model_4_5_gguf() []const u8 { return "models/local-4-5.gguf"; }
pub fn local_model_4_5_ctx() u32 { return 12288; }
pub fn local_model_4_5_threads() u32 { return 5; }
pub fn local_model_4_5_gpu_layers() i32 { return 5; }
pub fn local_model_4_5_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_5_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_4_5_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_5_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_5(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_6_id() []const u8 { return "local-4-6"; }
pub fn local_model_4_6_gguf() []const u8 { return "models/local-4-6.gguf"; }
pub fn local_model_4_6_ctx() u32 { return 14336; }
pub fn local_model_4_6_threads() u32 { return 6; }
pub fn local_model_4_6_gpu_layers() i32 { return 6; }
pub fn local_model_4_6_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_6_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_4_6_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_6_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_6(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_7_id() []const u8 { return "local-4-7"; }
pub fn local_model_4_7_gguf() []const u8 { return "models/local-4-7.gguf"; }
pub fn local_model_4_7_ctx() u32 { return 16384; }
pub fn local_model_4_7_threads() u32 { return 7; }
pub fn local_model_4_7_gpu_layers() i32 { return 7; }
pub fn local_model_4_7_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_7_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_4_7_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_7_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_7(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_8_id() []const u8 { return "local-4-8"; }
pub fn local_model_4_8_gguf() []const u8 { return "models/local-4-8.gguf"; }
pub fn local_model_4_8_ctx() u32 { return 18432; }
pub fn local_model_4_8_threads() u32 { return 8; }
pub fn local_model_4_8_gpu_layers() i32 { return 8; }
pub fn local_model_4_8_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_8_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_4_8_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_8_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_8(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_9_id() []const u8 { return "local-4-9"; }
pub fn local_model_4_9_gguf() []const u8 { return "models/local-4-9.gguf"; }
pub fn local_model_4_9_ctx() u32 { return 20480; }
pub fn local_model_4_9_threads() u32 { return 9; }
pub fn local_model_4_9_gpu_layers() i32 { return 9; }
pub fn local_model_4_9_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_9_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_4_9_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_9_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_9(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_10_id() []const u8 { return "local-4-10"; }
pub fn local_model_4_10_gguf() []const u8 { return "models/local-4-10.gguf"; }
pub fn local_model_4_10_ctx() u32 { return 22528; }
pub fn local_model_4_10_threads() u32 { return 10; }
pub fn local_model_4_10_gpu_layers() i32 { return 10; }
pub fn local_model_4_10_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_10_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_4_10_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_10_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_10(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_11_id() []const u8 { return "local-4-11"; }
pub fn local_model_4_11_gguf() []const u8 { return "models/local-4-11.gguf"; }
pub fn local_model_4_11_ctx() u32 { return 24576; }
pub fn local_model_4_11_threads() u32 { return 11; }
pub fn local_model_4_11_gpu_layers() i32 { return 11; }
pub fn local_model_4_11_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_11_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_4_11_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_11_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_11(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_12_id() []const u8 { return "local-4-12"; }
pub fn local_model_4_12_gguf() []const u8 { return "models/local-4-12.gguf"; }
pub fn local_model_4_12_ctx() u32 { return 26624; }
pub fn local_model_4_12_threads() u32 { return 12; }
pub fn local_model_4_12_gpu_layers() i32 { return 12; }
pub fn local_model_4_12_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_12_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_4_12_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_12_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_12(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_13_id() []const u8 { return "local-4-13"; }
pub fn local_model_4_13_gguf() []const u8 { return "models/local-4-13.gguf"; }
pub fn local_model_4_13_ctx() u32 { return 28672; }
pub fn local_model_4_13_threads() u32 { return 13; }
pub fn local_model_4_13_gpu_layers() i32 { return 13; }
pub fn local_model_4_13_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_13_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_4_13_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_13_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_13(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_14_id() []const u8 { return "local-4-14"; }
pub fn local_model_4_14_gguf() []const u8 { return "models/local-4-14.gguf"; }
pub fn local_model_4_14_ctx() u32 { return 30720; }
pub fn local_model_4_14_threads() u32 { return 14; }
pub fn local_model_4_14_gpu_layers() i32 { return 14; }
pub fn local_model_4_14_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_14_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_4_14_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_14_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_14(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_15_id() []const u8 { return "local-4-15"; }
pub fn local_model_4_15_gguf() []const u8 { return "models/local-4-15.gguf"; }
pub fn local_model_4_15_ctx() u32 { return 32768; }
pub fn local_model_4_15_threads() u32 { return 15; }
pub fn local_model_4_15_gpu_layers() i32 { return 15; }
pub fn local_model_4_15_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_15_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_4_15_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_15_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_15(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_16_id() []const u8 { return "local-4-16"; }
pub fn local_model_4_16_gguf() []const u8 { return "models/local-4-16.gguf"; }
pub fn local_model_4_16_ctx() u32 { return 2048; }
pub fn local_model_4_16_threads() u32 { return 1; }
pub fn local_model_4_16_gpu_layers() i32 { return 16; }
pub fn local_model_4_16_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_16_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_4_16_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_16_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_16(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_17_id() []const u8 { return "local-4-17"; }
pub fn local_model_4_17_gguf() []const u8 { return "models/local-4-17.gguf"; }
pub fn local_model_4_17_ctx() u32 { return 4096; }
pub fn local_model_4_17_threads() u32 { return 1; }
pub fn local_model_4_17_gpu_layers() i32 { return 17; }
pub fn local_model_4_17_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_17_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_4_17_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_17_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_17(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_18_id() []const u8 { return "local-4-18"; }
pub fn local_model_4_18_gguf() []const u8 { return "models/local-4-18.gguf"; }
pub fn local_model_4_18_ctx() u32 { return 6144; }
pub fn local_model_4_18_threads() u32 { return 2; }
pub fn local_model_4_18_gpu_layers() i32 { return 18; }
pub fn local_model_4_18_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_18_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_4_18_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_18_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_18(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_19_id() []const u8 { return "local-4-19"; }
pub fn local_model_4_19_gguf() []const u8 { return "models/local-4-19.gguf"; }
pub fn local_model_4_19_ctx() u32 { return 8192; }
pub fn local_model_4_19_threads() u32 { return 3; }
pub fn local_model_4_19_gpu_layers() i32 { return 19; }
pub fn local_model_4_19_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_19_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_4_19_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_19_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_19(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_20_id() []const u8 { return "local-4-20"; }
pub fn local_model_4_20_gguf() []const u8 { return "models/local-4-20.gguf"; }
pub fn local_model_4_20_ctx() u32 { return 10240; }
pub fn local_model_4_20_threads() u32 { return 4; }
pub fn local_model_4_20_gpu_layers() i32 { return 20; }
pub fn local_model_4_20_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_20_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_4_20_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_20_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_20(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_21_id() []const u8 { return "local-4-21"; }
pub fn local_model_4_21_gguf() []const u8 { return "models/local-4-21.gguf"; }
pub fn local_model_4_21_ctx() u32 { return 12288; }
pub fn local_model_4_21_threads() u32 { return 5; }
pub fn local_model_4_21_gpu_layers() i32 { return 21; }
pub fn local_model_4_21_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_21_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_4_21_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_21_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_21(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_22_id() []const u8 { return "local-4-22"; }
pub fn local_model_4_22_gguf() []const u8 { return "models/local-4-22.gguf"; }
pub fn local_model_4_22_ctx() u32 { return 14336; }
pub fn local_model_4_22_threads() u32 { return 6; }
pub fn local_model_4_22_gpu_layers() i32 { return 22; }
pub fn local_model_4_22_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_22_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_4_22_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_22_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_22(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_23_id() []const u8 { return "local-4-23"; }
pub fn local_model_4_23_gguf() []const u8 { return "models/local-4-23.gguf"; }
pub fn local_model_4_23_ctx() u32 { return 16384; }
pub fn local_model_4_23_threads() u32 { return 7; }
pub fn local_model_4_23_gpu_layers() i32 { return 23; }
pub fn local_model_4_23_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_23_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_4_23_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_23_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_23(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_24_id() []const u8 { return "local-4-24"; }
pub fn local_model_4_24_gguf() []const u8 { return "models/local-4-24.gguf"; }
pub fn local_model_4_24_ctx() u32 { return 18432; }
pub fn local_model_4_24_threads() u32 { return 8; }
pub fn local_model_4_24_gpu_layers() i32 { return 24; }
pub fn local_model_4_24_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_24_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_4_24_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_24_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_24(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_25_id() []const u8 { return "local-4-25"; }
pub fn local_model_4_25_gguf() []const u8 { return "models/local-4-25.gguf"; }
pub fn local_model_4_25_ctx() u32 { return 20480; }
pub fn local_model_4_25_threads() u32 { return 9; }
pub fn local_model_4_25_gpu_layers() i32 { return 25; }
pub fn local_model_4_25_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_25_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_4_25_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_25_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_25(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_26_id() []const u8 { return "local-4-26"; }
pub fn local_model_4_26_gguf() []const u8 { return "models/local-4-26.gguf"; }
pub fn local_model_4_26_ctx() u32 { return 22528; }
pub fn local_model_4_26_threads() u32 { return 10; }
pub fn local_model_4_26_gpu_layers() i32 { return 26; }
pub fn local_model_4_26_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_26_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_4_26_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_26_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_26(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_27_id() []const u8 { return "local-4-27"; }
pub fn local_model_4_27_gguf() []const u8 { return "models/local-4-27.gguf"; }
pub fn local_model_4_27_ctx() u32 { return 24576; }
pub fn local_model_4_27_threads() u32 { return 11; }
pub fn local_model_4_27_gpu_layers() i32 { return 27; }
pub fn local_model_4_27_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_27_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_4_27_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_27_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_27(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_28_id() []const u8 { return "local-4-28"; }
pub fn local_model_4_28_gguf() []const u8 { return "models/local-4-28.gguf"; }
pub fn local_model_4_28_ctx() u32 { return 26624; }
pub fn local_model_4_28_threads() u32 { return 12; }
pub fn local_model_4_28_gpu_layers() i32 { return 28; }
pub fn local_model_4_28_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_28_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_4_28_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_28_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_28(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_29_id() []const u8 { return "local-4-29"; }
pub fn local_model_4_29_gguf() []const u8 { return "models/local-4-29.gguf"; }
pub fn local_model_4_29_ctx() u32 { return 28672; }
pub fn local_model_4_29_threads() u32 { return 13; }
pub fn local_model_4_29_gpu_layers() i32 { return 29; }
pub fn local_model_4_29_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_29_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_4_29_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_29_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_29(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_30_id() []const u8 { return "local-4-30"; }
pub fn local_model_4_30_gguf() []const u8 { return "models/local-4-30.gguf"; }
pub fn local_model_4_30_ctx() u32 { return 30720; }
pub fn local_model_4_30_threads() u32 { return 14; }
pub fn local_model_4_30_gpu_layers() i32 { return 30; }
pub fn local_model_4_30_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_30_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_4_30_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_30_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_30(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_31_id() []const u8 { return "local-4-31"; }
pub fn local_model_4_31_gguf() []const u8 { return "models/local-4-31.gguf"; }
pub fn local_model_4_31_ctx() u32 { return 32768; }
pub fn local_model_4_31_threads() u32 { return 15; }
pub fn local_model_4_31_gpu_layers() i32 { return 31; }
pub fn local_model_4_31_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_31_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_4_31_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_31_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_31(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_32_id() []const u8 { return "local-4-32"; }
pub fn local_model_4_32_gguf() []const u8 { return "models/local-4-32.gguf"; }
pub fn local_model_4_32_ctx() u32 { return 2048; }
pub fn local_model_4_32_threads() u32 { return 1; }
pub fn local_model_4_32_gpu_layers() i32 { return 32; }
pub fn local_model_4_32_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_32_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_4_32_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_32_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_32(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_33_id() []const u8 { return "local-4-33"; }
pub fn local_model_4_33_gguf() []const u8 { return "models/local-4-33.gguf"; }
pub fn local_model_4_33_ctx() u32 { return 4096; }
pub fn local_model_4_33_threads() u32 { return 1; }
pub fn local_model_4_33_gpu_layers() i32 { return 33; }
pub fn local_model_4_33_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_33_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_4_33_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_33_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_33(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_34_id() []const u8 { return "local-4-34"; }
pub fn local_model_4_34_gguf() []const u8 { return "models/local-4-34.gguf"; }
pub fn local_model_4_34_ctx() u32 { return 6144; }
pub fn local_model_4_34_threads() u32 { return 2; }
pub fn local_model_4_34_gpu_layers() i32 { return 34; }
pub fn local_model_4_34_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_34_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_4_34_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_34_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_34(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_35_id() []const u8 { return "local-4-35"; }
pub fn local_model_4_35_gguf() []const u8 { return "models/local-4-35.gguf"; }
pub fn local_model_4_35_ctx() u32 { return 8192; }
pub fn local_model_4_35_threads() u32 { return 3; }
pub fn local_model_4_35_gpu_layers() i32 { return 35; }
pub fn local_model_4_35_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_35_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_4_35_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_35_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_35(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_36_id() []const u8 { return "local-4-36"; }
pub fn local_model_4_36_gguf() []const u8 { return "models/local-4-36.gguf"; }
pub fn local_model_4_36_ctx() u32 { return 10240; }
pub fn local_model_4_36_threads() u32 { return 4; }
pub fn local_model_4_36_gpu_layers() i32 { return 36; }
pub fn local_model_4_36_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_36_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_4_36_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_36_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_36(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_37_id() []const u8 { return "local-4-37"; }
pub fn local_model_4_37_gguf() []const u8 { return "models/local-4-37.gguf"; }
pub fn local_model_4_37_ctx() u32 { return 12288; }
pub fn local_model_4_37_threads() u32 { return 5; }
pub fn local_model_4_37_gpu_layers() i32 { return 37; }
pub fn local_model_4_37_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_37_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_4_37_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_37_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_37(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_38_id() []const u8 { return "local-4-38"; }
pub fn local_model_4_38_gguf() []const u8 { return "models/local-4-38.gguf"; }
pub fn local_model_4_38_ctx() u32 { return 14336; }
pub fn local_model_4_38_threads() u32 { return 6; }
pub fn local_model_4_38_gpu_layers() i32 { return 38; }
pub fn local_model_4_38_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_38_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_4_38_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_38_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_38(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_4_39_id() []const u8 { return "local-4-39"; }
pub fn local_model_4_39_gguf() []const u8 { return "models/local-4-39.gguf"; }
pub fn local_model_4_39_ctx() u32 { return 16384; }
pub fn local_model_4_39_threads() u32 { return 7; }
pub fn local_model_4_39_gpu_layers() i32 { return 39; }
pub fn local_model_4_39_chat_template() []const u8 { return "chatml"; }
pub fn local_model_4_39_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_4_39_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_4_39_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_4_39(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

test "llama shard 4" {
    try std.testing.expectEqualStrings("ollama", runtimeName(.ollama));
    try std.testing.expectEqualStrings("local-4-0", local_model_4_0_id());
    const gpa = std.testing.allocator;
    const argv = try local_model_4_0_argv(gpa);
    defer free_argv_4_0(gpa, argv);
    try std.testing.expect(argv.len == 3);
}

