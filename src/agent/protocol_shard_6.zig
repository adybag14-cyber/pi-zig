//! Generated RPC/session protocol shard 6 (agent).
const std = @import("std");

pub const MessageKind = enum {
    prompt,
    abort,
    steer,
    follow_up,
    ping,
    quit,
    get_state,
    get_messages,
    set_model,
    cycle_model,
    set_thinking_level,
    compact,
    get_tree,
    set_session_name,
    export_html,
    fork,
    clone,
    new_session,
    get_commands,
    list_sessions,
    get_skills,
    reload,
    set_tools,
    get_usage,
    stream_delta,
    tool_start,
    tool_end,
    error_event,
    session_info,
    model_change,
    compaction,
    auth_status,
    extension_hook,
    mcp_tools,
    server_health,
    index_rebuild,
    theme_apply,
    eval_run,
    ext_msg_6_0,
    ext_msg_6_1,
    ext_msg_6_2,
    ext_msg_6_3,
    ext_msg_6_4,
    ext_msg_6_5,
    ext_msg_6_6,
    ext_msg_6_7,
    ext_msg_6_8,
    ext_msg_6_9,
    ext_msg_6_10,
    ext_msg_6_11,
    ext_msg_6_12,
    ext_msg_6_13,
    ext_msg_6_14,
    ext_msg_6_15,
    ext_msg_6_16,
    ext_msg_6_17,
    ext_msg_6_18,
    ext_msg_6_19,
    ext_msg_6_20,
    ext_msg_6_21,
    ext_msg_6_22,
    ext_msg_6_23,
    ext_msg_6_24,
    ext_msg_6_25,
    ext_msg_6_26,
    ext_msg_6_27,
    ext_msg_6_28,
    ext_msg_6_29,
    ext_msg_6_30,
    ext_msg_6_31,
    ext_msg_6_32,
    ext_msg_6_33,
    ext_msg_6_34,
    ext_msg_6_35,
    ext_msg_6_36,
    ext_msg_6_37,
    ext_msg_6_38,
    ext_msg_6_39,
};

pub fn kindName(k: MessageKind) []const u8 {
    return switch (k) {
        .prompt => "prompt",
        .abort => "abort",
        .steer => "steer",
        .follow_up => "follow_up",
        .ping => "ping",
        .quit => "quit",
        .get_state => "get_state",
        .get_messages => "get_messages",
        .set_model => "set_model",
        .cycle_model => "cycle_model",
        .set_thinking_level => "set_thinking_level",
        .compact => "compact",
        .get_tree => "get_tree",
        .set_session_name => "set_session_name",
        .export_html => "export_html",
        .fork => "fork",
        .clone => "clone",
        .new_session => "new_session",
        .get_commands => "get_commands",
        .list_sessions => "list_sessions",
        .get_skills => "get_skills",
        .reload => "reload",
        .set_tools => "set_tools",
        .get_usage => "get_usage",
        .stream_delta => "stream_delta",
        .tool_start => "tool_start",
        .tool_end => "tool_end",
        .error_event => "error_event",
        .session_info => "session_info",
        .model_change => "model_change",
        .compaction => "compaction",
        .auth_status => "auth_status",
        .extension_hook => "extension_hook",
        .mcp_tools => "mcp_tools",
        .server_health => "server_health",
        .index_rebuild => "index_rebuild",
        .theme_apply => "theme_apply",
        .eval_run => "eval_run",
        .ext_msg_6_0 => "ext_msg_6_0",
        .ext_msg_6_1 => "ext_msg_6_1",
        .ext_msg_6_2 => "ext_msg_6_2",
        .ext_msg_6_3 => "ext_msg_6_3",
        .ext_msg_6_4 => "ext_msg_6_4",
        .ext_msg_6_5 => "ext_msg_6_5",
        .ext_msg_6_6 => "ext_msg_6_6",
        .ext_msg_6_7 => "ext_msg_6_7",
        .ext_msg_6_8 => "ext_msg_6_8",
        .ext_msg_6_9 => "ext_msg_6_9",
        .ext_msg_6_10 => "ext_msg_6_10",
        .ext_msg_6_11 => "ext_msg_6_11",
        .ext_msg_6_12 => "ext_msg_6_12",
        .ext_msg_6_13 => "ext_msg_6_13",
        .ext_msg_6_14 => "ext_msg_6_14",
        .ext_msg_6_15 => "ext_msg_6_15",
        .ext_msg_6_16 => "ext_msg_6_16",
        .ext_msg_6_17 => "ext_msg_6_17",
        .ext_msg_6_18 => "ext_msg_6_18",
        .ext_msg_6_19 => "ext_msg_6_19",
        .ext_msg_6_20 => "ext_msg_6_20",
        .ext_msg_6_21 => "ext_msg_6_21",
        .ext_msg_6_22 => "ext_msg_6_22",
        .ext_msg_6_23 => "ext_msg_6_23",
        .ext_msg_6_24 => "ext_msg_6_24",
        .ext_msg_6_25 => "ext_msg_6_25",
        .ext_msg_6_26 => "ext_msg_6_26",
        .ext_msg_6_27 => "ext_msg_6_27",
        .ext_msg_6_28 => "ext_msg_6_28",
        .ext_msg_6_29 => "ext_msg_6_29",
        .ext_msg_6_30 => "ext_msg_6_30",
        .ext_msg_6_31 => "ext_msg_6_31",
        .ext_msg_6_32 => "ext_msg_6_32",
        .ext_msg_6_33 => "ext_msg_6_33",
        .ext_msg_6_34 => "ext_msg_6_34",
        .ext_msg_6_35 => "ext_msg_6_35",
        .ext_msg_6_36 => "ext_msg_6_36",
        .ext_msg_6_37 => "ext_msg_6_37",
        .ext_msg_6_38 => "ext_msg_6_38",
        .ext_msg_6_39 => "ext_msg_6_39",
    };
}

pub fn parseKind(s: []const u8) ?MessageKind {
    if (std.mem.eql(u8, s, "prompt")) return .prompt;
    if (std.mem.eql(u8, s, "abort")) return .abort;
    if (std.mem.eql(u8, s, "steer")) return .steer;
    if (std.mem.eql(u8, s, "follow_up")) return .follow_up;
    if (std.mem.eql(u8, s, "ping")) return .ping;
    if (std.mem.eql(u8, s, "quit")) return .quit;
    if (std.mem.eql(u8, s, "get_state")) return .get_state;
    if (std.mem.eql(u8, s, "get_messages")) return .get_messages;
    if (std.mem.eql(u8, s, "set_model")) return .set_model;
    if (std.mem.eql(u8, s, "cycle_model")) return .cycle_model;
    if (std.mem.eql(u8, s, "set_thinking_level")) return .set_thinking_level;
    if (std.mem.eql(u8, s, "compact")) return .compact;
    if (std.mem.eql(u8, s, "get_tree")) return .get_tree;
    if (std.mem.eql(u8, s, "set_session_name")) return .set_session_name;
    if (std.mem.eql(u8, s, "export_html")) return .export_html;
    if (std.mem.eql(u8, s, "fork")) return .fork;
    if (std.mem.eql(u8, s, "clone")) return .clone;
    if (std.mem.eql(u8, s, "new_session")) return .new_session;
    if (std.mem.eql(u8, s, "get_commands")) return .get_commands;
    if (std.mem.eql(u8, s, "list_sessions")) return .list_sessions;
    if (std.mem.eql(u8, s, "get_skills")) return .get_skills;
    if (std.mem.eql(u8, s, "reload")) return .reload;
    if (std.mem.eql(u8, s, "set_tools")) return .set_tools;
    if (std.mem.eql(u8, s, "get_usage")) return .get_usage;
    if (std.mem.eql(u8, s, "stream_delta")) return .stream_delta;
    if (std.mem.eql(u8, s, "tool_start")) return .tool_start;
    if (std.mem.eql(u8, s, "tool_end")) return .tool_end;
    if (std.mem.eql(u8, s, "error_event")) return .error_event;
    if (std.mem.eql(u8, s, "session_info")) return .session_info;
    if (std.mem.eql(u8, s, "model_change")) return .model_change;
    if (std.mem.eql(u8, s, "compaction")) return .compaction;
    if (std.mem.eql(u8, s, "auth_status")) return .auth_status;
    if (std.mem.eql(u8, s, "extension_hook")) return .extension_hook;
    if (std.mem.eql(u8, s, "mcp_tools")) return .mcp_tools;
    if (std.mem.eql(u8, s, "server_health")) return .server_health;
    if (std.mem.eql(u8, s, "index_rebuild")) return .index_rebuild;
    if (std.mem.eql(u8, s, "theme_apply")) return .theme_apply;
    if (std.mem.eql(u8, s, "eval_run")) return .eval_run;
    if (std.mem.eql(u8, s, "ext_msg_6_0")) return .ext_msg_6_0;
    if (std.mem.eql(u8, s, "ext_msg_6_1")) return .ext_msg_6_1;
    if (std.mem.eql(u8, s, "ext_msg_6_2")) return .ext_msg_6_2;
    if (std.mem.eql(u8, s, "ext_msg_6_3")) return .ext_msg_6_3;
    if (std.mem.eql(u8, s, "ext_msg_6_4")) return .ext_msg_6_4;
    if (std.mem.eql(u8, s, "ext_msg_6_5")) return .ext_msg_6_5;
    if (std.mem.eql(u8, s, "ext_msg_6_6")) return .ext_msg_6_6;
    if (std.mem.eql(u8, s, "ext_msg_6_7")) return .ext_msg_6_7;
    if (std.mem.eql(u8, s, "ext_msg_6_8")) return .ext_msg_6_8;
    if (std.mem.eql(u8, s, "ext_msg_6_9")) return .ext_msg_6_9;
    if (std.mem.eql(u8, s, "ext_msg_6_10")) return .ext_msg_6_10;
    if (std.mem.eql(u8, s, "ext_msg_6_11")) return .ext_msg_6_11;
    if (std.mem.eql(u8, s, "ext_msg_6_12")) return .ext_msg_6_12;
    if (std.mem.eql(u8, s, "ext_msg_6_13")) return .ext_msg_6_13;
    if (std.mem.eql(u8, s, "ext_msg_6_14")) return .ext_msg_6_14;
    if (std.mem.eql(u8, s, "ext_msg_6_15")) return .ext_msg_6_15;
    if (std.mem.eql(u8, s, "ext_msg_6_16")) return .ext_msg_6_16;
    if (std.mem.eql(u8, s, "ext_msg_6_17")) return .ext_msg_6_17;
    if (std.mem.eql(u8, s, "ext_msg_6_18")) return .ext_msg_6_18;
    if (std.mem.eql(u8, s, "ext_msg_6_19")) return .ext_msg_6_19;
    if (std.mem.eql(u8, s, "ext_msg_6_20")) return .ext_msg_6_20;
    if (std.mem.eql(u8, s, "ext_msg_6_21")) return .ext_msg_6_21;
    if (std.mem.eql(u8, s, "ext_msg_6_22")) return .ext_msg_6_22;
    if (std.mem.eql(u8, s, "ext_msg_6_23")) return .ext_msg_6_23;
    if (std.mem.eql(u8, s, "ext_msg_6_24")) return .ext_msg_6_24;
    if (std.mem.eql(u8, s, "ext_msg_6_25")) return .ext_msg_6_25;
    if (std.mem.eql(u8, s, "ext_msg_6_26")) return .ext_msg_6_26;
    if (std.mem.eql(u8, s, "ext_msg_6_27")) return .ext_msg_6_27;
    if (std.mem.eql(u8, s, "ext_msg_6_28")) return .ext_msg_6_28;
    if (std.mem.eql(u8, s, "ext_msg_6_29")) return .ext_msg_6_29;
    if (std.mem.eql(u8, s, "ext_msg_6_30")) return .ext_msg_6_30;
    if (std.mem.eql(u8, s, "ext_msg_6_31")) return .ext_msg_6_31;
    if (std.mem.eql(u8, s, "ext_msg_6_32")) return .ext_msg_6_32;
    if (std.mem.eql(u8, s, "ext_msg_6_33")) return .ext_msg_6_33;
    if (std.mem.eql(u8, s, "ext_msg_6_34")) return .ext_msg_6_34;
    if (std.mem.eql(u8, s, "ext_msg_6_35")) return .ext_msg_6_35;
    if (std.mem.eql(u8, s, "ext_msg_6_36")) return .ext_msg_6_36;
    if (std.mem.eql(u8, s, "ext_msg_6_37")) return .ext_msg_6_37;
    if (std.mem.eql(u8, s, "ext_msg_6_38")) return .ext_msg_6_38;
    if (std.mem.eql(u8, s, "ext_msg_6_39")) return .ext_msg_6_39;
    return null;
}

pub fn encodeEnvelope(gpa: std.mem.Allocator, id: []const u8, kind: MessageKind, payload: []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"type\":");
    try std.json.Stringify.value(kindName(kind), .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    if (payload.len > 0 and payload[0] == '{') {
        try aw.writer.writeAll(payload);
    } else {
        try std.json.Stringify.value(payload, .{}, &aw.writer);
    }
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}

pub fn validateEnvelopeJson(json_text: []const u8) bool {
    if (json_text.len < 2) return false;
    if (json_text[0] != '{') return false;
    if (std.mem.indexOf(u8, json_text, "\"type\"") == null) return false;
    return true;
}

pub fn handle_ext_msg_6_0(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":0,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_0(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_0(gpa, payload);
}

pub fn handle_ext_msg_6_1(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":1,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_1(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_1(gpa, payload);
}

pub fn handle_ext_msg_6_2(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":2,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_2(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_2(gpa, payload);
}

pub fn handle_ext_msg_6_3(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":3,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_3(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_3(gpa, payload);
}

pub fn handle_ext_msg_6_4(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":4,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_4(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_4(gpa, payload);
}

pub fn handle_ext_msg_6_5(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":5,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_5(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_5(gpa, payload);
}

pub fn handle_ext_msg_6_6(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":6,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_6(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_6(gpa, payload);
}

pub fn handle_ext_msg_6_7(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":7,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_7(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_7(gpa, payload);
}

pub fn handle_ext_msg_6_8(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":8,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_8(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_8(gpa, payload);
}

pub fn handle_ext_msg_6_9(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":9,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_9(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_9(gpa, payload);
}

pub fn handle_ext_msg_6_10(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":10,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_10(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_10(gpa, payload);
}

pub fn handle_ext_msg_6_11(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":11,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_11(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_11(gpa, payload);
}

pub fn handle_ext_msg_6_12(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":12,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_12(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_12(gpa, payload);
}

pub fn handle_ext_msg_6_13(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":13,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_13(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_13(gpa, payload);
}

pub fn handle_ext_msg_6_14(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":14,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_14(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_14(gpa, payload);
}

pub fn handle_ext_msg_6_15(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":15,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_15(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_15(gpa, payload);
}

pub fn handle_ext_msg_6_16(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":16,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_16(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_16(gpa, payload);
}

pub fn handle_ext_msg_6_17(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":17,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_17(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_17(gpa, payload);
}

pub fn handle_ext_msg_6_18(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":18,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_18(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_18(gpa, payload);
}

pub fn handle_ext_msg_6_19(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":19,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_19(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_19(gpa, payload);
}

pub fn handle_ext_msg_6_20(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":20,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_20(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_20(gpa, payload);
}

pub fn handle_ext_msg_6_21(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":21,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_21(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_21(gpa, payload);
}

pub fn handle_ext_msg_6_22(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":22,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_22(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_22(gpa, payload);
}

pub fn handle_ext_msg_6_23(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":23,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_23(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_23(gpa, payload);
}

pub fn handle_ext_msg_6_24(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":24,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_24(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_24(gpa, payload);
}

pub fn handle_ext_msg_6_25(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":25,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_25(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_25(gpa, payload);
}

pub fn handle_ext_msg_6_26(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":26,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_26(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_26(gpa, payload);
}

pub fn handle_ext_msg_6_27(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":27,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_27(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_27(gpa, payload);
}

pub fn handle_ext_msg_6_28(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":28,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_28(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_28(gpa, payload);
}

pub fn handle_ext_msg_6_29(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":29,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_29(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_29(gpa, payload);
}

pub fn handle_ext_msg_6_30(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":30,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_30(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_30(gpa, payload);
}

pub fn handle_ext_msg_6_31(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":31,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_31(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_31(gpa, payload);
}

pub fn handle_ext_msg_6_32(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":32,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_32(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_32(gpa, payload);
}

pub fn handle_ext_msg_6_33(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":33,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_33(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_33(gpa, payload);
}

pub fn handle_ext_msg_6_34(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":34,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_34(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_34(gpa, payload);
}

pub fn handle_ext_msg_6_35(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":35,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_35(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_35(gpa, payload);
}

pub fn handle_ext_msg_6_36(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":36,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_36(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_36(gpa, payload);
}

pub fn handle_ext_msg_6_37(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":37,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_37(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_37(gpa, payload);
}

pub fn handle_ext_msg_6_38(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":38,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_38(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_38(gpa, payload);
}

pub fn handle_ext_msg_6_39(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"shard\":6,\"msg\":39,\"len\":{d}}}", .{payload.len});
}

pub fn dispatch_ext_6_39(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len == 0) return try gpa.dupe(u8, "{\"error\":\"empty\"}");
    return handle_ext_msg_6_39(gpa, payload);
}

pub fn dispatchByName(gpa: std.mem.Allocator, name: []const u8, payload: []const u8) !?[]u8 {
    if (std.mem.eql(u8, name, "ext_msg_6_0")) return try dispatch_ext_6_0(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_1")) return try dispatch_ext_6_1(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_2")) return try dispatch_ext_6_2(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_3")) return try dispatch_ext_6_3(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_4")) return try dispatch_ext_6_4(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_5")) return try dispatch_ext_6_5(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_6")) return try dispatch_ext_6_6(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_7")) return try dispatch_ext_6_7(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_8")) return try dispatch_ext_6_8(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_9")) return try dispatch_ext_6_9(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_10")) return try dispatch_ext_6_10(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_11")) return try dispatch_ext_6_11(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_12")) return try dispatch_ext_6_12(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_13")) return try dispatch_ext_6_13(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_14")) return try dispatch_ext_6_14(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_15")) return try dispatch_ext_6_15(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_16")) return try dispatch_ext_6_16(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_17")) return try dispatch_ext_6_17(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_18")) return try dispatch_ext_6_18(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_19")) return try dispatch_ext_6_19(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_20")) return try dispatch_ext_6_20(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_21")) return try dispatch_ext_6_21(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_22")) return try dispatch_ext_6_22(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_23")) return try dispatch_ext_6_23(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_24")) return try dispatch_ext_6_24(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_25")) return try dispatch_ext_6_25(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_26")) return try dispatch_ext_6_26(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_27")) return try dispatch_ext_6_27(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_28")) return try dispatch_ext_6_28(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_29")) return try dispatch_ext_6_29(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_30")) return try dispatch_ext_6_30(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_31")) return try dispatch_ext_6_31(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_32")) return try dispatch_ext_6_32(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_33")) return try dispatch_ext_6_33(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_34")) return try dispatch_ext_6_34(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_35")) return try dispatch_ext_6_35(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_36")) return try dispatch_ext_6_36(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_37")) return try dispatch_ext_6_37(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_38")) return try dispatch_ext_6_38(gpa, payload);
    if (std.mem.eql(u8, name, "ext_msg_6_39")) return try dispatch_ext_6_39(gpa, payload);
    return null;
}

test "protocol shard 6 kind roundtrip" {
    const k = parseKind("prompt").?;
    try std.testing.expectEqualStrings("prompt", kindName(k));
    const ek = parseKind("ext_msg_6_0").?;
    try std.testing.expectEqualStrings("ext_msg_6_0", kindName(ek));
    const gpa = std.testing.allocator;
    const out = try handle_ext_msg_6_0(gpa, "x");
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ok\":true") != null);
    const env = try encodeEnvelope(gpa, "id1", .ping, "{}");
    defer gpa.free(env);
    try std.testing.expect(validateEnvelopeJson(env));
}

