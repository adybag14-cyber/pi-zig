//! Generated local llama/runtime glue shard 10.
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

pub fn local_model_10_0_id() []const u8 { return "local-10-0"; }
pub fn local_model_10_0_gguf() []const u8 { return "models/local-10-0.gguf"; }
pub fn local_model_10_0_ctx() u32 { return 2048; }
pub fn local_model_10_0_threads() u32 { return 1; }
pub fn local_model_10_0_gpu_layers() i32 { return 0; }
pub fn local_model_10_0_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_0_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_10_0_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_0_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_0(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_1_id() []const u8 { return "local-10-1"; }
pub fn local_model_10_1_gguf() []const u8 { return "models/local-10-1.gguf"; }
pub fn local_model_10_1_ctx() u32 { return 4096; }
pub fn local_model_10_1_threads() u32 { return 1; }
pub fn local_model_10_1_gpu_layers() i32 { return 1; }
pub fn local_model_10_1_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_1_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_10_1_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_1_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_1(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_2_id() []const u8 { return "local-10-2"; }
pub fn local_model_10_2_gguf() []const u8 { return "models/local-10-2.gguf"; }
pub fn local_model_10_2_ctx() u32 { return 6144; }
pub fn local_model_10_2_threads() u32 { return 2; }
pub fn local_model_10_2_gpu_layers() i32 { return 2; }
pub fn local_model_10_2_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_2_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_10_2_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_2_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_2(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_3_id() []const u8 { return "local-10-3"; }
pub fn local_model_10_3_gguf() []const u8 { return "models/local-10-3.gguf"; }
pub fn local_model_10_3_ctx() u32 { return 8192; }
pub fn local_model_10_3_threads() u32 { return 3; }
pub fn local_model_10_3_gpu_layers() i32 { return 3; }
pub fn local_model_10_3_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_3_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_10_3_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_3_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_3(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_4_id() []const u8 { return "local-10-4"; }
pub fn local_model_10_4_gguf() []const u8 { return "models/local-10-4.gguf"; }
pub fn local_model_10_4_ctx() u32 { return 10240; }
pub fn local_model_10_4_threads() u32 { return 4; }
pub fn local_model_10_4_gpu_layers() i32 { return 4; }
pub fn local_model_10_4_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_4_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_10_4_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_4_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_4(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_5_id() []const u8 { return "local-10-5"; }
pub fn local_model_10_5_gguf() []const u8 { return "models/local-10-5.gguf"; }
pub fn local_model_10_5_ctx() u32 { return 12288; }
pub fn local_model_10_5_threads() u32 { return 5; }
pub fn local_model_10_5_gpu_layers() i32 { return 5; }
pub fn local_model_10_5_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_5_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_10_5_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_5_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_5(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_6_id() []const u8 { return "local-10-6"; }
pub fn local_model_10_6_gguf() []const u8 { return "models/local-10-6.gguf"; }
pub fn local_model_10_6_ctx() u32 { return 14336; }
pub fn local_model_10_6_threads() u32 { return 6; }
pub fn local_model_10_6_gpu_layers() i32 { return 6; }
pub fn local_model_10_6_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_6_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_10_6_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_6_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_6(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_7_id() []const u8 { return "local-10-7"; }
pub fn local_model_10_7_gguf() []const u8 { return "models/local-10-7.gguf"; }
pub fn local_model_10_7_ctx() u32 { return 16384; }
pub fn local_model_10_7_threads() u32 { return 7; }
pub fn local_model_10_7_gpu_layers() i32 { return 7; }
pub fn local_model_10_7_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_7_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_10_7_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_7_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_7(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_8_id() []const u8 { return "local-10-8"; }
pub fn local_model_10_8_gguf() []const u8 { return "models/local-10-8.gguf"; }
pub fn local_model_10_8_ctx() u32 { return 18432; }
pub fn local_model_10_8_threads() u32 { return 8; }
pub fn local_model_10_8_gpu_layers() i32 { return 8; }
pub fn local_model_10_8_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_8_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_10_8_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_8_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_8(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_9_id() []const u8 { return "local-10-9"; }
pub fn local_model_10_9_gguf() []const u8 { return "models/local-10-9.gguf"; }
pub fn local_model_10_9_ctx() u32 { return 20480; }
pub fn local_model_10_9_threads() u32 { return 9; }
pub fn local_model_10_9_gpu_layers() i32 { return 9; }
pub fn local_model_10_9_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_9_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_10_9_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_9_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_9(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_10_id() []const u8 { return "local-10-10"; }
pub fn local_model_10_10_gguf() []const u8 { return "models/local-10-10.gguf"; }
pub fn local_model_10_10_ctx() u32 { return 22528; }
pub fn local_model_10_10_threads() u32 { return 10; }
pub fn local_model_10_10_gpu_layers() i32 { return 10; }
pub fn local_model_10_10_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_10_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_10_10_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_10_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_10(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_11_id() []const u8 { return "local-10-11"; }
pub fn local_model_10_11_gguf() []const u8 { return "models/local-10-11.gguf"; }
pub fn local_model_10_11_ctx() u32 { return 24576; }
pub fn local_model_10_11_threads() u32 { return 11; }
pub fn local_model_10_11_gpu_layers() i32 { return 11; }
pub fn local_model_10_11_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_11_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_10_11_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_11_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_11(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_12_id() []const u8 { return "local-10-12"; }
pub fn local_model_10_12_gguf() []const u8 { return "models/local-10-12.gguf"; }
pub fn local_model_10_12_ctx() u32 { return 26624; }
pub fn local_model_10_12_threads() u32 { return 12; }
pub fn local_model_10_12_gpu_layers() i32 { return 12; }
pub fn local_model_10_12_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_12_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_10_12_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_12_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_12(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_13_id() []const u8 { return "local-10-13"; }
pub fn local_model_10_13_gguf() []const u8 { return "models/local-10-13.gguf"; }
pub fn local_model_10_13_ctx() u32 { return 28672; }
pub fn local_model_10_13_threads() u32 { return 13; }
pub fn local_model_10_13_gpu_layers() i32 { return 13; }
pub fn local_model_10_13_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_13_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_10_13_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_13_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_13(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_14_id() []const u8 { return "local-10-14"; }
pub fn local_model_10_14_gguf() []const u8 { return "models/local-10-14.gguf"; }
pub fn local_model_10_14_ctx() u32 { return 30720; }
pub fn local_model_10_14_threads() u32 { return 14; }
pub fn local_model_10_14_gpu_layers() i32 { return 14; }
pub fn local_model_10_14_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_14_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_10_14_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_14_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_14(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_15_id() []const u8 { return "local-10-15"; }
pub fn local_model_10_15_gguf() []const u8 { return "models/local-10-15.gguf"; }
pub fn local_model_10_15_ctx() u32 { return 32768; }
pub fn local_model_10_15_threads() u32 { return 15; }
pub fn local_model_10_15_gpu_layers() i32 { return 15; }
pub fn local_model_10_15_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_15_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_10_15_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_15_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_15(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_16_id() []const u8 { return "local-10-16"; }
pub fn local_model_10_16_gguf() []const u8 { return "models/local-10-16.gguf"; }
pub fn local_model_10_16_ctx() u32 { return 2048; }
pub fn local_model_10_16_threads() u32 { return 1; }
pub fn local_model_10_16_gpu_layers() i32 { return 16; }
pub fn local_model_10_16_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_16_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_10_16_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_16_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_16(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_17_id() []const u8 { return "local-10-17"; }
pub fn local_model_10_17_gguf() []const u8 { return "models/local-10-17.gguf"; }
pub fn local_model_10_17_ctx() u32 { return 4096; }
pub fn local_model_10_17_threads() u32 { return 1; }
pub fn local_model_10_17_gpu_layers() i32 { return 17; }
pub fn local_model_10_17_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_17_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_10_17_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_17_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_17(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_18_id() []const u8 { return "local-10-18"; }
pub fn local_model_10_18_gguf() []const u8 { return "models/local-10-18.gguf"; }
pub fn local_model_10_18_ctx() u32 { return 6144; }
pub fn local_model_10_18_threads() u32 { return 2; }
pub fn local_model_10_18_gpu_layers() i32 { return 18; }
pub fn local_model_10_18_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_18_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_10_18_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_18_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_18(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_19_id() []const u8 { return "local-10-19"; }
pub fn local_model_10_19_gguf() []const u8 { return "models/local-10-19.gguf"; }
pub fn local_model_10_19_ctx() u32 { return 8192; }
pub fn local_model_10_19_threads() u32 { return 3; }
pub fn local_model_10_19_gpu_layers() i32 { return 19; }
pub fn local_model_10_19_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_19_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_10_19_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_19_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_19(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_20_id() []const u8 { return "local-10-20"; }
pub fn local_model_10_20_gguf() []const u8 { return "models/local-10-20.gguf"; }
pub fn local_model_10_20_ctx() u32 { return 10240; }
pub fn local_model_10_20_threads() u32 { return 4; }
pub fn local_model_10_20_gpu_layers() i32 { return 20; }
pub fn local_model_10_20_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_20_endpoint() []const u8 { return "http://127.0.0.1:11434/v1"; }
pub fn local_model_10_20_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_20_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_20(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_21_id() []const u8 { return "local-10-21"; }
pub fn local_model_10_21_gguf() []const u8 { return "models/local-10-21.gguf"; }
pub fn local_model_10_21_ctx() u32 { return 12288; }
pub fn local_model_10_21_threads() u32 { return 5; }
pub fn local_model_10_21_gpu_layers() i32 { return 21; }
pub fn local_model_10_21_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_21_endpoint() []const u8 { return "http://127.0.0.1:11435/v1"; }
pub fn local_model_10_21_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_21_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_21(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_22_id() []const u8 { return "local-10-22"; }
pub fn local_model_10_22_gguf() []const u8 { return "models/local-10-22.gguf"; }
pub fn local_model_10_22_ctx() u32 { return 14336; }
pub fn local_model_10_22_threads() u32 { return 6; }
pub fn local_model_10_22_gpu_layers() i32 { return 22; }
pub fn local_model_10_22_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_22_endpoint() []const u8 { return "http://127.0.0.1:11436/v1"; }
pub fn local_model_10_22_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_22_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_22(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_23_id() []const u8 { return "local-10-23"; }
pub fn local_model_10_23_gguf() []const u8 { return "models/local-10-23.gguf"; }
pub fn local_model_10_23_ctx() u32 { return 16384; }
pub fn local_model_10_23_threads() u32 { return 7; }
pub fn local_model_10_23_gpu_layers() i32 { return 23; }
pub fn local_model_10_23_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_23_endpoint() []const u8 { return "http://127.0.0.1:11437/v1"; }
pub fn local_model_10_23_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_23_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_23(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_24_id() []const u8 { return "local-10-24"; }
pub fn local_model_10_24_gguf() []const u8 { return "models/local-10-24.gguf"; }
pub fn local_model_10_24_ctx() u32 { return 18432; }
pub fn local_model_10_24_threads() u32 { return 8; }
pub fn local_model_10_24_gpu_layers() i32 { return 24; }
pub fn local_model_10_24_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_24_endpoint() []const u8 { return "http://127.0.0.1:11438/v1"; }
pub fn local_model_10_24_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_24_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_24(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_25_id() []const u8 { return "local-10-25"; }
pub fn local_model_10_25_gguf() []const u8 { return "models/local-10-25.gguf"; }
pub fn local_model_10_25_ctx() u32 { return 20480; }
pub fn local_model_10_25_threads() u32 { return 9; }
pub fn local_model_10_25_gpu_layers() i32 { return 25; }
pub fn local_model_10_25_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_25_endpoint() []const u8 { return "http://127.0.0.1:11439/v1"; }
pub fn local_model_10_25_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_25_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_25(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_26_id() []const u8 { return "local-10-26"; }
pub fn local_model_10_26_gguf() []const u8 { return "models/local-10-26.gguf"; }
pub fn local_model_10_26_ctx() u32 { return 22528; }
pub fn local_model_10_26_threads() u32 { return 10; }
pub fn local_model_10_26_gpu_layers() i32 { return 26; }
pub fn local_model_10_26_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_26_endpoint() []const u8 { return "http://127.0.0.1:11440/v1"; }
pub fn local_model_10_26_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_26_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_26(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_27_id() []const u8 { return "local-10-27"; }
pub fn local_model_10_27_gguf() []const u8 { return "models/local-10-27.gguf"; }
pub fn local_model_10_27_ctx() u32 { return 24576; }
pub fn local_model_10_27_threads() u32 { return 11; }
pub fn local_model_10_27_gpu_layers() i32 { return 27; }
pub fn local_model_10_27_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_27_endpoint() []const u8 { return "http://127.0.0.1:11441/v1"; }
pub fn local_model_10_27_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_27_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_27(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_28_id() []const u8 { return "local-10-28"; }
pub fn local_model_10_28_gguf() []const u8 { return "models/local-10-28.gguf"; }
pub fn local_model_10_28_ctx() u32 { return 26624; }
pub fn local_model_10_28_threads() u32 { return 12; }
pub fn local_model_10_28_gpu_layers() i32 { return 28; }
pub fn local_model_10_28_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_28_endpoint() []const u8 { return "http://127.0.0.1:11442/v1"; }
pub fn local_model_10_28_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_28_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_28(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_29_id() []const u8 { return "local-10-29"; }
pub fn local_model_10_29_gguf() []const u8 { return "models/local-10-29.gguf"; }
pub fn local_model_10_29_ctx() u32 { return 28672; }
pub fn local_model_10_29_threads() u32 { return 13; }
pub fn local_model_10_29_gpu_layers() i32 { return 29; }
pub fn local_model_10_29_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_29_endpoint() []const u8 { return "http://127.0.0.1:11443/v1"; }
pub fn local_model_10_29_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_29_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_29(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_30_id() []const u8 { return "local-10-30"; }
pub fn local_model_10_30_gguf() []const u8 { return "models/local-10-30.gguf"; }
pub fn local_model_10_30_ctx() u32 { return 30720; }
pub fn local_model_10_30_threads() u32 { return 14; }
pub fn local_model_10_30_gpu_layers() i32 { return 30; }
pub fn local_model_10_30_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_30_endpoint() []const u8 { return "http://127.0.0.1:11444/v1"; }
pub fn local_model_10_30_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_30_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_30(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_31_id() []const u8 { return "local-10-31"; }
pub fn local_model_10_31_gguf() []const u8 { return "models/local-10-31.gguf"; }
pub fn local_model_10_31_ctx() u32 { return 32768; }
pub fn local_model_10_31_threads() u32 { return 15; }
pub fn local_model_10_31_gpu_layers() i32 { return 31; }
pub fn local_model_10_31_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_31_endpoint() []const u8 { return "http://127.0.0.1:11445/v1"; }
pub fn local_model_10_31_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_31_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_31(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_32_id() []const u8 { return "local-10-32"; }
pub fn local_model_10_32_gguf() []const u8 { return "models/local-10-32.gguf"; }
pub fn local_model_10_32_ctx() u32 { return 2048; }
pub fn local_model_10_32_threads() u32 { return 1; }
pub fn local_model_10_32_gpu_layers() i32 { return 32; }
pub fn local_model_10_32_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_32_endpoint() []const u8 { return "http://127.0.0.1:11446/v1"; }
pub fn local_model_10_32_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_32_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_32(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_33_id() []const u8 { return "local-10-33"; }
pub fn local_model_10_33_gguf() []const u8 { return "models/local-10-33.gguf"; }
pub fn local_model_10_33_ctx() u32 { return 4096; }
pub fn local_model_10_33_threads() u32 { return 1; }
pub fn local_model_10_33_gpu_layers() i32 { return 33; }
pub fn local_model_10_33_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_33_endpoint() []const u8 { return "http://127.0.0.1:11447/v1"; }
pub fn local_model_10_33_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_33_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_33(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_34_id() []const u8 { return "local-10-34"; }
pub fn local_model_10_34_gguf() []const u8 { return "models/local-10-34.gguf"; }
pub fn local_model_10_34_ctx() u32 { return 6144; }
pub fn local_model_10_34_threads() u32 { return 2; }
pub fn local_model_10_34_gpu_layers() i32 { return 34; }
pub fn local_model_10_34_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_34_endpoint() []const u8 { return "http://127.0.0.1:11448/v1"; }
pub fn local_model_10_34_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_34_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_34(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_35_id() []const u8 { return "local-10-35"; }
pub fn local_model_10_35_gguf() []const u8 { return "models/local-10-35.gguf"; }
pub fn local_model_10_35_ctx() u32 { return 8192; }
pub fn local_model_10_35_threads() u32 { return 3; }
pub fn local_model_10_35_gpu_layers() i32 { return 35; }
pub fn local_model_10_35_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_35_endpoint() []const u8 { return "http://127.0.0.1:11449/v1"; }
pub fn local_model_10_35_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_35_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_35(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_36_id() []const u8 { return "local-10-36"; }
pub fn local_model_10_36_gguf() []const u8 { return "models/local-10-36.gguf"; }
pub fn local_model_10_36_ctx() u32 { return 10240; }
pub fn local_model_10_36_threads() u32 { return 4; }
pub fn local_model_10_36_gpu_layers() i32 { return 36; }
pub fn local_model_10_36_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_36_endpoint() []const u8 { return "http://127.0.0.1:11450/v1"; }
pub fn local_model_10_36_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_36_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_36(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_37_id() []const u8 { return "local-10-37"; }
pub fn local_model_10_37_gguf() []const u8 { return "models/local-10-37.gguf"; }
pub fn local_model_10_37_ctx() u32 { return 12288; }
pub fn local_model_10_37_threads() u32 { return 5; }
pub fn local_model_10_37_gpu_layers() i32 { return 37; }
pub fn local_model_10_37_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_37_endpoint() []const u8 { return "http://127.0.0.1:11451/v1"; }
pub fn local_model_10_37_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_37_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_37(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_38_id() []const u8 { return "local-10-38"; }
pub fn local_model_10_38_gguf() []const u8 { return "models/local-10-38.gguf"; }
pub fn local_model_10_38_ctx() u32 { return 14336; }
pub fn local_model_10_38_threads() u32 { return 6; }
pub fn local_model_10_38_gpu_layers() i32 { return 38; }
pub fn local_model_10_38_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_38_endpoint() []const u8 { return "http://127.0.0.1:11452/v1"; }
pub fn local_model_10_38_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_38_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_38(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

pub fn local_model_10_39_id() []const u8 { return "local-10-39"; }
pub fn local_model_10_39_gguf() []const u8 { return "models/local-10-39.gguf"; }
pub fn local_model_10_39_ctx() u32 { return 16384; }
pub fn local_model_10_39_threads() u32 { return 7; }
pub fn local_model_10_39_gpu_layers() i32 { return 39; }
pub fn local_model_10_39_chat_template() []const u8 { return "chatml"; }
pub fn local_model_10_39_endpoint() []const u8 { return "http://127.0.0.1:11453/v1"; }
pub fn local_model_10_39_argv(gpa: std.mem.Allocator) ![]const []const u8 {
    const a0 = try gpa.dupe(u8, "llama-server");
    const a1 = try gpa.dupe(u8, "-m");
    const a2 = try gpa.dupe(u8, local_model_10_39_gguf());
    const out = try gpa.alloc([]const u8, 3);
    out[0] = a0; out[1] = a1; out[2] = a2;
    return out;
}
pub fn free_argv_10_39(gpa: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| gpa.free(a);
    gpa.free(argv);
}

test "llama shard 10" {
    try std.testing.expectEqualStrings("ollama", runtimeName(.ollama));
    try std.testing.expectEqualStrings("local-10-0", local_model_10_0_id());
    const gpa = std.testing.allocator;
    const argv = try local_model_10_0_argv(gpa);
    defer free_argv_10_0(gpa, argv);
    try std.testing.expect(argv.len == 3);
}

