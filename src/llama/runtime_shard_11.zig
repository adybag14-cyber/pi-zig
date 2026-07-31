//! Generated local llama/runtime glue shard 11.
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

pub fn local_model_11_0_id() []const u8 { return "local-11-0"; }
pub fn local_model_11_0_gguf() []const u8 { return "models/local-11-0.gguf"; }
pub fn local_model_11_0_ctx() u32 { return 2048; }
pub fn local_model_11_0_threads() u32 { return 1; }
pub fn local_model_11_0_gpu_layers() i32 { return 0; }
pub fn local_model_11_0_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_0_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_11_0_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_0_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_0(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_1_id() []const u8 { return "local-11-1"; }
pub fn local_model_11_1_gguf() []const u8 { return "models/local-11-1.gguf"; }
pub fn local_model_11_1_ctx() u32 { return 4096; }
pub fn local_model_11_1_threads() u32 { return 1; }
pub fn local_model_11_1_gpu_layers() i32 { return 1; }
pub fn local_model_11_1_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_1_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_11_1_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_1_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_1(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_2_id() []const u8 { return "local-11-2"; }
pub fn local_model_11_2_gguf() []const u8 { return "models/local-11-2.gguf"; }
pub fn local_model_11_2_ctx() u32 { return 6144; }
pub fn local_model_11_2_threads() u32 { return 2; }
pub fn local_model_11_2_gpu_layers() i32 { return 2; }
pub fn local_model_11_2_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_2_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_11_2_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_2_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_2(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_3_id() []const u8 { return "local-11-3"; }
pub fn local_model_11_3_gguf() []const u8 { return "models/local-11-3.gguf"; }
pub fn local_model_11_3_ctx() u32 { return 8192; }
pub fn local_model_11_3_threads() u32 { return 3; }
pub fn local_model_11_3_gpu_layers() i32 { return 3; }
pub fn local_model_11_3_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_3_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_11_3_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_3_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_3(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_4_id() []const u8 { return "local-11-4"; }
pub fn local_model_11_4_gguf() []const u8 { return "models/local-11-4.gguf"; }
pub fn local_model_11_4_ctx() u32 { return 10240; }
pub fn local_model_11_4_threads() u32 { return 4; }
pub fn local_model_11_4_gpu_layers() i32 { return 4; }
pub fn local_model_11_4_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_4_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_11_4_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_4_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_4(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_5_id() []const u8 { return "local-11-5"; }
pub fn local_model_11_5_gguf() []const u8 { return "models/local-11-5.gguf"; }
pub fn local_model_11_5_ctx() u32 { return 12288; }
pub fn local_model_11_5_threads() u32 { return 5; }
pub fn local_model_11_5_gpu_layers() i32 { return 5; }
pub fn local_model_11_5_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_5_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_11_5_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_5_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_5(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_6_id() []const u8 { return "local-11-6"; }
pub fn local_model_11_6_gguf() []const u8 { return "models/local-11-6.gguf"; }
pub fn local_model_11_6_ctx() u32 { return 14336; }
pub fn local_model_11_6_threads() u32 { return 6; }
pub fn local_model_11_6_gpu_layers() i32 { return 6; }
pub fn local_model_11_6_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_6_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_11_6_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_6_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_6(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_7_id() []const u8 { return "local-11-7"; }
pub fn local_model_11_7_gguf() []const u8 { return "models/local-11-7.gguf"; }
pub fn local_model_11_7_ctx() u32 { return 16384; }
pub fn local_model_11_7_threads() u32 { return 7; }
pub fn local_model_11_7_gpu_layers() i32 { return 7; }
pub fn local_model_11_7_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_7_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_11_7_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_7_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_7(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_8_id() []const u8 { return "local-11-8"; }
pub fn local_model_11_8_gguf() []const u8 { return "models/local-11-8.gguf"; }
pub fn local_model_11_8_ctx() u32 { return 18432; }
pub fn local_model_11_8_threads() u32 { return 8; }
pub fn local_model_11_8_gpu_layers() i32 { return 8; }
pub fn local_model_11_8_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_8_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_11_8_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_8_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_8(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_9_id() []const u8 { return "local-11-9"; }
pub fn local_model_11_9_gguf() []const u8 { return "models/local-11-9.gguf"; }
pub fn local_model_11_9_ctx() u32 { return 20480; }
pub fn local_model_11_9_threads() u32 { return 9; }
pub fn local_model_11_9_gpu_layers() i32 { return 9; }
pub fn local_model_11_9_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_9_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_11_9_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_9_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_9(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_10_id() []const u8 { return "local-11-10"; }
pub fn local_model_11_10_gguf() []const u8 { return "models/local-11-10.gguf"; }
pub fn local_model_11_10_ctx() u32 { return 22528; }
pub fn local_model_11_10_threads() u32 { return 10; }
pub fn local_model_11_10_gpu_layers() i32 { return 10; }
pub fn local_model_11_10_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_10_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_11_10_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_10_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_10(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_11_id() []const u8 { return "local-11-11"; }
pub fn local_model_11_11_gguf() []const u8 { return "models/local-11-11.gguf"; }
pub fn local_model_11_11_ctx() u32 { return 24576; }
pub fn local_model_11_11_threads() u32 { return 11; }
pub fn local_model_11_11_gpu_layers() i32 { return 11; }
pub fn local_model_11_11_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_11_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_11_11_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_11_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_11(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_12_id() []const u8 { return "local-11-12"; }
pub fn local_model_11_12_gguf() []const u8 { return "models/local-11-12.gguf"; }
pub fn local_model_11_12_ctx() u32 { return 26624; }
pub fn local_model_11_12_threads() u32 { return 12; }
pub fn local_model_11_12_gpu_layers() i32 { return 12; }
pub fn local_model_11_12_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_12_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_11_12_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_12_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_12(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_13_id() []const u8 { return "local-11-13"; }
pub fn local_model_11_13_gguf() []const u8 { return "models/local-11-13.gguf"; }
pub fn local_model_11_13_ctx() u32 { return 28672; }
pub fn local_model_11_13_threads() u32 { return 13; }
pub fn local_model_11_13_gpu_layers() i32 { return 13; }
pub fn local_model_11_13_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_13_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_11_13_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_13_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_13(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_14_id() []const u8 { return "local-11-14"; }
pub fn local_model_11_14_gguf() []const u8 { return "models/local-11-14.gguf"; }
pub fn local_model_11_14_ctx() u32 { return 30720; }
pub fn local_model_11_14_threads() u32 { return 14; }
pub fn local_model_11_14_gpu_layers() i32 { return 14; }
pub fn local_model_11_14_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_14_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_11_14_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_14_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_14(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_15_id() []const u8 { return "local-11-15"; }
pub fn local_model_11_15_gguf() []const u8 { return "models/local-11-15.gguf"; }
pub fn local_model_11_15_ctx() u32 { return 32768; }
pub fn local_model_11_15_threads() u32 { return 15; }
pub fn local_model_11_15_gpu_layers() i32 { return 15; }
pub fn local_model_11_15_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_15_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_11_15_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_15_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_15(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_16_id() []const u8 { return "local-11-16"; }
pub fn local_model_11_16_gguf() []const u8 { return "models/local-11-16.gguf"; }
pub fn local_model_11_16_ctx() u32 { return 2048; }
pub fn local_model_11_16_threads() u32 { return 1; }
pub fn local_model_11_16_gpu_layers() i32 { return 16; }
pub fn local_model_11_16_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_16_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_11_16_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_16_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_16(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_17_id() []const u8 { return "local-11-17"; }
pub fn local_model_11_17_gguf() []const u8 { return "models/local-11-17.gguf"; }
pub fn local_model_11_17_ctx() u32 { return 4096; }
pub fn local_model_11_17_threads() u32 { return 1; }
pub fn local_model_11_17_gpu_layers() i32 { return 17; }
pub fn local_model_11_17_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_17_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_11_17_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_17_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_17(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_18_id() []const u8 { return "local-11-18"; }
pub fn local_model_11_18_gguf() []const u8 { return "models/local-11-18.gguf"; }
pub fn local_model_11_18_ctx() u32 { return 6144; }
pub fn local_model_11_18_threads() u32 { return 2; }
pub fn local_model_11_18_gpu_layers() i32 { return 18; }
pub fn local_model_11_18_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_18_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_11_18_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_18_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_18(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_19_id() []const u8 { return "local-11-19"; }
pub fn local_model_11_19_gguf() []const u8 { return "models/local-11-19.gguf"; }
pub fn local_model_11_19_ctx() u32 { return 8192; }
pub fn local_model_11_19_threads() u32 { return 3; }
pub fn local_model_11_19_gpu_layers() i32 { return 19; }
pub fn local_model_11_19_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_19_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_11_19_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_19_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_19(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_20_id() []const u8 { return "local-11-20"; }
pub fn local_model_11_20_gguf() []const u8 { return "models/local-11-20.gguf"; }
pub fn local_model_11_20_ctx() u32 { return 10240; }
pub fn local_model_11_20_threads() u32 { return 4; }
pub fn local_model_11_20_gpu_layers() i32 { return 20; }
pub fn local_model_11_20_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_20_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_11_20_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_20_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_20(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_21_id() []const u8 { return "local-11-21"; }
pub fn local_model_11_21_gguf() []const u8 { return "models/local-11-21.gguf"; }
pub fn local_model_11_21_ctx() u32 { return 12288; }
pub fn local_model_11_21_threads() u32 { return 5; }
pub fn local_model_11_21_gpu_layers() i32 { return 21; }
pub fn local_model_11_21_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_21_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_11_21_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_21_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_21(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_22_id() []const u8 { return "local-11-22"; }
pub fn local_model_11_22_gguf() []const u8 { return "models/local-11-22.gguf"; }
pub fn local_model_11_22_ctx() u32 { return 14336; }
pub fn local_model_11_22_threads() u32 { return 6; }
pub fn local_model_11_22_gpu_layers() i32 { return 22; }
pub fn local_model_11_22_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_22_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_11_22_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_22_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_22(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_23_id() []const u8 { return "local-11-23"; }
pub fn local_model_11_23_gguf() []const u8 { return "models/local-11-23.gguf"; }
pub fn local_model_11_23_ctx() u32 { return 16384; }
pub fn local_model_11_23_threads() u32 { return 7; }
pub fn local_model_11_23_gpu_layers() i32 { return 23; }
pub fn local_model_11_23_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_23_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_11_23_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_23_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_23(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_24_id() []const u8 { return "local-11-24"; }
pub fn local_model_11_24_gguf() []const u8 { return "models/local-11-24.gguf"; }
pub fn local_model_11_24_ctx() u32 { return 18432; }
pub fn local_model_11_24_threads() u32 { return 8; }
pub fn local_model_11_24_gpu_layers() i32 { return 24; }
pub fn local_model_11_24_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_24_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_11_24_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_24_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_24(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_25_id() []const u8 { return "local-11-25"; }
pub fn local_model_11_25_gguf() []const u8 { return "models/local-11-25.gguf"; }
pub fn local_model_11_25_ctx() u32 { return 20480; }
pub fn local_model_11_25_threads() u32 { return 9; }
pub fn local_model_11_25_gpu_layers() i32 { return 25; }
pub fn local_model_11_25_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_25_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_11_25_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_25_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_25(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_26_id() []const u8 { return "local-11-26"; }
pub fn local_model_11_26_gguf() []const u8 { return "models/local-11-26.gguf"; }
pub fn local_model_11_26_ctx() u32 { return 22528; }
pub fn local_model_11_26_threads() u32 { return 10; }
pub fn local_model_11_26_gpu_layers() i32 { return 26; }
pub fn local_model_11_26_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_26_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_11_26_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_26_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_26(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_27_id() []const u8 { return "local-11-27"; }
pub fn local_model_11_27_gguf() []const u8 { return "models/local-11-27.gguf"; }
pub fn local_model_11_27_ctx() u32 { return 24576; }
pub fn local_model_11_27_threads() u32 { return 11; }
pub fn local_model_11_27_gpu_layers() i32 { return 27; }
pub fn local_model_11_27_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_27_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_11_27_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_27_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_27(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_28_id() []const u8 { return "local-11-28"; }
pub fn local_model_11_28_gguf() []const u8 { return "models/local-11-28.gguf"; }
pub fn local_model_11_28_ctx() u32 { return 26624; }
pub fn local_model_11_28_threads() u32 { return 12; }
pub fn local_model_11_28_gpu_layers() i32 { return 28; }
pub fn local_model_11_28_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_28_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_11_28_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_28_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_28(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_29_id() []const u8 { return "local-11-29"; }
pub fn local_model_11_29_gguf() []const u8 { return "models/local-11-29.gguf"; }
pub fn local_model_11_29_ctx() u32 { return 28672; }
pub fn local_model_11_29_threads() u32 { return 13; }
pub fn local_model_11_29_gpu_layers() i32 { return 29; }
pub fn local_model_11_29_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_29_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_11_29_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_29_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_29(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_30_id() []const u8 { return "local-11-30"; }
pub fn local_model_11_30_gguf() []const u8 { return "models/local-11-30.gguf"; }
pub fn local_model_11_30_ctx() u32 { return 30720; }
pub fn local_model_11_30_threads() u32 { return 14; }
pub fn local_model_11_30_gpu_layers() i32 { return 30; }
pub fn local_model_11_30_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_30_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_11_30_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_30_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_30(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_31_id() []const u8 { return "local-11-31"; }
pub fn local_model_11_31_gguf() []const u8 { return "models/local-11-31.gguf"; }
pub fn local_model_11_31_ctx() u32 { return 32768; }
pub fn local_model_11_31_threads() u32 { return 15; }
pub fn local_model_11_31_gpu_layers() i32 { return 31; }
pub fn local_model_11_31_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_31_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_11_31_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_31_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_31(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_32_id() []const u8 { return "local-11-32"; }
pub fn local_model_11_32_gguf() []const u8 { return "models/local-11-32.gguf"; }
pub fn local_model_11_32_ctx() u32 { return 2048; }
pub fn local_model_11_32_threads() u32 { return 1; }
pub fn local_model_11_32_gpu_layers() i32 { return 32; }
pub fn local_model_11_32_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_32_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_11_32_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_32_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_32(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_33_id() []const u8 { return "local-11-33"; }
pub fn local_model_11_33_gguf() []const u8 { return "models/local-11-33.gguf"; }
pub fn local_model_11_33_ctx() u32 { return 4096; }
pub fn local_model_11_33_threads() u32 { return 1; }
pub fn local_model_11_33_gpu_layers() i32 { return 33; }
pub fn local_model_11_33_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_33_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_11_33_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_33_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_33(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_34_id() []const u8 { return "local-11-34"; }
pub fn local_model_11_34_gguf() []const u8 { return "models/local-11-34.gguf"; }
pub fn local_model_11_34_ctx() u32 { return 6144; }
pub fn local_model_11_34_threads() u32 { return 2; }
pub fn local_model_11_34_gpu_layers() i32 { return 34; }
pub fn local_model_11_34_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_34_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_11_34_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_34_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_34(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_35_id() []const u8 { return "local-11-35"; }
pub fn local_model_11_35_gguf() []const u8 { return "models/local-11-35.gguf"; }
pub fn local_model_11_35_ctx() u32 { return 8192; }
pub fn local_model_11_35_threads() u32 { return 3; }
pub fn local_model_11_35_gpu_layers() i32 { return 35; }
pub fn local_model_11_35_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_35_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_11_35_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_35_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_35(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_36_id() []const u8 { return "local-11-36"; }
pub fn local_model_11_36_gguf() []const u8 { return "models/local-11-36.gguf"; }
pub fn local_model_11_36_ctx() u32 { return 10240; }
pub fn local_model_11_36_threads() u32 { return 4; }
pub fn local_model_11_36_gpu_layers() i32 { return 36; }
pub fn local_model_11_36_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_36_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_11_36_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_36_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_36(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_37_id() []const u8 { return "local-11-37"; }
pub fn local_model_11_37_gguf() []const u8 { return "models/local-11-37.gguf"; }
pub fn local_model_11_37_ctx() u32 { return 12288; }
pub fn local_model_11_37_threads() u32 { return 5; }
pub fn local_model_11_37_gpu_layers() i32 { return 37; }
pub fn local_model_11_37_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_37_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_11_37_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_37_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_37(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_38_id() []const u8 { return "local-11-38"; }
pub fn local_model_11_38_gguf() []const u8 { return "models/local-11-38.gguf"; }
pub fn local_model_11_38_ctx() u32 { return 14336; }
pub fn local_model_11_38_threads() u32 { return 6; }
pub fn local_model_11_38_gpu_layers() i32 { return 38; }
pub fn local_model_11_38_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_38_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_11_38_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_38_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_38(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_11_39_id() []const u8 { return "local-11-39"; }
pub fn local_model_11_39_gguf() []const u8 { return "models/local-11-39.gguf"; }
pub fn local_model_11_39_ctx() u32 { return 16384; }
pub fn local_model_11_39_threads() u32 { return 7; }
pub fn local_model_11_39_gpu_layers() i32 { return 39; }
pub fn local_model_11_39_chat_template() []const u8 { return "chatml"; }
pub fn local_model_11_39_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_11_39_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_11_39_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_11_39(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

test "llama shard 11" {
    try std.testing.expectEqualStrings("ollama", runtimeName(.ollama));
    try std.testing.expectEqualStrings("local-11-0", local_model_11_0_id());
    const gpa = std.testing.allocator;
    const argv = try local_model_11_0_argv(gpa);
    defer free_argv_11_0(gpa, argv);
    try std.testing.expect(argv.len == 3);
}

