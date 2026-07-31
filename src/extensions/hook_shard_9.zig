//! Generated extension hook registry shard 9.
const std = @import("std");

pub fn isBuiltinHook(h: []const u8) bool {
    if (std.mem.eql(u8, h, "session_start")) return true;
    if (std.mem.eql(u8, h, "session_end")) return true;
    if (std.mem.eql(u8, h, "before_prompt")) return true;
    if (std.mem.eql(u8, h, "after_prompt")) return true;
    if (std.mem.eql(u8, h, "before_tool")) return true;
    if (std.mem.eql(u8, h, "after_tool")) return true;
    if (std.mem.eql(u8, h, "on_error")) return true;
    if (std.mem.eql(u8, h, "on_abort")) return true;
    if (std.mem.eql(u8, h, "on_model_change")) return true;
    if (std.mem.eql(u8, h, "on_compact")) return true;
    if (std.mem.eql(u8, h, "on_stream_delta")) return true;
    if (std.mem.eql(u8, h, "on_steer")) return true;
    if (std.mem.eql(u8, h, "on_follow_up")) return true;
    if (std.mem.eql(u8, h, "ui_render")) return true;
    if (std.mem.eql(u8, h, "command_register")) return true;
    return false;
}

pub fn ext_9_0_name() []const u8 { return "ext_9_0"; }
pub fn ext_9_0_version() []const u8 { return "1.0.0"; }
pub fn ext_9_0_hook_count() usize { return 1; }
pub fn ext_9_0_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "session_start", "session_end", "before_prompt", "after_prompt", "before_tool" };
    if (idx >= ext_9_0_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_0_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_0\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_0_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_0_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_0_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_1_name() []const u8 { return "ext_9_1"; }
pub fn ext_9_1_version() []const u8 { return "1.0.1"; }
pub fn ext_9_1_hook_count() usize { return 2; }
pub fn ext_9_1_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "session_end", "before_prompt", "after_prompt", "before_tool", "after_tool" };
    if (idx >= ext_9_1_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_1_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_1\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_1_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_1_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_1_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_2_name() []const u8 { return "ext_9_2"; }
pub fn ext_9_2_version() []const u8 { return "1.0.2"; }
pub fn ext_9_2_hook_count() usize { return 3; }
pub fn ext_9_2_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "before_prompt", "after_prompt", "before_tool", "after_tool", "on_error" };
    if (idx >= ext_9_2_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_2_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_2\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_2_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_2_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_2_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_3_name() []const u8 { return "ext_9_3"; }
pub fn ext_9_3_version() []const u8 { return "1.0.3"; }
pub fn ext_9_3_hook_count() usize { return 4; }
pub fn ext_9_3_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "after_prompt", "before_tool", "after_tool", "on_error", "on_abort" };
    if (idx >= ext_9_3_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_3_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_3\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_3_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_3_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_3_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_4_name() []const u8 { return "ext_9_4"; }
pub fn ext_9_4_version() []const u8 { return "1.0.4"; }
pub fn ext_9_4_hook_count() usize { return 5; }
pub fn ext_9_4_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "before_tool", "after_tool", "on_error", "on_abort", "on_model_change" };
    if (idx >= ext_9_4_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_4_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_4\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_4_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_4_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_4_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_5_name() []const u8 { return "ext_9_5"; }
pub fn ext_9_5_version() []const u8 { return "1.0.5"; }
pub fn ext_9_5_hook_count() usize { return 1; }
pub fn ext_9_5_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "after_tool", "on_error", "on_abort", "on_model_change", "on_compact" };
    if (idx >= ext_9_5_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_5_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_5\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_5_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_5_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_5_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_6_name() []const u8 { return "ext_9_6"; }
pub fn ext_9_6_version() []const u8 { return "1.0.6"; }
pub fn ext_9_6_hook_count() usize { return 2; }
pub fn ext_9_6_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_error", "on_abort", "on_model_change", "on_compact", "on_stream_delta" };
    if (idx >= ext_9_6_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_6_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_6\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_6_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_6_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_6_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_7_name() []const u8 { return "ext_9_7"; }
pub fn ext_9_7_version() []const u8 { return "1.0.7"; }
pub fn ext_9_7_hook_count() usize { return 3; }
pub fn ext_9_7_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_abort", "on_model_change", "on_compact", "on_stream_delta", "on_steer" };
    if (idx >= ext_9_7_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_7_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_7\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_7_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_7_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_7_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_8_name() []const u8 { return "ext_9_8"; }
pub fn ext_9_8_version() []const u8 { return "1.0.8"; }
pub fn ext_9_8_hook_count() usize { return 4; }
pub fn ext_9_8_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_model_change", "on_compact", "on_stream_delta", "on_steer", "on_follow_up" };
    if (idx >= ext_9_8_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_8_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_8\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_8_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_8_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_8_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_9_name() []const u8 { return "ext_9_9"; }
pub fn ext_9_9_version() []const u8 { return "1.0.9"; }
pub fn ext_9_9_hook_count() usize { return 5; }
pub fn ext_9_9_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_compact", "on_stream_delta", "on_steer", "on_follow_up", "ui_render" };
    if (idx >= ext_9_9_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_9_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_9\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_9_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_9_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_9_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_10_name() []const u8 { return "ext_9_10"; }
pub fn ext_9_10_version() []const u8 { return "1.0.10"; }
pub fn ext_9_10_hook_count() usize { return 1; }
pub fn ext_9_10_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_stream_delta", "on_steer", "on_follow_up", "ui_render", "command_register" };
    if (idx >= ext_9_10_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_10_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_10\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_10_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_10_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_10_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_11_name() []const u8 { return "ext_9_11"; }
pub fn ext_9_11_version() []const u8 { return "1.0.11"; }
pub fn ext_9_11_hook_count() usize { return 2; }
pub fn ext_9_11_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_steer", "on_follow_up", "ui_render", "command_register", "session_start" };
    if (idx >= ext_9_11_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_11_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_11\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_11_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_11_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_11_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_12_name() []const u8 { return "ext_9_12"; }
pub fn ext_9_12_version() []const u8 { return "1.0.12"; }
pub fn ext_9_12_hook_count() usize { return 3; }
pub fn ext_9_12_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_follow_up", "ui_render", "command_register", "session_start", "session_end" };
    if (idx >= ext_9_12_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_12_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_12\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_12_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_12_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_12_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_13_name() []const u8 { return "ext_9_13"; }
pub fn ext_9_13_version() []const u8 { return "1.0.13"; }
pub fn ext_9_13_hook_count() usize { return 4; }
pub fn ext_9_13_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "ui_render", "command_register", "session_start", "session_end", "before_prompt" };
    if (idx >= ext_9_13_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_13_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_13\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_13_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_13_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_13_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_14_name() []const u8 { return "ext_9_14"; }
pub fn ext_9_14_version() []const u8 { return "1.0.14"; }
pub fn ext_9_14_hook_count() usize { return 5; }
pub fn ext_9_14_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "command_register", "session_start", "session_end", "before_prompt", "after_prompt" };
    if (idx >= ext_9_14_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_14_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_14\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_14_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_14_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_14_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_15_name() []const u8 { return "ext_9_15"; }
pub fn ext_9_15_version() []const u8 { return "1.0.15"; }
pub fn ext_9_15_hook_count() usize { return 1; }
pub fn ext_9_15_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "session_start", "session_end", "before_prompt", "after_prompt", "before_tool" };
    if (idx >= ext_9_15_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_15_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_15\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_15_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_15_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_15_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_16_name() []const u8 { return "ext_9_16"; }
pub fn ext_9_16_version() []const u8 { return "1.0.16"; }
pub fn ext_9_16_hook_count() usize { return 2; }
pub fn ext_9_16_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "session_end", "before_prompt", "after_prompt", "before_tool", "after_tool" };
    if (idx >= ext_9_16_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_16_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_16\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_16_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_16_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_16_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_17_name() []const u8 { return "ext_9_17"; }
pub fn ext_9_17_version() []const u8 { return "1.0.17"; }
pub fn ext_9_17_hook_count() usize { return 3; }
pub fn ext_9_17_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "before_prompt", "after_prompt", "before_tool", "after_tool", "on_error" };
    if (idx >= ext_9_17_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_17_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_17\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_17_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_17_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_17_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_18_name() []const u8 { return "ext_9_18"; }
pub fn ext_9_18_version() []const u8 { return "1.0.18"; }
pub fn ext_9_18_hook_count() usize { return 4; }
pub fn ext_9_18_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "after_prompt", "before_tool", "after_tool", "on_error", "on_abort" };
    if (idx >= ext_9_18_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_18_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_18\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_18_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_18_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_18_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_19_name() []const u8 { return "ext_9_19"; }
pub fn ext_9_19_version() []const u8 { return "1.0.19"; }
pub fn ext_9_19_hook_count() usize { return 5; }
pub fn ext_9_19_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "before_tool", "after_tool", "on_error", "on_abort", "on_model_change" };
    if (idx >= ext_9_19_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_19_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_19\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_19_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_19_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_19_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_20_name() []const u8 { return "ext_9_20"; }
pub fn ext_9_20_version() []const u8 { return "1.0.20"; }
pub fn ext_9_20_hook_count() usize { return 1; }
pub fn ext_9_20_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "after_tool", "on_error", "on_abort", "on_model_change", "on_compact" };
    if (idx >= ext_9_20_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_20_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_20\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_20_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_20_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_20_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_21_name() []const u8 { return "ext_9_21"; }
pub fn ext_9_21_version() []const u8 { return "1.0.21"; }
pub fn ext_9_21_hook_count() usize { return 2; }
pub fn ext_9_21_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_error", "on_abort", "on_model_change", "on_compact", "on_stream_delta" };
    if (idx >= ext_9_21_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_21_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_21\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_21_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_21_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_21_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_22_name() []const u8 { return "ext_9_22"; }
pub fn ext_9_22_version() []const u8 { return "1.0.22"; }
pub fn ext_9_22_hook_count() usize { return 3; }
pub fn ext_9_22_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_abort", "on_model_change", "on_compact", "on_stream_delta", "on_steer" };
    if (idx >= ext_9_22_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_22_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_22\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_22_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_22_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_22_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_23_name() []const u8 { return "ext_9_23"; }
pub fn ext_9_23_version() []const u8 { return "1.0.23"; }
pub fn ext_9_23_hook_count() usize { return 4; }
pub fn ext_9_23_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_model_change", "on_compact", "on_stream_delta", "on_steer", "on_follow_up" };
    if (idx >= ext_9_23_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_23_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_23\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_23_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_23_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_23_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_24_name() []const u8 { return "ext_9_24"; }
pub fn ext_9_24_version() []const u8 { return "1.0.24"; }
pub fn ext_9_24_hook_count() usize { return 5; }
pub fn ext_9_24_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_compact", "on_stream_delta", "on_steer", "on_follow_up", "ui_render" };
    if (idx >= ext_9_24_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_24_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_24\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_24_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_24_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_24_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_25_name() []const u8 { return "ext_9_25"; }
pub fn ext_9_25_version() []const u8 { return "1.0.25"; }
pub fn ext_9_25_hook_count() usize { return 1; }
pub fn ext_9_25_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_stream_delta", "on_steer", "on_follow_up", "ui_render", "command_register" };
    if (idx >= ext_9_25_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_25_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_25\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_25_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_25_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_25_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_26_name() []const u8 { return "ext_9_26"; }
pub fn ext_9_26_version() []const u8 { return "1.0.26"; }
pub fn ext_9_26_hook_count() usize { return 2; }
pub fn ext_9_26_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_steer", "on_follow_up", "ui_render", "command_register", "session_start" };
    if (idx >= ext_9_26_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_26_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_26\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_26_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_26_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_26_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_27_name() []const u8 { return "ext_9_27"; }
pub fn ext_9_27_version() []const u8 { return "1.0.27"; }
pub fn ext_9_27_hook_count() usize { return 3; }
pub fn ext_9_27_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_follow_up", "ui_render", "command_register", "session_start", "session_end" };
    if (idx >= ext_9_27_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_27_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_27\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_27_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_27_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_27_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_28_name() []const u8 { return "ext_9_28"; }
pub fn ext_9_28_version() []const u8 { return "1.0.28"; }
pub fn ext_9_28_hook_count() usize { return 4; }
pub fn ext_9_28_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "ui_render", "command_register", "session_start", "session_end", "before_prompt" };
    if (idx >= ext_9_28_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_28_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_28\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_28_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_28_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_28_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_29_name() []const u8 { return "ext_9_29"; }
pub fn ext_9_29_version() []const u8 { return "1.0.29"; }
pub fn ext_9_29_hook_count() usize { return 5; }
pub fn ext_9_29_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "command_register", "session_start", "session_end", "before_prompt", "after_prompt" };
    if (idx >= ext_9_29_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_29_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_29\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_29_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_29_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_29_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_30_name() []const u8 { return "ext_9_30"; }
pub fn ext_9_30_version() []const u8 { return "1.0.30"; }
pub fn ext_9_30_hook_count() usize { return 1; }
pub fn ext_9_30_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "session_start", "session_end", "before_prompt", "after_prompt", "before_tool" };
    if (idx >= ext_9_30_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_30_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_30\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_30_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_30_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_30_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_31_name() []const u8 { return "ext_9_31"; }
pub fn ext_9_31_version() []const u8 { return "1.0.31"; }
pub fn ext_9_31_hook_count() usize { return 2; }
pub fn ext_9_31_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "session_end", "before_prompt", "after_prompt", "before_tool", "after_tool" };
    if (idx >= ext_9_31_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_31_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_31\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_31_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_31_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_31_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_32_name() []const u8 { return "ext_9_32"; }
pub fn ext_9_32_version() []const u8 { return "1.0.32"; }
pub fn ext_9_32_hook_count() usize { return 3; }
pub fn ext_9_32_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "before_prompt", "after_prompt", "before_tool", "after_tool", "on_error" };
    if (idx >= ext_9_32_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_32_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_32\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_32_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_32_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_32_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_33_name() []const u8 { return "ext_9_33"; }
pub fn ext_9_33_version() []const u8 { return "1.0.33"; }
pub fn ext_9_33_hook_count() usize { return 4; }
pub fn ext_9_33_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "after_prompt", "before_tool", "after_tool", "on_error", "on_abort" };
    if (idx >= ext_9_33_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_33_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_33\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_33_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_33_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_33_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_34_name() []const u8 { return "ext_9_34"; }
pub fn ext_9_34_version() []const u8 { return "1.0.34"; }
pub fn ext_9_34_hook_count() usize { return 5; }
pub fn ext_9_34_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "before_tool", "after_tool", "on_error", "on_abort", "on_model_change" };
    if (idx >= ext_9_34_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_34_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_34\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_34_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_34_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_34_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_35_name() []const u8 { return "ext_9_35"; }
pub fn ext_9_35_version() []const u8 { return "1.0.35"; }
pub fn ext_9_35_hook_count() usize { return 1; }
pub fn ext_9_35_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "after_tool", "on_error", "on_abort", "on_model_change", "on_compact" };
    if (idx >= ext_9_35_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_35_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_35\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_35_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_35_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_35_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_36_name() []const u8 { return "ext_9_36"; }
pub fn ext_9_36_version() []const u8 { return "1.0.36"; }
pub fn ext_9_36_hook_count() usize { return 2; }
pub fn ext_9_36_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_error", "on_abort", "on_model_change", "on_compact", "on_stream_delta" };
    if (idx >= ext_9_36_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_36_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_36\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_36_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_36_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_36_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_37_name() []const u8 { return "ext_9_37"; }
pub fn ext_9_37_version() []const u8 { return "1.0.37"; }
pub fn ext_9_37_hook_count() usize { return 3; }
pub fn ext_9_37_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_abort", "on_model_change", "on_compact", "on_stream_delta", "on_steer" };
    if (idx >= ext_9_37_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_37_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_37\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_37_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_37_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_37_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_38_name() []const u8 { return "ext_9_38"; }
pub fn ext_9_38_version() []const u8 { return "1.0.38"; }
pub fn ext_9_38_hook_count() usize { return 4; }
pub fn ext_9_38_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_model_change", "on_compact", "on_stream_delta", "on_steer", "on_follow_up" };
    if (idx >= ext_9_38_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_38_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_38\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_38_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_38_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_38_hook_at(i), hook)) return true;
    }
    return false;
}

pub fn ext_9_39_name() []const u8 { return "ext_9_39"; }
pub fn ext_9_39_version() []const u8 { return "1.0.39"; }
pub fn ext_9_39_hook_count() usize { return 5; }
pub fn ext_9_39_hook_at(idx: usize) []const u8 {
    const hooks_arr = [_][]const u8{ "on_compact", "on_stream_delta", "on_steer", "on_follow_up", "ui_render" };
    if (idx >= ext_9_39_hook_count()) return "";
    return hooks_arr[idx];
}
pub fn ext_9_39_emit(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ext\":\"ext_9_39\",\"hook\":\"{s}\",\"payload_len\":{d}}}", .{hook, payload.len});
}
pub fn ext_9_39_matches(hook: []const u8) bool {
    var i: usize = 0;
    while (i < ext_9_39_hook_count()) : (i += 1) {
        if (std.mem.eql(u8, ext_9_39_hook_at(i), hook)) return true;
    }
    return false;
}

test "extensions shard 9" {
    try std.testing.expect(isBuiltinHook("before_prompt"));
    try std.testing.expectEqualStrings("ext_9_0", ext_9_0_name());
    const gpa = std.testing.allocator;
    const out = try ext_9_0_emit(gpa, "before_prompt", "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

