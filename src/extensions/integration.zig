//! Adapter between the out-of-process extension host and the dependency-free
//! agent callback interface.
const std = @import("std");
const host_mod = @import("host.zig");
const actions_mod = @import("actions.zig");
const agent_loop = @import("../agent/loop.zig");
const agent_tools = @import("../agent/tools.zig");
const session_mod = @import("../agent/session.zig");
const compaction_mod = @import("../agent/compaction.zig");
const branch_summary_mod = @import("../agent/branch_summary.zig");
const summarization_mod = @import("../agent/summarization.zig");
const ai = @import("../ai/root.zig");
const file_permissions = @import("../file_permissions.zig");
const ui = @import("ui.zig");

pub const Bridge = struct {
    host: *host_mod.Host,
    action_queue: actions_mod.Queue,
    abort_flag: ?*bool = null,

    pub fn init(host: *host_mod.Host) Bridge {
        return .{ .host = host, .action_queue = actions_mod.Queue.init(host.gpa, host.io) };
    }

    pub fn setAbortFlag(self: *Bridge, abort_flag: ?*bool) void {
        self.abort_flag = abort_flag;
    }

    fn executeHook(self: *Bridge, hook: []const u8, payload: []const u8) !host_mod.EmitResult {
        return self.host.executeHookWithAbort(hook, payload, self.abort_flag);
    }

    pub fn uiPromptEvent(self: *Bridge, event: ui.PromptEvent, method: []const u8) void {
        const hook = if (event == .start) "ui_prompt_start" else "ui_prompt_end";
        if (!self.host.hasHook(hook)) return;
        var payload: std.Io.Writer.Allocating = .init(self.host.gpa);
        defer payload.deinit();
        payload.writer.writeAll("{\"type\":") catch return;
        std.json.Stringify.value(hook, .{}, &payload.writer) catch return;
        payload.writer.writeAll(",\"method\":") catch return;
        std.json.Stringify.value(method, .{}, &payload.writer) catch return;
        payload.writer.writeAll("}") catch return;
        var emitted = self.executeHook(hook, payload.written()) catch return;
        emitted.deinit(self.host.gpa);
    }

    pub fn deinit(self: *Bridge) void {
        self.action_queue.deinit();
        self.* = undefined;
    }

    pub fn drainActions(self: *Bridge) ![]actions_mod.Record {
        return self.action_queue.drain();
    }

    pub fn queuedActionCount(self: *Bridge) usize {
        return self.action_queue.count();
    }

    /// Transfer command/shortcut action ownership into the same FIFO used by
    /// lifecycle hooks and parallel extension-tool callbacks.
    pub fn enqueueActions(self: *Bridge, batch: *actions_mod.Batch) !void {
        try self.action_queue.enqueue(batch);
    }

    fn queueEmitted(self: *Bridge, emitted: *host_mod.EmitResult) !void {
        for (emitted.responses) |*response| try self.action_queue.enqueue(&response.actions);
    }

    /// Forward the native agent event stream into upstream-style extension
    /// lifecycle handlers. Renderer events still go to their ordinary consumer;
    /// this observer is an additional, isolated fan-out and never aborts a run.
    pub fn onAgentEvent(ctx: ?*anyopaque, event: agent_loop.AgentEvent) void {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        const hook = eventHookName(event.kind) orelse return;
        if (!self.host.hasHook(hook)) return;
        const payload = eventPayload(self.host.gpa, event, hook) catch return;
        defer self.host.gpa.free(payload);
        var emitted = self.executeHook(hook, payload) catch return;
        defer emitted.deinit(self.host.gpa);
        self.queueEmitted(&emitted) catch return;
    }

    pub fn beforePrompt(ctx: ?*anyopaque, gpa: std.mem.Allocator, prompt: []const u8) anyerror!?[]u8 {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        const payload = try object1(gpa, "prompt", prompt);
        defer gpa.free(payload);
        var emitted = try self.executeHook("before_prompt", payload);
        defer emitted.deinit(gpa);
        try self.queueEmitted(&emitted);

        var current: ?[]u8 = null;
        errdefer if (current) |owned| gpa.free(owned);
        for (emitted.responses) |response| {
            const replacement = parseStringField(gpa, response.json, "prompt") catch continue;
            if (replacement) |owned| {
                if (current) |old| gpa.free(old);
                current = owned;
            }
        }
        return current;
    }

    pub fn beforeAgentStart(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        cwd: []const u8,
        prompt: []const u8,
        system_prompt: []const u8,
        images: []const agent_loop.UserImage,
    ) anyerror!?agent_loop.BeforeAgentStartResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        if (!self.host.hasHook("before_agent_start")) return null;
        const payload = try beforeAgentStartPayload(gpa, cwd, prompt, system_prompt, images);
        defer gpa.free(payload);
        var emitted = try self.executeHook("before_agent_start", payload);
        defer emitted.deinit(gpa);
        try self.queueEmitted(&emitted);

        var replacement: ?[]u8 = null;
        errdefer if (replacement) |owned| gpa.free(owned);
        var messages: std.ArrayList(agent_loop.ExtensionContextMessage) = .empty;
        errdefer {
            for (messages.items) |*message| message.deinit(gpa);
            messages.deinit(gpa);
        }

        for (emitted.responses) |response| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.json, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            if (parsed.value.object.get("systemPrompt")) |value| {
                if (value == .string) {
                    const next = try gpa.dupe(u8, value.string);
                    if (replacement) |old| gpa.free(old);
                    replacement = next;
                }
            }
            if (parsed.value.object.get("message")) |value| {
                if (try parseContextMessage(gpa, value)) |message| try messages.append(gpa, message);
            }
            if (parsed.value.object.get("messages")) |value| {
                if (value == .array) {
                    for (value.array.items) |message_value| {
                        if (try parseContextMessage(gpa, message_value)) |message| try messages.append(gpa, message);
                    }
                }
            }
        }

        if (replacement == null and messages.items.len == 0) return null;
        const owned_messages = try messages.toOwnedSlice(gpa);
        const result = agent_loop.BeforeAgentStartResult{
            .system_prompt = replacement,
            .messages = owned_messages,
        };
        replacement = null;
        return result;
    }

    pub fn transformContext(
        ctx: ?*anyopaque,
        scratch: std.mem.Allocator,
        messages: []const ai.ChatMessage,
    ) anyerror![]const ai.ChatMessage {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        if (!self.host.hasHook("context")) return messages;
        const payload = try contextPayload(self.host.gpa, messages);
        defer self.host.gpa.free(payload);
        var emitted = try self.executeHook("context", payload);
        defer emitted.deinit(self.host.gpa);
        try self.queueEmitted(&emitted);

        var current = messages;
        for (emitted.responses) |response| {
            var parsed = std.json.parseFromSlice(std.json.Value, self.host.gpa, response.json, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            const value = parsed.value.object.get("messages") orelse continue;
            if (value != .array) continue;
            current = try parseContextProjection(scratch, value, messages);
        }
        return current;
    }

    pub fn beforeTool(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        tool_name: []const u8,
        tool_call_id: []const u8,
        args_json: []const u8,
    ) anyerror!?agent_loop.BeforeToolResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        const payload = try beforeToolPayload(gpa, tool_name, tool_call_id, args_json);
        defer gpa.free(payload);
        var emitted = try self.executeHook("before_tool", payload);
        defer emitted.deinit(gpa);
        try self.queueEmitted(&emitted);

        var replacement: ?[]u8 = null;
        errdefer if (replacement) |owned| gpa.free(owned);
        var reason: ?[]u8 = null;
        errdefer if (reason) |owned| gpa.free(owned);
        var block = false;
        var changed = false;
        for (emitted.responses) |response| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.json, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            if (parsed.value.object.get("arguments") orelse parsed.value.object.get("args")) |value| {
                const serialized = try stringifyJsonValue(gpa, value);
                if (replacement) |old| gpa.free(old);
                replacement = serialized;
                changed = true;
            }
            if (parsed.value.object.get("block")) |value| {
                if (value == .bool) {
                    block = value.bool;
                    changed = true;
                }
            }
            if (parsed.value.object.get("reason")) |value| {
                if (value == .string) {
                    if (reason) |old| gpa.free(old);
                    reason = try gpa.dupe(u8, value.string);
                    changed = true;
                }
            }
        }
        if (!changed) return null;
        const out = agent_loop.BeforeToolResult{ .arguments_json = replacement, .block = block, .reason = reason };
        replacement = null;
        reason = null;
        return out;
    }

    pub fn afterTool(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        tool_name: []const u8,
        tool_call_id: []const u8,
        args_json: []const u8,
        raw: *const agent_tools.ToolResult,
    ) anyerror!?agent_loop.ToolResultOverride {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        const payload = try toolPayload(gpa, tool_name, tool_call_id, args_json, raw);
        defer gpa.free(payload);
        var emitted = try self.executeHook("after_tool", payload);
        defer emitted.deinit(gpa);
        try self.queueEmitted(&emitted);

        var content_text: ?[]u8 = null;
        errdefer if (content_text) |value| gpa.free(value);
        var image_b64: ?[]u8 = null;
        errdefer if (image_b64) |value| gpa.free(value);
        var image_mime: ?[]u8 = null;
        errdefer if (image_mime) |value| gpa.free(value);
        var images: []agent_tools.ToolImage = &.{};
        errdefer agent_tools.deinitImages(gpa, images);
        var details_json: ?[]u8 = null;
        errdefer if (details_json) |value| gpa.free(value);
        var usage: ?agent_tools.ToolUsage = null;
        var added_tool_names: ?[]const []const u8 = null;
        errdefer if (added_tool_names) |values| deinitStringList(gpa, values);
        var content_changed = false;
        var details_changed = false;
        var current_error = raw.is_error;
        var current_terminate: ?bool = null;
        var changed = false;

        for (emitted.responses) |response| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.json, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            if (parsed.value.object.get("content")) |value| {
                var replacement = parseHookToolContent(gpa, value) catch continue;
                if (content_text) |old| gpa.free(old);
                if (image_b64) |old| gpa.free(old);
                if (image_mime) |old| gpa.free(old);
                agent_tools.deinitImages(gpa, images);
                content_text = replacement.text;
                image_b64 = replacement.image_b64;
                image_mime = replacement.image_mime;
                images = replacement.images;
                replacement = .{ .text = &.{} };
                content_changed = true;
                changed = true;
            }
            if (parsed.value.object.get("details")) |value| {
                if (details_json) |old| gpa.free(old);
                details_json = if (value == .null) null else try stringifyJsonValue(gpa, value);
                details_changed = true;
                changed = true;
            }
            if (parsed.value.object.get("usage")) |value| {
                usage = try parseToolUsage(value);
                changed = true;
            }
            if (parsed.value.object.get("addedToolNames")) |value| {
                if (added_tool_names) |old| deinitStringList(gpa, old);
                added_tool_names = try parseStringList(gpa, value);
                changed = true;
            }
            if (parsed.value.object.get("isError")) |value| {
                if (value == .bool) {
                    current_error = value.bool;
                    changed = true;
                }
            }
            if (parsed.value.object.get("terminate")) |value| {
                if (value == .bool) {
                    current_terminate = value.bool;
                    changed = true;
                }
            }
        }
        if (!changed) return null;

        const final_content = if (content_changed) content_text.? else try gpa.dupe(u8, raw.content);
        if (content_changed) content_text = null;
        errdefer gpa.free(final_content);
        const final_image_b64 = if (content_changed)
            image_b64
        else if (raw.image_b64) |value|
            try gpa.dupe(u8, value)
        else
            null;
        if (content_changed) image_b64 = null;
        errdefer if (final_image_b64) |value| gpa.free(value);
        const final_image_mime = if (content_changed)
            image_mime
        else if (raw.image_mime) |value|
            try gpa.dupe(u8, value)
        else
            null;
        if (content_changed) image_mime = null;
        errdefer if (final_image_mime) |value| gpa.free(value);
        const final_images = if (content_changed) images else try agent_tools.cloneImages(gpa, raw.images);
        if (content_changed) images = &.{};
        errdefer agent_tools.deinitImages(gpa, final_images);
        const final_details = if (details_changed)
            details_json
        else if (raw.details_json) |value|
            try gpa.dupe(u8, value)
        else
            null;
        if (details_changed) details_json = null;

        const result = agent_loop.ToolResultOverride{
            .content = final_content,
            .is_error = current_error,
            .image_b64 = final_image_b64,
            .image_mime = final_image_mime,
            .images = final_images,
            .details_json = final_details,
            .usage = usage,
            .added_tool_names = added_tool_names,
            .terminate = current_terminate,
        };
        added_tool_names = null;
        return result;
    }

    pub fn toolSchemasJson(self: *Bridge, gpa: std.mem.Allocator, filter: agent_tools.ToolFilter) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        try out.writer.writeByte('[');
        var first = true;
        for (self.host.extensions.items) |ext| {
            for (ext.tools) |tool| {
                if (!filter.isEnabled(tool.name)) continue;
                if (!first) try out.writer.writeByte(',');
                first = false;
                try out.writer.writeAll("{\"type\":\"function\",\"function\":{\"name\":");
                try std.json.Stringify.value(tool.name, .{}, &out.writer);
                try out.writer.writeAll(",\"description\":");
                try std.json.Stringify.value(tool.description, .{}, &out.writer);
                try out.writer.writeAll(",\"parameters\":");
                try out.writer.writeAll(tool.parameters_json);
                try out.writer.writeAll("}}");
            }
        }
        try out.writer.writeByte(']');
        return try out.toOwnedSlice();
    }

    pub fn toolExecutionMode(ctx: ?*anyopaque, name: []const u8) agent_loop.ToolExecutionMode {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        for (self.host.extensions.items) |ext| {
            for (ext.tools) |tool| {
                if (!std.mem.eql(u8, tool.name, name)) continue;
                return switch (tool.execution_mode) {
                    .parallel => .parallel,
                    .sequential => .sequential,
                };
            }
        }
        return .parallel;
    }

    pub fn hasExecutableTool(ctx: ?*anyopaque, name: []const u8) bool {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        return self.host.hasTool(name);
    }

    pub fn prepareToolArguments(ctx: ?*anyopaque, gpa: std.mem.Allocator, name: []const u8, arguments_json: []const u8) anyerror!?[]u8 {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        const prepared = (try self.host.prepareToolArguments(name, arguments_json)) orelse return null;
        defer self.host.gpa.free(prepared);
        return try gpa.dupe(u8, prepared);
    }

    pub fn executeTool(ctx: ?*anyopaque, gpa: std.mem.Allocator, name: []const u8, arguments_json: []const u8) anyerror!?agent_tools.ToolResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        var output = (try self.host.executeTool(name, arguments_json)) orelse return null;
        defer output.deinit(self.host.gpa);
        return try self.transferToolOutput(gpa, &output);
    }

    pub fn executeToolStreaming(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        name: []const u8,
        arguments_json: []const u8,
        progress_fn: agent_loop.ExternalToolProgressFn,
        progress_ctx: ?*anyopaque,
    ) anyerror!?agent_tools.ToolResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        var adapter = LiveProgressAdapter{
            .gpa = self.host.gpa,
            .callback = progress_fn,
            .context = progress_ctx,
        };
        var output = (try self.host.executeToolStreaming(name, arguments_json, LiveProgressAdapter.forward, &adapter)) orelse return null;
        defer output.deinit(self.host.gpa);
        return try self.transferToolOutput(gpa, &output);
    }

    /// Full-fidelity dispatcher used by the agent loop. Unlike the compatibility
    /// callback above, this preserves the provider's call ID and live abort flag.
    pub fn executeToolCallStreaming(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        tool_call_id: []const u8,
        name: []const u8,
        arguments_json: []const u8,
        progress_fn: agent_loop.ExternalToolProgressFn,
        progress_ctx: ?*anyopaque,
        abort_flag: ?*bool,
    ) anyerror!?agent_tools.ToolResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        var adapter = LiveProgressAdapter{
            .gpa = self.host.gpa,
            .callback = progress_fn,
            .context = progress_ctx,
        };
        var output = (try self.host.executeToolCallStreaming(tool_call_id, name, arguments_json, abort_flag, LiveProgressAdapter.forward, &adapter)) orelse return null;
        defer output.deinit(self.host.gpa);
        return try self.transferToolOutput(gpa, &output);
    }

    fn transferToolOutput(self: *Bridge, gpa: std.mem.Allocator, output: *host_mod.ToolOutput) !?agent_tools.ToolResult {
        try self.action_queue.enqueue(&output.actions);
        if (output.delegate_builtin) return null;

        // The agent may execute external tools in a per-worker arena. The host
        // owns script results with its long-lived allocator, so transfer by
        // cloning into the allocator supplied by the agent rather than assuming
        // both allocators are identical. This also makes parallel tool results
        // disappear with their worker arena after finalization.
        const content = try gpa.dupe(u8, output.content);
        errdefer gpa.free(content);
        var image_set = try cloneHostImageSet(gpa, output.image_b64, output.image_mime, output.images);
        errdefer image_set.deinit(gpa);
        var details_json: ?[]u8 = null;
        errdefer if (details_json) |value| gpa.free(value);
        if (output.details_json) |value| details_json = try gpa.dupe(u8, value);
        const added_tool_names = try cloneStringList(gpa, output.added_tool_names);
        errdefer deinitStringList(gpa, added_tool_names);
        const updates = try cloneToolUpdates(gpa, output.updates);
        errdefer deinitToolUpdates(gpa, updates);
        return .{
            .content = content,
            .is_error = output.is_error,
            .image_b64 = image_set.image_b64,
            .image_mime = image_set.image_mime,
            .images = image_set.images,
            .details_json = details_json,
            .usage = if (output.usage) |usage| convertToolUsage(usage) else null,
            .added_tool_names = added_tool_names,
            .updates = updates,
            .terminate = output.terminate,
        };
    }

    pub fn beforeCompact(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        sess: *const session_mod.Session,
        preparation: compaction_mod.HookPreparation,
    ) anyerror!?compaction_mod.BeforeHookResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        if (!self.host.hasHook("session_before_compact")) return null;
        const payload = try compactionBeforePayload(gpa, sess, preparation);
        defer gpa.free(payload);
        var emitted = try self.executeHook("session_before_compact", payload);
        defer emitted.deinit(self.host.gpa);
        try self.queueEmitted(&emitted);

        var result: compaction_mod.BeforeHookResult = .{};
        errdefer result.deinit(gpa);
        var changed = false;
        for (emitted.responses) |response| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.json, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            if (parsed.value.object.get("cancel")) |value| {
                if (value == .bool and value.bool) {
                    result.cancel = true;
                    changed = true;
                    break;
                }
            }
            const replacement_value = parsed.value.object.get("compaction") orelse continue;
            const replacement = parseCompactionOverride(gpa, replacement_value) catch continue;
            if (result.compaction) |*old| old.deinit(gpa);
            result.compaction = replacement;
            changed = true;
        }
        if (!changed) return null;
        return result;
    }

    pub fn afterCompact(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        compaction_entry: *const session_mod.SessionEntry,
        reason: summarization_mod.Reason,
        will_retry: bool,
        from_extension: bool,
    ) anyerror!void {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        if (!self.host.hasHook("session_compact")) return;
        const payload = try compactionAfterPayload(gpa, compaction_entry, reason, will_retry, from_extension);
        defer gpa.free(payload);
        var emitted = try self.executeHook("session_compact", payload);
        defer emitted.deinit(self.host.gpa);
        try self.queueEmitted(&emitted);
    }

    pub fn beforeTree(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        sess: *const session_mod.Session,
        preparation: branch_summary_mod.HookPreparation,
    ) anyerror!?branch_summary_mod.BeforeHookResult {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        if (!self.host.hasHook("session_before_tree")) return null;
        const payload = try treeBeforePayload(gpa, sess, preparation);
        defer gpa.free(payload);
        var emitted = try self.executeHook("session_before_tree", payload);
        defer emitted.deinit(self.host.gpa);
        try self.queueEmitted(&emitted);

        var result: branch_summary_mod.BeforeHookResult = .{};
        errdefer result.deinit(gpa);
        var changed = false;
        for (emitted.responses) |response| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.json, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            if (parsed.value.object.get("cancel")) |value| {
                if (value == .bool and value.bool) {
                    result.cancel = true;
                    changed = true;
                    break;
                }
            }
            if (parsed.value.object.get("summary")) |value| {
                const summary = parseTreeSummaryOverride(gpa, value) catch null;
                if (summary) |owned| {
                    if (result.summary) |*old| old.deinit(gpa);
                    result.summary = owned;
                    changed = true;
                }
            }
            if (parsed.value.object.get("customInstructions")) |value| {
                if (value == .string) {
                    if (result.custom_instructions) |old| gpa.free(old);
                    result.custom_instructions = try gpa.dupe(u8, value.string);
                    changed = true;
                }
            }
            if (parsed.value.object.get("replaceInstructions")) |value| {
                if (value == .bool) {
                    result.replace_instructions = value.bool;
                    changed = true;
                }
            }
            if (parsed.value.object.get("label")) |value| {
                if (value == .string) {
                    if (result.label) |old| gpa.free(old);
                    result.label = try gpa.dupe(u8, value.string);
                    changed = true;
                }
            }
        }
        if (!changed) return null;
        return result;
    }

    pub fn afterTree(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        new_leaf_id: ?[]const u8,
        old_leaf_id: ?[]const u8,
        summary_entry: ?*const session_mod.SessionEntry,
        from_extension: bool,
    ) anyerror!void {
        const self: *Bridge = @ptrCast(@alignCast(ctx.?));
        if (!self.host.hasHook("session_tree")) return;
        const payload = try treeAfterPayload(gpa, new_leaf_id, old_leaf_id, summary_entry, from_extension);
        defer gpa.free(payload);
        var emitted = try self.executeHook("session_tree", payload);
        defer emitted.deinit(self.host.gpa);
        try self.queueEmitted(&emitted);
    }

    pub fn sessionStart(self: *Bridge, gpa: std.mem.Allocator, cwd: []const u8, session_id: []const u8, reason: []const u8) !void {
        const payload = try lifecyclePayload(gpa, cwd, session_id, reason);
        defer gpa.free(payload);
        var emitted = try self.executeHook("session_start", payload);
        defer emitted.deinit(gpa);
        try self.queueEmitted(&emitted);
    }

    pub fn sessionShutdown(self: *Bridge, gpa: std.mem.Allocator, cwd: []const u8, session_id: []const u8, reason: []const u8) !void {
        const payload = try lifecyclePayload(gpa, cwd, session_id, reason);
        defer gpa.free(payload);
        var emitted = try self.executeHook("session_shutdown", payload);
        defer emitted.deinit(gpa);
        try self.queueEmitted(&emitted);
    }
};

const OwnedImageSet = struct {
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    images: []agent_tools.ToolImage = &.{},

    fn deinit(self: *OwnedImageSet, gpa: std.mem.Allocator) void {
        if (self.image_b64) |value| gpa.free(value);
        if (self.image_mime) |value| gpa.free(value);
        agent_tools.deinitImages(gpa, self.images);
        self.* = undefined;
    }
};

fn cloneHostImageSet(
    gpa: std.mem.Allocator,
    legacy_b64: ?[]const u8,
    legacy_mime: ?[]const u8,
    source: []const host_mod.ToolImage,
) !OwnedImageSet {
    var out: OwnedImageSet = .{};
    errdefer out.deinit(gpa);
    if (source.len > 0) {
        out.image_b64 = try gpa.dupe(u8, source[0].data_b64);
        out.image_mime = try gpa.dupe(u8, source[0].mime_type);
        if (source.len > 1) {
            out.images = try gpa.alloc(agent_tools.ToolImage, source.len - 1);
            var initialized: usize = 0;
            errdefer for (out.images[0..initialized]) |*image| image.deinit(gpa);
            for (source[1..], 0..) |image, index| {
                out.images[index] = .{
                    .data_b64 = try gpa.dupe(u8, image.data_b64),
                    .mime_type = try gpa.dupe(u8, image.mime_type),
                };
                initialized += 1;
            }
        }
    } else if (legacy_b64) |value| {
        out.image_b64 = try gpa.dupe(u8, value);
        out.image_mime = try gpa.dupe(u8, legacy_mime orelse "image/png");
    }
    return out;
}

fn borrowedHostExtraImages(gpa: std.mem.Allocator, source: []const host_mod.ToolImage) ![]agent_tools.ToolImage {
    if (source.len <= 1) return &.{};
    const out = try gpa.alloc(agent_tools.ToolImage, source.len - 1);
    for (source[1..], 0..) |image, index| {
        out[index] = .{ .data_b64 = image.data_b64, .mime_type = image.mime_type };
    }
    return out;
}

const LiveProgressAdapter = struct {
    gpa: std.mem.Allocator,
    callback: agent_loop.ExternalToolProgressFn,
    context: ?*anyopaque,

    fn forward(raw_ctx: ?*anyopaque, update: *const host_mod.ToolUpdate) anyerror!void {
        const self: *LiveProgressAdapter = @ptrCast(@alignCast(raw_ctx.?));
        const extra_images = borrowedHostExtraImages(self.gpa, update.images) catch return;
        defer if (extra_images.len > 0) self.gpa.free(extra_images);
        self.callback(self.context, .{
            .content = update.content,
            .is_error = update.is_error,
            .image_b64 = if (update.images.len > 0) update.images[0].data_b64 else update.image_b64,
            .image_mime = if (update.images.len > 0) update.images[0].mime_type else update.image_mime,
            .images = extra_images,
            .details_json = update.details_json,
            .usage = if (update.usage) |usage| convertToolUsage(usage) else null,
            .added_tool_names = update.added_tool_names,
            .defer_observer = true,
        });
    }
};

fn cloneToolUpdates(gpa: std.mem.Allocator, source: []const host_mod.ToolUpdate) ![]agent_tools.ToolUpdate {
    if (source.len == 0) return &.{};
    const out = try gpa.alloc(agent_tools.ToolUpdate, source.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |*update| update.deinit(gpa);
        gpa.free(out);
    }
    for (source, 0..) |update, index| {
        const content = try gpa.dupe(u8, update.content);
        errdefer gpa.free(content);
        var image_set = try cloneHostImageSet(gpa, update.image_b64, update.image_mime, update.images);
        errdefer image_set.deinit(gpa);
        const details_json = if (update.details_json) |value| try gpa.dupe(u8, value) else null;
        errdefer if (details_json) |value| gpa.free(value);
        const added_tool_names = try cloneStringList(gpa, update.added_tool_names);
        errdefer deinitStringList(gpa, added_tool_names);
        out[index] = .{
            .content = content,
            .is_error = update.is_error,
            .image_b64 = image_set.image_b64,
            .image_mime = image_set.image_mime,
            .images = image_set.images,
            .details_json = details_json,
            .usage = if (update.usage) |usage| convertToolUsage(usage) else null,
            .added_tool_names = added_tool_names,
            .observer_deferred = update.observer_deferred,
        };
        initialized += 1;
    }
    return out;
}

fn deinitToolUpdates(gpa: std.mem.Allocator, updates: []agent_tools.ToolUpdate) void {
    for (updates) |*update| update.deinit(gpa);
    if (updates.len > 0) gpa.free(updates);
}

fn cloneStringList(gpa: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    if (source.len == 0) return &.{};
    const out = try gpa.alloc([]const u8, source.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |value| gpa.free(value);
        gpa.free(out);
    }
    for (source, 0..) |value, index| {
        out[index] = try gpa.dupe(u8, value);
        initialized += 1;
    }
    return out;
}

fn deinitStringList(gpa: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| gpa.free(value);
    gpa.free(values);
}

fn convertToolUsage(source: host_mod.ToolUsage) agent_tools.ToolUsage {
    return .{
        .input = source.input,
        .output = source.output,
        .cache_read = source.cache_read,
        .cache_write = source.cache_write,
        .cache_write_1h = source.cache_write_1h,
        .reasoning = source.reasoning,
        .total_tokens = source.total_tokens,
        .cost = .{
            .input = source.cost.input,
            .output = source.cost.output,
            .cache_read = source.cost.cache_read,
            .cache_write = source.cost.cache_write,
            .total = source.cost.total,
        },
    };
}

fn eventHookName(kind: agent_loop.EventKind) ?[]const u8 {
    return switch (kind) {
        .agent_start => "agent_start",
        .agent_end => "agent_end",
        .turn_start => "turn_start",
        .turn_end => "turn_end",
        .message_start => "message_start",
        .message_update => "message_update",
        .message_end => "message_end",
        .tool_execution_start => "tool_execution_start",
        .tool_execution_update => "tool_execution_update",
        .tool_execution_end => "tool_execution_end",
        .session_compact_failed => "session_compact_failed",
        .auto_retry_start, .auto_retry_end, .summarization_retry_scheduled, .summarization_retry_attempt_start, .summarization_retry_finished => null,
        // The native loop emits these compatibility aliases in addition to the
        // canonical events above; forwarding them would invoke extensions twice.
        .user, .assistant, .tool_call, .tool_result, .done, .turn_limit => null,
    };
}

fn eventPayload(gpa: std.mem.Allocator, event: agent_loop.AgentEvent, hook: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":");
    try std.json.Stringify.value(hook, .{}, &out.writer);

    switch (event.kind) {
        .message_start, .message_update, .message_end => {
            const role = if (event.name.len > 0) event.name else "assistant";
            try out.writer.writeAll(",\"message\":{\"role\":");
            try std.json.Stringify.value(role, .{}, &out.writer);
            try out.writer.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(event.text, .{}, &out.writer);
            try out.writer.writeAll("}]}");
            if (event.kind == .message_update) {
                try out.writer.writeAll(",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":");
                try std.json.Stringify.value(event.text, .{}, &out.writer);
                try out.writer.writeByte('}');
            }
        },
        .turn_end => {
            try out.writer.writeAll(",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(event.text, .{}, &out.writer);
            try out.writer.writeAll("}]}");
        },
        .tool_execution_start => {
            try out.writer.writeAll(",\"toolName\":");
            try std.json.Stringify.value(event.name, .{}, &out.writer);
            try out.writer.writeAll(",\"toolCallId\":");
            try std.json.Stringify.value(event.id, .{}, &out.writer);
            try out.writer.writeAll(",\"args\":");
            if (event.args_json.len > 0 and jsonIsValid(gpa, event.args_json))
                try out.writer.writeAll(event.args_json)
            else
                try out.writer.writeAll("{}");
        },
        .tool_execution_update => {
            try out.writer.writeAll(",\"toolName\":");
            try std.json.Stringify.value(event.name, .{}, &out.writer);
            try out.writer.writeAll(",\"toolCallId\":");
            try std.json.Stringify.value(event.id, .{}, &out.writer);
            try out.writer.writeAll(",\"args\":");
            if (event.args_json.len > 0 and jsonIsValid(gpa, event.args_json))
                try out.writer.writeAll(event.args_json)
            else
                try out.writer.writeAll("{}");
            try out.writer.writeAll(",\"partialResult\":");
            try writeEventToolResult(&out.writer, event);
        },
        .tool_execution_end => {
            try out.writer.writeAll(",\"toolName\":");
            try std.json.Stringify.value(event.name, .{}, &out.writer);
            try out.writer.writeAll(",\"toolCallId\":");
            try std.json.Stringify.value(event.id, .{}, &out.writer);
            try out.writer.writeAll(",\"result\":");
            try writeEventToolResult(&out.writer, event);
            try out.writer.writeAll(",\"isError\":");
            try out.writer.writeAll(if (event.is_error) "true" else "false");
        },
        .agent_end => {
            try out.writer.writeAll(",\"messages\":[],\"text\":");
            try std.json.Stringify.value(event.text, .{}, &out.writer);
        },
        .agent_start, .turn_start => {},
        .session_compact_failed => {
            try out.writer.writeAll(",\"source\":");
            try std.json.Stringify.value(event.source, .{}, &out.writer);
            try out.writer.writeAll(",\"reason\":");
            try std.json.Stringify.value(event.reason, .{}, &out.writer);
            try out.writer.writeAll(",\"willRetry\":");
            try out.writer.writeAll(if (event.will_retry) "true" else "false");
            try out.writer.writeAll(",\"error\":");
            try std.json.Stringify.value(event.error_message orelse event.text, .{}, &out.writer);
        },
        .auto_retry_start, .auto_retry_end, .summarization_retry_scheduled, .summarization_retry_attempt_start, .summarization_retry_finished => unreachable,
        .user, .assistant, .tool_call, .tool_result, .done, .turn_limit => unreachable,
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn writeEventToolResult(writer: *std.Io.Writer, event: agent_loop.AgentEvent) !void {
    try writer.writeAll("{\"content\":");
    try writeToolContentArray(writer, event.text, event.image_b64, event.image_mime, event.images);
    try writer.writeAll(",\"details\":");
    if (event.details_json) |details|
        try writer.writeAll(details)
    else
        try writer.writeAll("null");
    try writer.writeAll(",\"isError\":");
    try writer.writeAll(if (event.is_error) "true" else "false");
    if (event.usage) |usage| {
        try writer.writeAll(",\"usage\":");
        try writeUsageObject(writer, usage, true);
    }
    if (event.added_tool_names.len > 0) {
        try writer.writeAll(",\"addedToolNames\":[");
        for (event.added_tool_names, 0..) |name, index| {
            if (index > 0) try writer.writeByte(',');
            try std.json.Stringify.value(name, .{}, writer);
        }
        try writer.writeByte(']');
    }
    try writer.writeByte('}');
}

fn writeUsageObject(writer: *std.Io.Writer, usage: anytype, include_cache_write_1h: bool) !void {
    try writer.print("{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}", .{
        usage.input,
        usage.output,
        usage.cache_read,
        usage.cache_write,
    });
    if (include_cache_write_1h) {
        if (usage.cache_write_1h) |tokens| try writer.print(",\"cacheWrite1h\":{d}", .{tokens});
    }
    if (usage.reasoning) |tokens| try writer.print(",\"reasoning\":{d}", .{tokens});
    try writer.print(",\"totalTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}}}}", .{
        usage.total(),
        usage.cost.input,
        usage.cost.output,
        usage.cost.cache_read,
        usage.cost.cache_write,
        usage.cost.total,
    });
}

fn jsonIsValid(gpa: std.mem.Allocator, raw: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    return true;
}

fn stringifyJsonValue(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

fn contextPayload(gpa: std.mem.Allocator, messages: []const ai.ChatMessage) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":\"context\",\"messages\":[");
    for (messages, 0..) |message, index| {
        if (index > 0) try out.writer.writeByte(',');
        try out.writer.print("{{\"_piIndex\":{d},\"role\":", .{index});
        try std.json.Stringify.value(message.role, .{}, &out.writer);
        try out.writer.writeAll(",\"content\":");
        if (message.hasImages()) {
            try out.writer.writeAll("[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(message.content, .{}, &out.writer);
            try out.writer.writeByte('}');
            var image_index: usize = 0;
            while (image_index < message.imageCount()) : (image_index += 1) {
                const image = message.imageAt(image_index).?;
                try out.writer.writeAll(",{\"type\":\"image\",\"data\":");
                try std.json.Stringify.value(image.data_b64, .{}, &out.writer);
                try out.writer.writeAll(",\"mimeType\":");
                try std.json.Stringify.value(image.mime_type, .{}, &out.writer);
                try out.writer.writeByte('}');
            }
            try out.writer.writeByte(']');
        } else {
            try std.json.Stringify.value(message.content, .{}, &out.writer);
        }
        if (message.custom_type) |custom_type| {
            try out.writer.writeAll(",\"customType\":");
            try std.json.Stringify.value(custom_type, .{}, &out.writer);
        }
        if (message.tool_call_id) |tool_call_id| {
            try out.writer.writeAll(",\"toolCallId\":");
            try std.json.Stringify.value(tool_call_id, .{}, &out.writer);
        }
        if (message.tool_name) |tool_name| {
            try out.writer.writeAll(",\"toolName\":");
            try std.json.Stringify.value(tool_name, .{}, &out.writer);
        }
        if (message.tool_is_error) try out.writer.writeAll(",\"isError\":true");
        try out.writer.writeByte('}');
    }
    try out.writer.writeAll("]}");
    return try out.toOwnedSlice();
}

fn parseContextProjection(
    scratch: std.mem.Allocator,
    value: std.json.Value,
    original: []const ai.ChatMessage,
) ![]const ai.ChatMessage {
    var out: std.ArrayList(ai.ChatMessage) = .empty;
    for (value.array.items) |item| {
        if (item != .object) continue;
        var message: ai.ChatMessage = .{ .role = "user", .content = "" };
        var has_base = false;
        if (item.object.get("_piIndex")) |index_value| {
            if (index_value == .integer and index_value.integer >= 0) {
                const index: usize = @intCast(index_value.integer);
                if (index < original.len) {
                    message = original[index];
                    has_base = true;
                }
            }
        }
        if (item.object.get("role")) |role| {
            if (role != .string) continue;
            message.role = try scratch.dupe(u8, role.string);
        } else if (!has_base) continue;

        if (item.object.get("content")) |content| {
            const normalized = try parseMessageContent(scratch, content);
            message.content = normalized.text;
            message.image_b64 = normalized.image_b64;
            message.image_mime = normalized.image_mime;
            message.images = normalized.images;
        } else if (!has_base) continue;

        if (item.object.get("customType")) |custom_type| {
            message.custom_type = if (custom_type == .string)
                try scratch.dupe(u8, custom_type.string)
            else
                null;
        }
        if (item.object.get("toolCallId")) |tool_call_id| {
            if (tool_call_id == .string) message.tool_call_id = try scratch.dupe(u8, tool_call_id.string);
        }
        if (item.object.get("toolName")) |tool_name| {
            if (tool_name == .string) message.tool_name = try scratch.dupe(u8, tool_name.string);
        }
        if (item.object.get("isError")) |is_error| {
            if (is_error == .bool) message.tool_is_error = is_error.bool;
        }
        try out.append(scratch, message);
    }
    return try out.toOwnedSlice(scratch);
}

const ParsedMessageContent = struct {
    text: []const u8,
    image_b64: ?[]const u8 = null,
    image_mime: ?[]const u8 = null,
    images: []const ai.ChatImage = &.{},
};

fn parseMessageContent(scratch: std.mem.Allocator, value: std.json.Value) !ParsedMessageContent {
    if (value == .string) return .{ .text = try scratch.dupe(u8, value.string) };
    if (value != .array) return .{ .text = try stringifyJsonValue(scratch, value) };

    var text: std.Io.Writer.Allocating = .init(scratch);
    var wrote = false;
    var image_b64: ?[]const u8 = null;
    var image_mime: ?[]const u8 = null;
    var extra_images: std.ArrayList(ai.ChatImage) = .empty;
    for (value.array.items) |part| {
        if (part != .object) continue;
        const kind = part.object.get("type") orelse continue;
        if (kind != .string) continue;
        if (std.mem.eql(u8, kind.string, "text")) {
            const piece = part.object.get("text") orelse continue;
            if (piece != .string) continue;
            if (wrote) try text.writer.writeByte('\n');
            wrote = true;
            try text.writer.writeAll(piece.string);
        } else if (std.mem.eql(u8, kind.string, "image")) {
            const data = part.object.get("data") orelse part.object.get("base64") orelse continue;
            if (data != .string or data.string.len == 0) continue;
            const mime_value = part.object.get("mimeType") orelse part.object.get("mime_type");
            const mime = if (mime_value) |field| if (field == .string and field.string.len > 0) field.string else "image/png" else "image/png";
            if (image_b64 == null) {
                image_b64 = try scratch.dupe(u8, data.string);
                image_mime = try scratch.dupe(u8, mime);
            } else {
                try extra_images.append(scratch, .{
                    .data_b64 = try scratch.dupe(u8, data.string),
                    .mime_type = try scratch.dupe(u8, mime),
                });
            }
        }
    }
    return .{
        .text = try text.toOwnedSlice(),
        .image_b64 = image_b64,
        .image_mime = image_mime,
        .images = try extra_images.toOwnedSlice(scratch),
    };
}

fn beforeAgentStartPayload(
    gpa: std.mem.Allocator,
    cwd: []const u8,
    prompt: []const u8,
    system_prompt: []const u8,
    images: []const agent_loop.UserImage,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":\"before_agent_start\",\"prompt\":");
    try std.json.Stringify.value(prompt, .{}, &out.writer);
    try out.writer.writeAll(",\"systemPrompt\":");
    try std.json.Stringify.value(system_prompt, .{}, &out.writer);
    try out.writer.writeAll(",\"systemPromptOptions\":{\"cwd\":");
    try std.json.Stringify.value(cwd, .{}, &out.writer);
    try out.writer.writeAll("},\"images\":[");
    for (images, 0..) |image, index| {
        if (index > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, &out.writer);
        try out.writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(image.mime_type, .{}, &out.writer);
        try out.writer.writeByte('}');
    }
    try out.writer.writeAll("]}");
    return try out.toOwnedSlice();
}

fn parseContextMessage(gpa: std.mem.Allocator, value: std.json.Value) !?agent_loop.ExtensionContextMessage {
    if (value != .object) return null;
    const custom_value = value.object.get("customType") orelse return null;
    if (custom_value != .string or custom_value.string.len == 0) return null;
    const content_value = value.object.get("content") orelse return null;
    const content = try messageContentAlloc(gpa, content_value);
    errdefer gpa.free(content);
    const custom_type = try gpa.dupe(u8, custom_value.string);
    errdefer gpa.free(custom_type);
    const display = if (value.object.get("display")) |display_value|
        display_value == .bool and display_value.bool
    else
        false;
    return .{ .custom_type = custom_type, .content = content, .display = display };
}

fn messageContentAlloc(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    if (value == .string) return try gpa.dupe(u8, value.string);
    if (value == .array) {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        var wrote = false;
        for (value.array.items) |item| {
            if (item != .object) continue;
            const kind = item.object.get("type") orelse continue;
            const text = item.object.get("text") orelse continue;
            if (kind != .string or !std.mem.eql(u8, kind.string, "text") or text != .string) continue;
            if (wrote) try out.writer.writeByte('\n');
            wrote = true;
            try out.writer.writeAll(text.string);
        }
        return try out.toOwnedSlice();
    }
    return try stringifyJsonValue(gpa, value);
}

fn beforeToolPayload(gpa: std.mem.Allocator, name: []const u8, id: []const u8, args_json: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"toolName\":");
    try std.json.Stringify.value(name, .{}, &out.writer);
    try out.writer.writeAll(",\"toolCallId\":");
    try std.json.Stringify.value(id, .{}, &out.writer);
    try out.writer.writeAll(",\"args\":");
    try out.writer.writeAll(args_json);
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn object1(gpa: std.mem.Allocator, key: []const u8, value: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('{');
    try std.json.Stringify.value(key, .{}, &out.writer);
    try out.writer.writeByte(':');
    try std.json.Stringify.value(value, .{}, &out.writer);
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

const HookToolContent = struct {
    text: []u8,
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    images: []agent_tools.ToolImage = &.{},

    fn deinit(self: *HookToolContent, gpa: std.mem.Allocator) void {
        if (self.text.len > 0) gpa.free(self.text);
        if (self.image_b64) |value| gpa.free(value);
        if (self.image_mime) |value| gpa.free(value);
        agent_tools.deinitImages(gpa, self.images);
        self.* = undefined;
    }
};

fn parseHookToolContent(gpa: std.mem.Allocator, value: std.json.Value) !HookToolContent {
    if (value == .string) return .{ .text = try gpa.dupe(u8, value.string) };
    if (value != .array) return error.InvalidToolResultContent;
    var text: std.Io.Writer.Allocating = .init(gpa);
    errdefer text.deinit();
    var image_b64: ?[]u8 = null;
    errdefer if (image_b64) |owned| gpa.free(owned);
    var image_mime: ?[]u8 = null;
    errdefer if (image_mime) |owned| gpa.free(owned);
    var extra_images: std.ArrayList(agent_tools.ToolImage) = .empty;
    errdefer {
        for (extra_images.items) |*image| image.deinit(gpa);
        extra_images.deinit(gpa);
    }
    var wrote_text = false;
    for (value.array.items) |item| {
        if (item == .string) {
            if (wrote_text) try text.writer.writeByte('\n');
            try text.writer.writeAll(item.string);
            wrote_text = true;
            continue;
        }
        if (item != .object) return error.InvalidToolResultContent;
        const kind = item.object.get("type") orelse return error.InvalidToolResultContent;
        if (kind != .string) return error.InvalidToolResultContent;
        if (std.mem.eql(u8, kind.string, "text")) {
            const field = item.object.get("text") orelse return error.InvalidToolResultContent;
            if (field != .string) return error.InvalidToolResultContent;
            if (wrote_text) try text.writer.writeByte('\n');
            try text.writer.writeAll(field.string);
            wrote_text = true;
        } else if (std.mem.eql(u8, kind.string, "image")) {
            const data = item.object.get("data") orelse item.object.get("base64") orelse return error.InvalidToolResultContent;
            if (data != .string or data.string.len == 0) return error.InvalidToolResultContent;
            const mime_value = item.object.get("mimeType") orelse item.object.get("mime_type");
            if (mime_value) |field| if (field != .string or field.string.len == 0) return error.InvalidToolResultContent;
            const data_owned = try gpa.dupe(u8, data.string);
            errdefer gpa.free(data_owned);
            const mime_owned = try gpa.dupe(u8, if (mime_value) |field| field.string else "image/png");
            errdefer gpa.free(mime_owned);
            if (image_b64 == null) {
                image_b64 = data_owned;
                image_mime = mime_owned;
            } else {
                try extra_images.append(gpa, .{ .data_b64 = data_owned, .mime_type = mime_owned });
            }
        }
    }
    return .{
        .text = try text.toOwnedSlice(),
        .image_b64 = image_b64,
        .image_mime = image_mime,
        .images = try extra_images.toOwnedSlice(gpa),
    };
}

fn writeToolContentArray(
    writer: *std.Io.Writer,
    content: []const u8,
    image_b64: ?[]const u8,
    image_mime: ?[]const u8,
    images: []const agent_tools.ToolImage,
) !void {
    try writer.writeByte('[');
    var wrote = false;
    if (content.len > 0 or (image_b64 == null and images.len == 0)) {
        try writer.writeAll("{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(content, .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    if (image_b64) |image| {
        if (wrote) try writer.writeByte(',');
        try writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(image_mime orelse "image/png", .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    for (images) |image| {
        if (wrote) try writer.writeByte(',');
        try writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(image.mime_type, .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    try writer.writeByte(']');
}

fn toolPayload(
    gpa: std.mem.Allocator,
    name: []const u8,
    id: []const u8,
    args_json: []const u8,
    result: *const agent_tools.ToolResult,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"toolName\":");
    try std.json.Stringify.value(name, .{}, &out.writer);
    try out.writer.writeAll(",\"toolCallId\":");
    try std.json.Stringify.value(id, .{}, &out.writer);
    try out.writer.writeAll(",\"args\":");
    try out.writer.writeAll(args_json);
    try out.writer.writeAll(",\"content\":");
    try writeToolContentArray(&out.writer, result.content, result.image_b64, result.image_mime, result.images);
    try out.writer.writeAll(",\"details\":");
    if (result.details_json) |details|
        try out.writer.writeAll(details)
    else
        try out.writer.writeAll("null");
    try out.writer.writeAll(",\"isError\":");
    try out.writer.writeAll(if (result.is_error) "true" else "false");
    if (result.usage) |usage| {
        try out.writer.writeAll(",\"usage\":");
        try writeUsageObject(&out.writer, usage, true);
    }
    if (result.added_tool_names.len > 0) {
        try out.writer.writeAll(",\"addedToolNames\":[");
        for (result.added_tool_names, 0..) |tool_name, index| {
            if (index > 0) try out.writer.writeByte(',');
            try std.json.Stringify.value(tool_name, .{}, &out.writer);
        }
        try out.writer.writeByte(']');
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn parseToolUsage(value: std.json.Value) !?agent_tools.ToolUsage {
    if (value == .null) return null;
    if (value != .object) return error.InvalidToolResultHook;
    var usage: agent_tools.ToolUsage = .{
        .input = try jsonObjectU64(&value.object, "input"),
        .output = try jsonObjectU64(&value.object, "output"),
        .cache_read = try jsonObjectU64(&value.object, "cacheRead"),
        .cache_write = try jsonObjectU64(&value.object, "cacheWrite"),
        .cache_write_1h = try jsonObjectOptionalU64(&value.object, "cacheWrite1h"),
        .reasoning = try jsonObjectOptionalU64(&value.object, "reasoning"),
        .total_tokens = try jsonObjectU64(&value.object, "totalTokens"),
    };
    if (value.object.get("cost")) |cost| {
        if (cost != .object) return error.InvalidToolResultHook;
        usage.cost = .{
            .input = try jsonObjectF64(&cost.object, "input"),
            .output = try jsonObjectF64(&cost.object, "output"),
            .cache_read = try jsonObjectF64(&cost.object, "cacheRead"),
            .cache_write = try jsonObjectF64(&cost.object, "cacheWrite"),
            .total = try jsonObjectF64(&cost.object, "total"),
        };
    }
    return usage;
}

fn parseStringList(gpa: std.mem.Allocator, value: std.json.Value) ![]const []const u8 {
    if (value == .null) return &.{};
    if (value != .array or value.array.items.len > 4096) return error.InvalidToolResultHook;
    if (value.array.items.len == 0) return &.{};
    const out = try gpa.alloc([]const u8, value.array.items.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |item| gpa.free(item);
        gpa.free(out);
    }
    for (value.array.items, 0..) |item, index| {
        if (item != .string or item.string.len == 0) return error.InvalidToolResultHook;
        out[index] = try gpa.dupe(u8, item.string);
        initialized += 1;
    }
    return out;
}

fn jsonObjectU64(object: *const std.json.ObjectMap, field: []const u8) !u64 {
    return (try jsonObjectOptionalU64(object, field)) orelse 0;
}

fn jsonObjectOptionalU64(object: *const std.json.ObjectMap, field: []const u8) !?u64 {
    const value = object.get(field) orelse return null;
    if (value == .null) return null;
    if (value != .integer or value.integer < 0) return error.InvalidToolResultHook;
    return @intCast(value.integer);
}

fn jsonObjectF64(object: *const std.json.ObjectMap, field: []const u8) !f64 {
    const value = object.get(field) orelse return 0;
    const number: f64 = switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        else => return error.InvalidToolResultHook,
    };
    if (!std.math.isFinite(number) or number < 0) return error.InvalidToolResultHook;
    return number;
}

fn summaryReasonName(reason: summarization_mod.Reason) []const u8 {
    return switch (reason) {
        .manual => "manual",
        .threshold => "threshold",
        .overflow => "overflow",
        .navigation => "navigation",
    };
}

fn entryTypeName(entry_type: session_mod.EntryType) []const u8 {
    return switch (entry_type) {
        .message => "message",
        .compaction => "compaction",
        .branch_summary => "branch_summary",
        .session_info => "session_info",
        .label => "label",
        .custom => "custom",
        .custom_message => "custom_message",
        .model_change => "model_change",
        .thinking_level_change => "thinking_level_change",
    };
}

fn writeNullableString(writer: *std.Io.Writer, value: ?[]const u8) !void {
    if (value) |text| try std.json.Stringify.value(text, .{}, writer) else try writer.writeAll("null");
}

fn writeAssistantUsage(writer: *std.Io.Writer, meta: session_mod.AssistantMeta) !void {
    try writer.print("{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}", .{
        meta.usage_input,
        meta.usage_output,
        meta.usage_cache_read,
        meta.usage_cache_write,
    });
    if (meta.usage_cache_write_1h) |value| try writer.print(",\"cacheWrite1h\":{d}", .{value});
    if (meta.usage_reasoning) |value| try writer.print(",\"reasoning\":{d}", .{value});
    try writer.print(",\"totalTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}}}}", .{
        meta.usage_total,
        meta.cost_input,
        meta.cost_output,
        meta.cost_cache_read,
        meta.cost_cache_write,
        meta.cost_total,
    });
}

fn writeEntryMessageContent(writer: *std.Io.Writer, entry: *const session_mod.SessionEntry) !void {
    if (entry.image_b64 == null and entry.images.len == 0) {
        try std.json.Stringify.value(entry.content, .{}, writer);
        return;
    }
    try writer.writeAll("[{\"type\":\"text\",\"text\":");
    try std.json.Stringify.value(entry.content, .{}, writer);
    try writer.writeByte('}');
    if (entry.image_b64) |data| {
        try writer.writeAll(",{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(data, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(entry.image_mime orelse "application/octet-stream", .{}, writer);
        try writer.writeByte('}');
    }
    for (entry.images) |image| {
        try writer.writeAll(",{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(image.mime_type, .{}, writer);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeSessionEntry(writer: *std.Io.Writer, entry: *const session_mod.SessionEntry) !void {
    try writer.writeAll("{\"type\":");
    try std.json.Stringify.value(entryTypeName(entry.entry_type), .{}, writer);
    try writer.writeAll(",\"id\":");
    try std.json.Stringify.value(entry.id, .{}, writer);
    try writer.writeAll(",\"parentId\":");
    try writeNullableString(writer, entry.parent_id);
    try writer.writeAll(",\"timestamp\":");
    try std.json.Stringify.value(entry.timestamp, .{}, writer);

    switch (entry.entry_type) {
        .message => {
            try writer.writeAll(",\"message\":{\"role\":");
            try std.json.Stringify.value(entry.role, .{}, writer);
            try writer.writeAll(",\"content\":");
            try writeEntryMessageContent(writer, entry);
            if (entry.tool_call_id) |value| {
                try writer.writeAll(",\"toolCallId\":");
                try std.json.Stringify.value(value, .{}, writer);
            }
            if (entry.tool_name) |value| {
                try writer.writeAll(",\"toolName\":");
                try std.json.Stringify.value(value, .{}, writer);
            }
            if (entry.tool_is_error) try writer.writeAll(",\"isError\":true");
            if (entry.meta.provider.len > 0) {
                try writer.writeAll(",\"provider\":");
                try std.json.Stringify.value(entry.meta.provider, .{}, writer);
            }
            if (entry.meta.model.len > 0) {
                try writer.writeAll(",\"model\":");
                try std.json.Stringify.value(entry.meta.model, .{}, writer);
            }
            if (entry.meta.usage_total > 0 or entry.meta.cost_total > 0) {
                try writer.writeAll(",\"usage\":");
                try writeAssistantUsage(writer, entry.meta);
            }
            try writer.writeByte('}');
        },
        .compaction => {
            try writer.writeAll(",\"summary\":");
            try std.json.Stringify.value(entry.content, .{}, writer);
            try writer.writeAll(",\"firstKeptEntryId\":");
            try writeNullableString(writer, entry.first_kept_entry_id);
            try writer.print(",\"tokensBefore\":{d},\"fromHook\":{s}", .{ entry.tokens_before, if (entry.from_hook) "true" else "false" });
            try writer.writeAll(",\"details\":");
            if (entry.data_json) |details| try writer.writeAll(details) else try writer.writeAll("null");
            if (entry.meta.usage_total > 0 or entry.meta.cost_total > 0) {
                try writer.writeAll(",\"usage\":");
                try writeAssistantUsage(writer, entry.meta);
            }
        },
        .branch_summary => {
            try writer.writeAll(",\"summary\":");
            try std.json.Stringify.value(entry.content, .{}, writer);
            try writer.writeAll(",\"fromId\":");
            try writeNullableString(writer, entry.target_id);
            try writer.writeAll(",\"fromHook\":");
            try writer.writeAll(if (entry.from_hook) "true" else "false");
            try writer.writeAll(",\"details\":");
            if (entry.data_json) |details| try writer.writeAll(details) else try writer.writeAll("null");
            if (entry.meta.usage_total > 0 or entry.meta.cost_total > 0) {
                try writer.writeAll(",\"usage\":");
                try writeAssistantUsage(writer, entry.meta);
            }
        },
        .custom_message => {
            try writer.writeAll(",\"customType\":");
            try writeNullableString(writer, entry.custom_type);
            try writer.writeAll(",\"content\":");
            try std.json.Stringify.value(entry.content, .{}, writer);
            try writer.writeAll(",\"display\":");
            try writer.writeAll(if (entry.display) "true" else "false");
        },
        .custom => {
            try writer.writeAll(",\"customType\":");
            try writeNullableString(writer, entry.custom_type);
            try writer.writeAll(",\"data\":");
            if (entry.data_json) |data| try writer.writeAll(data) else try writer.writeAll("null");
        },
        .label => {
            try writer.writeAll(",\"targetId\":");
            try writeNullableString(writer, entry.target_id);
            try writer.writeAll(",\"label\":");
            try writeNullableString(writer, entry.label);
        },
        .session_info, .model_change, .thinking_level_change => {
            try writer.writeAll(",\"data\":");
            if (entry.data_json) |data| try writer.writeAll(data) else try writer.writeAll("null");
        },
    }
    try writer.writeByte('}');
}

fn writeMessageProjection(writer: *std.Io.Writer, entry: *const session_mod.SessionEntry) !void {
    const role = switch (entry.entry_type) {
        .message => entry.role,
        .custom_message => "user",
        .compaction, .branch_summary => "user",
        else => "user",
    };
    try writer.writeAll("{\"role\":");
    try std.json.Stringify.value(role, .{}, writer);
    try writer.writeAll(",\"content\":");
    try writeEntryMessageContent(writer, entry);
    if (entry.tool_call_id) |value| {
        try writer.writeAll(",\"toolCallId\":");
        try std.json.Stringify.value(value, .{}, writer);
    }
    if (entry.tool_name) |value| {
        try writer.writeAll(",\"toolName\":");
        try std.json.Stringify.value(value, .{}, writer);
    }
    if (entry.tool_is_error) try writer.writeAll(",\"isError\":true");
    try writer.writeByte('}');
}

fn compactionBeforePayload(
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    preparation: compaction_mod.HookPreparation,
) ![]u8 {
    _ = sess;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":\"session_before_compact\",\"preparation\":{\"firstKeptEntryId\":");
    try std.json.Stringify.value(preparation.first_kept_entry_id, .{}, &out.writer);
    try out.writer.writeAll(",\"messagesToSummarize\":[");
    for (preparation.messages_to_summarize, 0..) |entry, index| {
        if (index > 0) try out.writer.writeByte(',');
        try writeMessageProjection(&out.writer, entry);
    }
    try out.writer.writeAll("],\"turnPrefixMessages\":[");
    for (preparation.turn_prefix_messages, 0..) |entry, index| {
        if (index > 0) try out.writer.writeByte(',');
        try writeMessageProjection(&out.writer, entry);
    }
    try out.writer.writeAll("],\"isSplitTurn\":");
    try out.writer.writeAll(if (preparation.is_split_turn) "true" else "false");
    try out.writer.writeAll(",\"tokensBefore\":");
    try out.writer.print("{d}", .{preparation.tokens_before});
    if (preparation.previous_summary) |value| {
        try out.writer.writeAll(",\"previousSummary\":");
        try std.json.Stringify.value(value, .{}, &out.writer);
    }
    try out.writer.writeAll(",\"fileOps\":{\"read\":[");
    for (preparation.file_ops.read, 0..) |path, index| {
        if (index > 0) try out.writer.writeByte(',');
        try std.json.Stringify.value(path, .{}, &out.writer);
    }
    try out.writer.writeAll("],\"written\":[");
    for (preparation.file_ops.written, 0..) |path, index| {
        if (index > 0) try out.writer.writeByte(',');
        try std.json.Stringify.value(path, .{}, &out.writer);
    }
    try out.writer.writeAll("],\"edited\":[");
    for (preparation.file_ops.edited, 0..) |path, index| {
        if (index > 0) try out.writer.writeByte(',');
        try std.json.Stringify.value(path, .{}, &out.writer);
    }
    try out.writer.writeAll("]},\"settings\":{\"enabled\":");
    try out.writer.writeAll(if (preparation.settings.enabled) "true" else "false");
    try out.writer.print(",\"reserveTokens\":{d},\"keepRecentTokens\":{d}", .{
        preparation.settings.reserve_tokens,
        preparation.settings.keep_recent_tokens,
    });
    try out.writer.writeAll("}},\"branchEntries\":[");
    for (preparation.branch_entries, 0..) |entry, index| {
        if (index > 0) try out.writer.writeByte(',');
        try writeSessionEntry(&out.writer, entry);
    }
    try out.writer.writeAll("],\"customInstructions\":");
    try writeNullableString(&out.writer, preparation.custom_instructions);
    try out.writer.writeAll(",\"reason\":");
    try std.json.Stringify.value(summaryReasonName(preparation.reason), .{}, &out.writer);
    try out.writer.writeAll(",\"willRetry\":");
    try out.writer.writeAll(if (preparation.will_retry) "true" else "false");
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn compactionAfterPayload(
    gpa: std.mem.Allocator,
    entry: *const session_mod.SessionEntry,
    reason: summarization_mod.Reason,
    will_retry: bool,
    from_extension: bool,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":\"session_compact\",\"compactionEntry\":");
    try writeSessionEntry(&out.writer, entry);
    try out.writer.writeAll(",\"fromExtension\":");
    try out.writer.writeAll(if (from_extension) "true" else "false");
    try out.writer.writeAll(",\"reason\":");
    try std.json.Stringify.value(summaryReasonName(reason), .{}, &out.writer);
    try out.writer.writeAll(",\"willRetry\":");
    try out.writer.writeAll(if (will_retry) "true" else "false");
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn treeBeforePayload(
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    preparation: branch_summary_mod.HookPreparation,
) ![]u8 {
    _ = sess;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":\"session_before_tree\",\"preparation\":{\"targetId\":");
    try std.json.Stringify.value(preparation.target_id, .{}, &out.writer);
    try out.writer.writeAll(",\"oldLeafId\":");
    try writeNullableString(&out.writer, preparation.old_leaf_id);
    try out.writer.writeAll(",\"commonAncestorId\":");
    try writeNullableString(&out.writer, preparation.common_ancestor_id);
    try out.writer.writeAll(",\"entriesToSummarize\":[");
    for (preparation.entries_to_summarize, 0..) |entry, index| {
        if (index > 0) try out.writer.writeByte(',');
        try writeSessionEntry(&out.writer, entry);
    }
    try out.writer.writeAll("],\"userWantsSummary\":");
    try out.writer.writeAll(if (preparation.user_wants_summary) "true" else "false");
    if (preparation.custom_instructions) |value| {
        try out.writer.writeAll(",\"customInstructions\":");
        try std.json.Stringify.value(value, .{}, &out.writer);
    }
    if (preparation.replace_instructions) try out.writer.writeAll(",\"replaceInstructions\":true");
    if (preparation.label) |value| {
        try out.writer.writeAll(",\"label\":");
        try std.json.Stringify.value(value, .{}, &out.writer);
    }
    try out.writer.writeAll("}}");
    return try out.toOwnedSlice();
}

fn treeAfterPayload(
    gpa: std.mem.Allocator,
    new_leaf_id: ?[]const u8,
    old_leaf_id: ?[]const u8,
    summary_entry: ?*const session_mod.SessionEntry,
    from_extension: bool,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":\"session_tree\",\"newLeafId\":");
    try writeNullableString(&out.writer, new_leaf_id);
    try out.writer.writeAll(",\"oldLeafId\":");
    try writeNullableString(&out.writer, old_leaf_id);
    if (summary_entry) |entry| {
        try out.writer.writeAll(",\"summaryEntry\":");
        try writeSessionEntry(&out.writer, entry);
        try out.writer.writeAll(",\"fromExtension\":");
        try out.writer.writeAll(if (from_extension) "true" else "false");
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn assistantMetaFromUsage(value: std.json.Value) !session_mod.AssistantMeta {
    const usage = (try parseToolUsage(value)) orelse return .{};
    return .{
        .usage_input = usage.input,
        .usage_output = usage.output,
        .usage_cache_read = usage.cache_read,
        .usage_cache_write = usage.cache_write,
        .usage_cache_write_1h = usage.cache_write_1h,
        .usage_reasoning = usage.reasoning,
        .usage_total = usage.total_tokens,
        .cost_input = usage.cost.input,
        .cost_output = usage.cost.output,
        .cost_cache_read = usage.cost.cache_read,
        .cost_cache_write = usage.cost.cache_write,
        .cost_total = usage.cost.total,
    };
}

fn parseCompactionOverride(gpa: std.mem.Allocator, value: std.json.Value) !compaction_mod.HookCompaction {
    if (value != .object) return error.InvalidCompactionHook;
    const summary_value = value.object.get("summary") orelse return error.InvalidCompactionHook;
    const first_value = value.object.get("firstKeptEntryId") orelse return error.InvalidCompactionHook;
    const tokens_value = value.object.get("tokensBefore") orelse return error.InvalidCompactionHook;
    if (summary_value != .string or first_value != .string or tokens_value != .integer or tokens_value.integer < 0) return error.InvalidCompactionHook;
    const summary = try gpa.dupe(u8, summary_value.string);
    errdefer gpa.free(summary);
    const first = try gpa.dupe(u8, first_value.string);
    errdefer gpa.free(first);
    var details_json: ?[]u8 = null;
    errdefer if (details_json) |owned| gpa.free(owned);
    if (value.object.get("details")) |details| {
        if (details != .null) details_json = try stringifyJsonValue(gpa, details);
    }
    const meta = if (value.object.get("usage")) |usage| try assistantMetaFromUsage(usage) else session_mod.AssistantMeta{};
    return .{
        .summary = summary,
        .first_kept_entry_id = first,
        .tokens_before = @intCast(tokens_value.integer),
        .details_json = details_json,
        .meta = meta,
    };
}

fn parseTreeSummaryOverride(gpa: std.mem.Allocator, value: std.json.Value) !?branch_summary_mod.HookSummary {
    if (value == .null) return null;
    if (value != .object) return error.InvalidTreeHook;
    const summary_value = value.object.get("summary") orelse return error.InvalidTreeHook;
    if (summary_value != .string) return error.InvalidTreeHook;
    const summary = try gpa.dupe(u8, summary_value.string);
    errdefer gpa.free(summary);
    var details_json: ?[]u8 = null;
    errdefer if (details_json) |owned| gpa.free(owned);
    if (value.object.get("details")) |details| {
        if (details != .null) details_json = try stringifyJsonValue(gpa, details);
    }
    const meta = if (value.object.get("usage")) |usage| try assistantMetaFromUsage(usage) else session_mod.AssistantMeta{};
    return .{ .summary = summary, .details_json = details_json, .meta = meta };
}

fn lifecyclePayload(gpa: std.mem.Allocator, cwd: []const u8, session_id: []const u8, reason: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"cwd\":");
    try std.json.Stringify.value(cwd, .{}, &out.writer);
    try out.writer.writeAll(",\"sessionId\":");
    try std.json.Stringify.value(session_id, .{}, &out.writer);
    try out.writer.writeAll(",\"reason\":");
    try std.json.Stringify.value(reason, .{}, &out.writer);
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn parseStringField(gpa: std.mem.Allocator, raw: []const u8, field: []const u8) !?[]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const value = parsed.value.object.get(field) orelse return null;
    if (value != .string) return null;
    return try gpa.dupe(u8, value.string);
}

test "agent event payloads are valid upstream-shaped JSON" {
    const gpa = std.testing.allocator;
    const cases = [_]agent_loop.AgentEvent{
        .{ .kind = .agent_start },
        .{ .kind = .message_update, .name = "assistant", .text = "delta" },
        .{ .kind = .turn_end, .text = "answer" },
        .{ .kind = .tool_execution_start, .name = "read", .id = "call-1", .args_json = "{\"path\":\"a.txt\"}" },
        .{
            .kind = .tool_execution_update,
            .name = "read",
            .id = "call-1",
            .text = "partial",
            .details_json = "{\"line\":2}",
            .image_b64 = "AQID",
            .image_mime = "image/png",
            .usage = .{
                .input = 1,
                .output = 2,
                .cache_read = 3,
                .cache_write = 4,
                .cache_write_1h = 1,
                .reasoning = 2,
                .total_tokens = 10,
                .cost = .{ .input = 0.1, .output = 0.2, .cache_read = 0.3, .cache_write = 0.4, .total = 1.0 },
            },
            .added_tool_names = &.{ "late_tool", "other_tool" },
            .is_partial = true,
        },
        .{
            .kind = .tool_execution_end,
            .name = "read",
            .id = "call-1",
            .text = "contents",
            .is_error = true,
            .details_json = "{\"line\":3}",
        },
        .{ .kind = .agent_end, .text = "done" },
    };
    for (cases) |event| {
        const hook = eventHookName(event.kind).?;
        const payload = try eventPayload(gpa, event, hook);
        defer gpa.free(payload);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .object);
        try std.testing.expectEqualStrings(hook, parsed.value.object.get("type").?.string);
    }

    const tool_update = try eventPayload(gpa, cases[4], "tool_execution_update");
    defer gpa.free(tool_update);
    var parsed_update = try std.json.parseFromSlice(std.json.Value, gpa, tool_update, .{});
    defer parsed_update.deinit();
    const partial = parsed_update.value.object.get("partialResult").?;
    try std.testing.expect(partial == .object);
    try std.testing.expectEqual(@as(i64, 2), partial.object.get("details").?.object.get("line").?.integer);
    try std.testing.expectEqualStrings("image", partial.object.get("content").?.array.items[1].object.get("type").?.string);
    try std.testing.expectEqualStrings("AQID", partial.object.get("content").?.array.items[1].object.get("data").?.string);
    const partial_usage = partial.object.get("usage").?;
    try std.testing.expectEqual(@as(i64, 10), partial_usage.object.get("totalTokens").?.integer);
    try std.testing.expectEqual(@as(i64, 1), partial_usage.object.get("cacheWrite1h").?.integer);
    try std.testing.expectEqual(@as(usize, 2), partial.object.get("addedToolNames").?.array.items.len);
    try std.testing.expectEqualStrings("late_tool", partial.object.get("addedToolNames").?.array.items[0].string);

    const tool_end = try eventPayload(gpa, cases[5], "tool_execution_end");
    defer gpa.free(tool_end);
    var parsed_end = try std.json.parseFromSlice(std.json.Value, gpa, tool_end, .{});
    defer parsed_end.deinit();
    const result = parsed_end.value.object.get("result").?;
    try std.testing.expect(result == .object);
    try std.testing.expect(result.object.get("isError").?.bool);
    try std.testing.expectEqual(@as(i64, 3), result.object.get("details").?.object.get("line").?.integer);
}

test "bridge forwards canonical agent events once and isolates compatibility aliases" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "events.sh", .data =
        \\#!/bin/sh
        \\printf '%s\t%s\n' "$2" "$3" >> "$(dirname "$0")/events.log"
        \\printf '%s\n' '{}'
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "events.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "events.sh", gpa);
    defer gpa.free(entry);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(
        gpa,
        "{{\"name\":\"events\",\"hooks\":[\"agent_start\",\"tool_execution_end\"],\"entry\":\"{s}\"}}",
        .{entry},
    );
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    var bridge = Bridge.init(&host);
    defer bridge.deinit();

    Bridge.onAgentEvent(&bridge, .{ .kind = .agent_start });
    Bridge.onAgentEvent(&bridge, .{ .kind = .assistant, .text = "legacy alias" });
    Bridge.onAgentEvent(&bridge, .{
        .kind = .tool_execution_end,
        .name = "read",
        .id = "call-7",
        .text = "ok",
    });

    const log = try tmp.dir.readFileAlloc(io, "events.log", gpa, .limited(16 * 1024));
    defer gpa.free(log);
    var lines = std.mem.splitScalar(u8, std.mem.trim(u8, log, "\r\n"), '\n');
    const first = lines.next().?;
    const second = lines.next().?;
    try std.testing.expect(lines.next() == null);
    try std.testing.expect(std.mem.startsWith(u8, first, "agent_start\t"));
    try std.testing.expect(std.mem.startsWith(u8, second, "tool_execution_end\t"));
    const payload = second[std.mem.indexOfScalar(u8, second, '\t').? + 1 ..];
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("read", parsed.value.object.get("toolName").?.string);
}

test "bridge applies last prompt replacement" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "rewrite.sh", .data =
        \\#!/bin/sh
        \\printf '%s\n' '{"prompt":"rewritten"}'
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "rewrite.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "rewrite.sh", gpa);
    defer gpa.free(entry);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"rewrite\",\"hooks\":[\"before_prompt\"],\"entry\":\"{s}\"}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    const replacement = (try Bridge.beforePrompt(&bridge, gpa, "original")).?;
    defer gpa.free(replacement);
    try std.testing.expectEqualStrings("rewritten", replacement);
}

test "context projection preserves native messages while filtering and injecting" {
    const gpa = std.testing.allocator;
    const original = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "hidden", .custom_type = "plan-mode-context" },
        .{ .role = "assistant", .content = "answer", .provider = "mock" },
    };
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"messages\":[{\"_piIndex\":0,\"role\":\"system\",\"content\":\"system\"},{\"_piIndex\":2,\"role\":\"assistant\",\"content\":\"answer\"},{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"new\"},{\"type\":\"image\",\"data\":\"AQID\",\"mimeType\":\"image/png\"}]}]}", .{});
    defer parsed.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const projection = try parseContextProjection(arena.allocator(), parsed.value.object.get("messages").?, &original);
    try std.testing.expectEqual(@as(usize, 3), projection.len);
    try std.testing.expectEqualStrings("mock", projection[1].provider.?);
    try std.testing.expectEqualStrings("new", projection[2].content);
    try std.testing.expectEqualStrings("AQID", projection[2].image_b64.?);
}

test "JavaScript context hook filters custom messages and preserves assistant metadata" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function (pi) {
        \\  pi.on("context", (event) => ({ messages: event.messages.filter((message) => message.customType !== "hide-me") }));
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "filter.ts", .data = source });
    const path = try tmp.dir.realPathFileAlloc(io, "filter.ts", gpa);
    defer gpa.free(path);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    host.loadPath(path) catch |err| switch (err) {
        error.FileNotFound, error.NodeRuntimeNotFound => return error.SkipZigTest,
        else => return err,
    };
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    const original = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "hidden", .custom_type = "hide-me" },
        .{ .role = "assistant", .content = "answer", .provider = "mock", .response_id = "r-1" },
    };
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const projected = try Bridge.transformContext(&bridge, arena.allocator(), &original);
    try std.testing.expectEqual(@as(usize, 2), projected.len);
    try std.testing.expectEqualStrings("system", projected[0].content);
    try std.testing.expectEqualStrings("answer", projected[1].content);
    try std.testing.expectEqualStrings("mock", projected[1].provider.?);
    try std.testing.expectEqualStrings("r-1", projected[1].response_id.?);
}

test "bridge applies before_agent_start system prompt and custom context message" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "start.sh", .data =
        \\#!/bin/sh
        \\printf '%s\n' '{"systemPrompt":"replacement system","message":{"customType":"mode-context","content":"injected context","display":false}}'
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "start.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "start.sh", gpa);
    defer gpa.free(entry);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"start\",\"hooks\":[\"before_agent_start\"],\"entry\":\"{s}\"}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    var result = (try Bridge.beforeAgentStart(&bridge, gpa, "/tmp/project", "hello", "base system", &.{})).?;
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("replacement system", result.system_prompt.?);
    try std.testing.expectEqual(@as(usize, 1), result.messages.len);
    try std.testing.expectEqualStrings("mode-context", result.messages[0].custom_type);
    try std.testing.expectEqualStrings("injected context", result.messages[0].content);
    try std.testing.expect(!result.messages[0].display);
}

test "bridge can override tool content and error status" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "tool.sh", .data =
        \\#!/bin/sh
        \\printf '%s\n' '{"content":"redacted","isError":true}'
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "tool.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "tool.sh", gpa);
    defer gpa.free(entry);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"tool\",\"hooks\":[\"after_tool\"],\"entry\":\"{s}\"}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    var raw = agent_tools.ToolResult{ .content = try gpa.dupe(u8, "secret"), .is_error = false };
    defer raw.deinit(gpa);
    var replacement = (try Bridge.afterTool(&bridge, gpa, "read", "c1", "{}", &raw)).?;
    defer replacement.deinit(gpa);
    try std.testing.expectEqualStrings("redacted", replacement.content);
    try std.testing.expect(replacement.is_error);
}

test "bridge exposes and executes extension tools" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "tool.sh", .data =
        \\#!/bin/sh
        \\printf '%s\n' '{"content":"custom result","isError":false}'
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "tool.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "tool.sh", gpa);
    defer gpa.free(entry);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"custom\",\"entry\":\"{s}\",\"tools\":[{{\"name\":\"custom_echo\",\"description\":\"Echo\",\"parameters\":{{\"type\":\"object\",\"properties\":{{\"text\":{{\"type\":\"string\"}}}}}}}}]}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    const schemas = try bridge.toolSchemasJson(gpa, .{});
    defer gpa.free(schemas);
    try std.testing.expect(std.mem.indexOf(u8, schemas, "custom_echo") != null);
    var result = (try Bridge.executeTool(&bridge, gpa, "custom_echo", "{\"text\":\"hi\"}")).?;
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("custom result", result.content);
}

test "built-in extension tools expose replacement schemas and renderer metadata" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadJson(
        "{\"name\":\"read-renderer\",\"tools\":[{\"name\":\"read\",\"hasRenderCall\":true,\"hasRenderResult\":true,\"renderShell\":\"self\",\"parameters\":{\"type\":\"object\"}}]}",
        ".",
    );
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    const schemas = try bridge.toolSchemasJson(gpa, .{});
    defer gpa.free(schemas);
    try std.testing.expect(std.mem.indexOf(u8, schemas, "\"name\":\"read\"") != null);
    try std.testing.expect(Bridge.hasExecutableTool(&bridge, "read"));
    try std.testing.expect(host.extensions.items[0].tools[0].has_render_call);
    try std.testing.expect(host.extensions.items[0].tools[0].has_render_result);
    try std.testing.expect(host.extensions.items[0].tools[0].render_shell_self);
}

test "bridge exposes extension tool executionMode" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "noop.sh", .data =
        \\#!/bin/sh
        \\printf '%s\n' '{"content":"ok"}'
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "noop.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "noop.sh", gpa);
    defer gpa.free(entry);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"mode\",\"entry\":\"{s}\",\"tools\":[{{\"name\":\"ordered\",\"executionMode\":\"sequential\",\"parameters\":{{\"type\":\"object\"}}}}]}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    try std.testing.expectEqual(agent_loop.ToolExecutionMode.sequential, Bridge.toolExecutionMode(&bridge, "ordered"));
    try std.testing.expectEqual(agent_loop.ToolExecutionMode.parallel, Bridge.toolExecutionMode(&bridge, "missing"));
}

test "JavaScript tool_result hook can replace text image details and error state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.on('tool_result', (event) => {
        \\    if (event.toolName !== 'vision') return;
        \\    if (event.details.phase !== 1) throw new Error('missing original details');
        \\    if (event.content[1].type !== 'image' || event.content[2].data !== 'T0xEMg==') throw new Error('missing original images');
        \\    if (event.usage.totalTokens !== 3) throw new Error('missing original usage');
        \\    if (event.addedToolNames[0] !== 'original_tool') throw new Error('missing original tool names');
        \\    return {
        \\      content: [
        \\        { type: 'text', text: 'sanitized' },
        \\        { type: 'image', data: 'TkVX', mimeType: 'image/webp' },
        \\        { type: 'image', data: 'TkVXMg==', mimeType: 'image/png' },
        \\      ],
        \\      details: { phase: 2, sanitized: true },
        \\      usage: { input: 5, output: 6, cacheRead: 7, cacheWrite: 8, cacheWrite1h: 2, reasoning: 3, totalTokens: 26, cost: { input: 0.5, output: 0.6, cacheRead: 0.7, cacheWrite: 0.8, total: 2.6 } },
        \\      addedToolNames: ['replacement_tool'],
        \\      isError: true,
        \\    };
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "result.ts", .data = source });
    const path = try tmp.dir.realPathFileAlloc(io, "result.ts", gpa);
    defer gpa.free(path);

    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    host.loadPath(path) catch |err| switch (err) {
        error.JavaScriptRuntimeNotFound => return error.SkipZigTest,
        else => return err,
    };
    var bridge = Bridge.init(&host);
    defer bridge.deinit();
    var raw = agent_tools.ToolResult{
        .content = try gpa.dupe(u8, "original"),
        .is_error = false,
        .image_b64 = try gpa.dupe(u8, "T0xE"),
        .image_mime = try gpa.dupe(u8, "image/png"),
        .images = try agent_tools.cloneImages(gpa, &.{.{ .data_b64 = @constCast("T0xEMg=="), .mime_type = @constCast("image/jpeg") }}),
        .details_json = try gpa.dupe(u8, "{\"phase\":1}"),
        .usage = .{ .input = 1, .output = 2, .total_tokens = 3, .cost = .{ .total = 0.3 } },
        .added_tool_names = blk: {
            const names = try gpa.alloc([]const u8, 1);
            names[0] = try gpa.dupe(u8, "original_tool");
            break :blk names;
        },
    };
    defer raw.deinit(gpa);

    var replacement = (try Bridge.afterTool(&bridge, gpa, "vision", "call-v", "{}", &raw)).?;
    defer replacement.deinit(gpa);
    try std.testing.expectEqualStrings("sanitized", replacement.content);
    try std.testing.expect(replacement.is_error);
    try std.testing.expectEqualStrings("TkVX", replacement.image_b64.?);
    try std.testing.expectEqualStrings("image/webp", replacement.image_mime.?);
    try std.testing.expectEqual(@as(usize, 1), replacement.images.len);
    try std.testing.expectEqualStrings("TkVXMg==", replacement.images[0].data_b64);
    try std.testing.expectEqualStrings("image/png", replacement.images[0].mime_type);
    try std.testing.expect(std.mem.indexOf(u8, replacement.details_json.?, "\"phase\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, replacement.details_json.?, "\"sanitized\":true") != null);
    try std.testing.expectEqual(@as(u64, 26), replacement.usage.?.total_tokens);
    try std.testing.expectEqual(@as(?u64, 2), replacement.usage.?.cache_write_1h);
    try std.testing.expectEqual(@as(usize, 1), replacement.added_tool_names.?.len);
    try std.testing.expectEqualStrings("replacement_tool", replacement.added_tool_names.?[0]);
}

test "JavaScript session compaction and tree hooks round trip native payloads and actions" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.on('session_before_compact', (event) => {
        \\    if (event.type !== 'session_before_compact') throw new Error('missing compact type');
        \\    if (!Array.isArray(event.preparation.messagesToSummarize) || event.preparation.messagesToSummarize.length !== 4) throw new Error('bad compact messages');
        \\    if (!Array.isArray(event.branchEntries) || event.branchEntries.length !== 6) throw new Error('bad branch entries');
        \\    if (event.reason !== 'overflow' || event.willRetry !== true) throw new Error('bad compact reason');
        \\    return { compaction: {
        \\      summary: 'js compact 164',
        \\      firstKeptEntryId: event.preparation.firstKeptEntryId,
        \\      tokensBefore: event.preparation.tokensBefore,
        \\      details: { source: 'js164' },
        \\      usage: { input: 1, output: 2, cacheRead: 3, cacheWrite: 4, totalTokens: 10, cost: { input: 0.1, output: 0.2, cacheRead: 0.3, cacheWrite: 0.4, total: 1 } },
        \\    } };
        \\  });
        \\  pi.on('session_compact', (event) => {
        \\    if (event.type !== 'session_compact' || event.compactionEntry.summary !== 'js compact 164' || event.fromExtension !== true) throw new Error('bad compact after');
        \\    pi.appendEntry('after-compact-164', { reason: event.reason, retry: event.willRetry });
        \\  });
        \\  pi.on('session_before_tree', (event) => {
        \\    if (event.type !== 'session_before_tree' || event.preparation.userWantsSummary !== true) throw new Error('bad tree before');
        \\    if (event.preparation.entriesToSummarize.length !== 2) throw new Error('bad tree entries');
        \\    return { summary: {
        \\      summary: 'js tree 164', details: { source: 'tree164' },
        \\      usage: { input: 5, output: 6, cacheRead: 0, cacheWrite: 0, totalTokens: 11, cost: { input: 0.5, output: 0.6, cacheRead: 0, cacheWrite: 0, total: 1.1 } },
        \\    }, label: 'tree-label-164' };
        \\  });
        \\  pi.on('session_tree', (event) => {
        \\    if (event.type !== 'session_tree' || event.summaryEntry.summary !== 'js tree 164' || event.fromExtension !== true) throw new Error('bad tree after');
        \\    pi.appendEntry('after-tree-164', { ok: true });
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "hooks.ts", .data = source });
    const path = try tmp.dir.realPathFileAlloc(io, "hooks.ts", gpa);
    defer gpa.free(path);
    var host = host_mod.Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    host.loadPath(path) catch |err| switch (err) {
        error.JavaScriptRuntimeNotFound, error.NodeRuntimeNotFound => return error.SkipZigTest,
        else => return err,
    };
    var bridge = Bridge.init(&host);
    defer bridge.deinit();

    var sess = try session_mod.Session.init(gpa, "integration-hooks-164", "/tmp");
    defer sess.deinit();
    var parent: ?[]const u8 = null;
    for (0..6) |index| {
        const text = try std.fmt.allocPrint(gpa, "entry-{d}", .{index});
        defer gpa.free(text);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", text, null, null);
    }
    const branch = try sess.contextEntries(gpa);
    defer gpa.free(branch);
    var compact_result = (try Bridge.beforeCompact(&bridge, gpa, &sess, .{
        .branch_entries = branch,
        .messages_to_summarize = branch[0..4],
        .turn_prefix_messages = &.{},
        .is_split_turn = false,
        .first_kept_entry_id = branch[4].id,
        .tokens_before = 164,
        .settings = .{ .reserve_tokens = 16_384, .keep_recent_tokens = 20_000 },
        .reason = .overflow,
        .will_retry = true,
    })).?;
    defer compact_result.deinit(gpa);
    try std.testing.expectEqualStrings("js compact 164", compact_result.compaction.?.summary);
    try std.testing.expectEqualStrings("{\"source\":\"js164\"}", compact_result.compaction.?.details_json.?);
    try std.testing.expectEqual(@as(u64, 10), compact_result.compaction.?.meta.usage_total);
    const compact_id = try sess.appendCompaction(
        compact_result.compaction.?.summary,
        compact_result.compaction.?.first_kept_entry_id,
        compact_result.compaction.?.tokens_before,
        compact_result.compaction.?.details_json,
        true,
        compact_result.compaction.?.meta,
    );
    try Bridge.afterCompact(&bridge, gpa, sess.getEntry(compact_id).?, .overflow, true, true);
    const compact_actions = try bridge.drainActions();
    defer actions_mod.freeRecords(gpa, compact_actions);
    try std.testing.expectEqual(@as(usize, 1), compact_actions.len);
    try std.testing.expectEqualStrings("append_entry", compact_actions[0].kind);
    try std.testing.expect(std.mem.indexOf(u8, compact_actions[0].json, "after-compact-164") != null);

    const first = sess.entries.items[0].id;
    const second = sess.entries.items[1].id;
    try sess.setTip(second);
    const abandoned_user = try sess.appendMessage(second, "user", "abandoned", null, null);
    _ = try sess.appendMessage(abandoned_user, "assistant", "abandoned answer", null, null);
    const tree_entries = try sess.branchEntriesAt(gpa, sess.lastEntryId());
    defer gpa.free(tree_entries);
    var tree_result = (try Bridge.beforeTree(&bridge, gpa, &sess, .{
        .target_id = first,
        .old_leaf_id = sess.lastEntryId(),
        .common_ancestor_id = first,
        .entries_to_summarize = tree_entries[2..],
        .user_wants_summary = true,
        .custom_instructions = "focus",
        .replace_instructions = false,
        .label = null,
    })).?;
    defer tree_result.deinit(gpa);
    try std.testing.expectEqualStrings("js tree 164", tree_result.summary.?.summary);
    try std.testing.expectEqualStrings("tree-label-164", tree_result.label.?);
    try std.testing.expectEqual(@as(u64, 11), tree_result.summary.?.meta.usage_total);
    const tree_id = try sess.appendBranchSummaryWithHook(first, first, tree_result.summary.?.summary, tree_result.summary.?.details_json, true, tree_result.summary.?.meta);
    try Bridge.afterTree(&bridge, gpa, tree_id, second, sess.getEntry(tree_id).?, true);
    const tree_actions = try bridge.drainActions();
    defer actions_mod.freeRecords(gpa, tree_actions);
    try std.testing.expectEqual(@as(usize, 1), tree_actions.len);
    try std.testing.expectEqualStrings("append_entry", tree_actions[0].kind);
    try std.testing.expect(std.mem.indexOf(u8, tree_actions[0].json, "after-tree-164") != null);
}
