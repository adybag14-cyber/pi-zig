//! Generated tool definitions/schemas shard 16 (agent).
const std = @import("std");

pub const ToolSpec = struct {
    name: []const u8,
    description: []const u8,
    parameters_json: []const u8,
    dangerous: bool,
    requires_cwd: bool,
};

pub const tools = [_]ToolSpec{
    .{ .name = "read_16_0", .description = "Tool read_16_0: read operation variant 0 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_0\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "write_16_1", .description = "Tool write_16_1: write operation variant 1 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_1\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "edit_16_2", .description = "Tool edit_16_2: edit operation variant 2 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_2\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "bash_16_3", .description = "Tool bash_16_3: bash operation variant 3 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_3\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "grep_16_4", .description = "Tool grep_16_4: grep operation variant 4 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_4\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "find_16_5", .description = "Tool find_16_5: find operation variant 5 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_5\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "ls_16_6", .description = "Tool ls_16_6: ls operation variant 6 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_6\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "glob_16_7", .description = "Tool glob_16_7: glob operation variant 7 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_7\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "patch_16_8", .description = "Tool patch_16_8: patch operation variant 8 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_8\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "apply_diff_16_9", .description = "Tool apply_diff_16_9: apply_diff operation variant 9 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_9\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "git_status_16_10", .description = "Tool git_status_16_10: git_status operation variant 10 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_10\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "git_diff_16_11", .description = "Tool git_diff_16_11: git_diff operation variant 11 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_11\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "git_log_16_12", .description = "Tool git_log_16_12: git_log operation variant 12 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_12\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "web_fetch_16_13", .description = "Tool web_fetch_16_13: web_fetch operation variant 13 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_13\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = false },
    .{ .name = "web_search_16_14", .description = "Tool web_search_16_14: web_search operation variant 14 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_14\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = false },
    .{ .name = "memory_get_16_15", .description = "Tool memory_get_16_15: memory_get operation variant 15 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_15\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "memory_set_16_16", .description = "Tool memory_set_16_16: memory_set operation variant 16 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_16\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "notebook_edit_16_17", .description = "Tool notebook_edit_16_17: notebook_edit operation variant 17 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_17\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "todo_write_16_18", .description = "Tool todo_write_16_18: todo_write operation variant 18 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_18\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "todo_read_16_19", .description = "Tool todo_read_16_19: todo_read operation variant 19 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_19\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "skill_run_16_20", .description = "Tool skill_run_16_20: skill_run operation variant 20 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_20\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "mcp_call_16_21", .description = "Tool mcp_call_16_21: mcp_call operation variant 21 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_21\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "image_describe_16_22", .description = "Tool image_describe_16_22: image_describe operation variant 22 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_22\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "format_code_16_23", .description = "Tool format_code_16_23: format_code operation variant 23 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_23\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "lint_code_16_24", .description = "Tool lint_code_16_24: lint_code operation variant 24 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_24\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "test_run_16_25", .description = "Tool test_run_16_25: test_run operation variant 25 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_25\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "build_run_16_26", .description = "Tool build_run_16_26: build_run operation variant 26 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_26\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "typecheck_16_27", .description = "Tool typecheck_16_27: typecheck operation variant 27 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_27\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "rename_symbol_16_28", .description = "Tool rename_symbol_16_28: rename_symbol operation variant 28 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_28\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "read_16_29", .description = "Tool read_16_29: read operation variant 29 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_29\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "write_16_30", .description = "Tool write_16_30: write operation variant 30 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_30\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "edit_16_31", .description = "Tool edit_16_31: edit operation variant 31 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_31\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "bash_16_32", .description = "Tool bash_16_32: bash operation variant 32 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_32\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "grep_16_33", .description = "Tool grep_16_33: grep operation variant 33 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_33\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "find_16_34", .description = "Tool find_16_34: find operation variant 34 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_34\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "ls_16_35", .description = "Tool ls_16_35: ls operation variant 35 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_35\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "glob_16_36", .description = "Tool glob_16_36: glob operation variant 36 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_36\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "patch_16_37", .description = "Tool patch_16_37: patch operation variant 37 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_37\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = true, .requires_cwd = true },
    .{ .name = "apply_diff_16_38", .description = "Tool apply_diff_16_38: apply_diff operation variant 38 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_38\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
    .{ .name = "git_status_16_39", .description = "Tool git_status_16_39: git_status operation variant 39 in shard 16", .parameters_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"},\"pattern\":{\"type\":\"string\"},\"flag_39\":{\"type\":\"boolean\"}},\"required\":[\"path\"]}", .dangerous = false, .requires_cwd = true },
};

pub fn toolCount() usize { return tools.len; }

pub fn findTool(name: []const u8) ?ToolSpec {
    for (tools) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}

pub fn openaiToolsJson(gpa: std.mem.Allocator) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("[");
    for (tools, 0..) |t, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"type\":\"function\",\"function\":{\"name\":");
        try std.json.Stringify.value(t.name, .{}, &aw.writer);
        try aw.writer.writeAll(",\"description\":");
        try std.json.Stringify.value(t.description, .{}, &aw.writer);
        try aw.writer.writeAll(",\"parameters\":");
        try aw.writer.writeAll(t.parameters_json);
        try aw.writer.writeAll("}}");
    }
    try aw.writer.writeAll("]");
    return try aw.toOwnedSlice();
}

pub fn validateArgsHasPath(args_json: []const u8) bool {
    return std.mem.indexOf(u8, args_json, "\"path\"") != null;
}

pub fn execute_read_16_0_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:read_16_0:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_read_16_0() []const u8 {
    return tools[0].parameters_json;
}

pub fn execute_write_16_1_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:write_16_1:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_write_16_1() []const u8 {
    return tools[1].parameters_json;
}

pub fn execute_edit_16_2_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:edit_16_2:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_edit_16_2() []const u8 {
    return tools[2].parameters_json;
}

pub fn execute_bash_16_3_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:bash_16_3:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_bash_16_3() []const u8 {
    return tools[3].parameters_json;
}

pub fn execute_grep_16_4_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:grep_16_4:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_grep_16_4() []const u8 {
    return tools[4].parameters_json;
}

pub fn execute_find_16_5_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:find_16_5:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_find_16_5() []const u8 {
    return tools[5].parameters_json;
}

pub fn execute_ls_16_6_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:ls_16_6:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_ls_16_6() []const u8 {
    return tools[6].parameters_json;
}

pub fn execute_glob_16_7_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:glob_16_7:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_glob_16_7() []const u8 {
    return tools[7].parameters_json;
}

pub fn execute_patch_16_8_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:patch_16_8:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_patch_16_8() []const u8 {
    return tools[8].parameters_json;
}

pub fn execute_apply_diff_16_9_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:apply_diff_16_9:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_apply_diff_16_9() []const u8 {
    return tools[9].parameters_json;
}

pub fn execute_git_status_16_10_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:git_status_16_10:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_git_status_16_10() []const u8 {
    return tools[10].parameters_json;
}

pub fn execute_git_diff_16_11_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:git_diff_16_11:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_git_diff_16_11() []const u8 {
    return tools[11].parameters_json;
}

pub fn execute_git_log_16_12_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:git_log_16_12:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_git_log_16_12() []const u8 {
    return tools[12].parameters_json;
}

pub fn execute_web_fetch_16_13_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:web_fetch_16_13:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_web_fetch_16_13() []const u8 {
    return tools[13].parameters_json;
}

pub fn execute_web_search_16_14_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:web_search_16_14:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_web_search_16_14() []const u8 {
    return tools[14].parameters_json;
}

pub fn execute_memory_get_16_15_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:memory_get_16_15:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_memory_get_16_15() []const u8 {
    return tools[15].parameters_json;
}

pub fn execute_memory_set_16_16_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:memory_set_16_16:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_memory_set_16_16() []const u8 {
    return tools[16].parameters_json;
}

pub fn execute_notebook_edit_16_17_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:notebook_edit_16_17:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_notebook_edit_16_17() []const u8 {
    return tools[17].parameters_json;
}

pub fn execute_todo_write_16_18_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:todo_write_16_18:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_todo_write_16_18() []const u8 {
    return tools[18].parameters_json;
}

pub fn execute_todo_read_16_19_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:todo_read_16_19:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_todo_read_16_19() []const u8 {
    return tools[19].parameters_json;
}

pub fn execute_skill_run_16_20_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:skill_run_16_20:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_skill_run_16_20() []const u8 {
    return tools[20].parameters_json;
}

pub fn execute_mcp_call_16_21_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:mcp_call_16_21:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_mcp_call_16_21() []const u8 {
    return tools[21].parameters_json;
}

pub fn execute_image_describe_16_22_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:image_describe_16_22:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_image_describe_16_22() []const u8 {
    return tools[22].parameters_json;
}

pub fn execute_format_code_16_23_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:format_code_16_23:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_format_code_16_23() []const u8 {
    return tools[23].parameters_json;
}

pub fn execute_lint_code_16_24_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:lint_code_16_24:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_lint_code_16_24() []const u8 {
    return tools[24].parameters_json;
}

pub fn execute_test_run_16_25_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:test_run_16_25:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_test_run_16_25() []const u8 {
    return tools[25].parameters_json;
}

pub fn execute_build_run_16_26_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:build_run_16_26:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_build_run_16_26() []const u8 {
    return tools[26].parameters_json;
}

pub fn execute_typecheck_16_27_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:typecheck_16_27:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_typecheck_16_27() []const u8 {
    return tools[27].parameters_json;
}

pub fn execute_rename_symbol_16_28_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:rename_symbol_16_28:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_rename_symbol_16_28() []const u8 {
    return tools[28].parameters_json;
}

pub fn execute_read_16_29_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:read_16_29:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_read_16_29() []const u8 {
    return tools[29].parameters_json;
}

pub fn execute_write_16_30_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:write_16_30:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_write_16_30() []const u8 {
    return tools[30].parameters_json;
}

pub fn execute_edit_16_31_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:edit_16_31:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_edit_16_31() []const u8 {
    return tools[31].parameters_json;
}

pub fn execute_bash_16_32_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:bash_16_32:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_bash_16_32() []const u8 {
    return tools[32].parameters_json;
}

pub fn execute_grep_16_33_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:grep_16_33:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_grep_16_33() []const u8 {
    return tools[33].parameters_json;
}

pub fn execute_find_16_34_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:find_16_34:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_find_16_34() []const u8 {
    return tools[34].parameters_json;
}

pub fn execute_ls_16_35_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:ls_16_35:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_ls_16_35() []const u8 {
    return tools[35].parameters_json;
}

pub fn execute_glob_16_36_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:glob_16_36:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_glob_16_36() []const u8 {
    return tools[36].parameters_json;
}

pub fn execute_patch_16_37_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:patch_16_37:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_patch_16_37() []const u8 {
    return tools[37].parameters_json;
}

pub fn execute_apply_diff_16_38_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:apply_diff_16_38:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_apply_diff_16_38() []const u8 {
    return tools[38].parameters_json;
}

pub fn execute_git_status_16_39_preview(gpa: std.mem.Allocator, args_json: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "preview:git_status_16_39:{d}:{s}", .{args_json.len, if (args_json.len > 64) args_json[0..64] else args_json});
}

pub fn schema_git_status_16_39() []const u8 {
    return tools[39].parameters_json;
}

test "tools shard 16" {
    try std.testing.expect(toolCount() == 40);
    const first = tools[0];
    try std.testing.expect(findTool(first.name) != null);
    const gpa = std.testing.allocator;
    const js = try openaiToolsJson(gpa);
    defer gpa.free(js);
    try std.testing.expect(std.mem.indexOf(u8, js, "\"type\":\"function\"") != null);
}

