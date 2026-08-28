//! Shared retry boundary for compaction and branch-summary model calls.
const std = @import("std");
const ai = @import("../ai/root.zig");

const Io = std.Io;

pub const Source = enum {
    compaction,
    branch_summary,

    pub fn wireName(self: Source) []const u8 {
        return switch (self) {
            .compaction => "compaction",
            .branch_summary => "branchSummary",
        };
    }
};

pub const Reason = enum {
    manual,
    threshold,
    overflow,
    navigation,

    pub fn wireName(self: Reason) []const u8 {
        return @tagName(self);
    }
};

pub const EventKind = enum {
    retry_scheduled,
    retry_attempt_start,
    retry_finished,
};

pub const Event = struct {
    kind: EventKind,
    source: Source,
    reason: Reason,
    attempt: usize = 0,
    max_attempts: usize = 0,
    delay_ms: u64 = 0,
    error_message: []const u8 = "",
    success: bool = false,
    final_error: ?[]const u8 = null,
};

pub const EventHandler = *const fn (ctx: ?*anyopaque, event: Event) void;

pub const Options = struct {
    io: Io,
    client: ai.ModelClient,
    source: Source,
    reason: Reason,
    retry_enabled: bool = true,
    retry_max_retries: usize = 3,
    retry_base_delay_ms: u64 = 2_000,
    /// Request-local provider output cap. Branch summaries use the original
    /// independent 2,048-token ceiling; zero preserves the model default.
    max_output_tokens: u64 = 0,
    abort_flag: ?*bool = null,
    retry_abort_flag: ?*bool = null,
    on_event: ?EventHandler = null,
    event_ctx: ?*anyopaque = null,
};

fn emit(options: Options, event: Event) void {
    if (options.on_event) |handler| handler(options.event_ctx, event);
}

fn responseIsError(response: ai.ModelResponse) bool {
    return response.stop_reason.len > 0 and std.mem.eql(u8, response.stop_reason, "error");
}

fn responseIsAborted(response: ai.ModelResponse) bool {
    return response.stop_reason.len > 0 and std.mem.eql(u8, response.stop_reason, "aborted");
}

fn responseErrorText(response: ai.ModelResponse) []const u8 {
    if (response.error_message.len > 0) return response.error_message;
    if (response.content.len > 0) return response.content;
    return "Unknown summarization error";
}

fn makeErrorResponse(gpa: std.mem.Allocator, message: []const u8) !ai.ModelResponse {
    const content = try gpa.dupe(u8, message);
    errdefer gpa.free(content);
    const error_message = try gpa.dupe(u8, message);
    errdefer gpa.free(error_message);
    const stop_reason = try gpa.dupe(u8, "error");
    errdefer gpa.free(stop_reason);
    return .{
        .content = content,
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .error_message = error_message,
        .stop_reason = stop_reason,
    };
}

fn completeOnce(
    gpa: std.mem.Allocator,
    client: ai.ModelClient,
    messages: []const ai.ChatMessage,
    max_output_tokens: u64,
) !ai.ModelResponse {
    return client.completeWithOptions(gpa, messages, "[]", .{ .max_tokens = max_output_tokens, .isolate_cache = true }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return try makeErrorResponse(gpa, @errorName(err)),
    };
}

/// Run one standalone summarization call with the same retry policy used by
/// assistant turns. Events are emitted only after a retry has been scheduled.
pub fn complete(
    gpa: std.mem.Allocator,
    messages: []const ai.ChatMessage,
    options: Options,
) !ai.ModelResponse {
    if (ai.retry.isAbortRequested(options.abort_flag, options.retry_abort_flag)) {
        return error.SummarizationCancelled;
    }

    var response = try completeOnce(gpa, options.client, messages, options.max_output_tokens);
    var attempt: usize = 0;
    var retry_started = false;

    while (options.retry_enabled and
        attempt < options.retry_max_retries and
        responseIsError(response) and
        ai.retry.isRetryableError(responseErrorText(response)))
    {
        attempt += 1;
        retry_started = true;
        const error_text = responseErrorText(response);
        const delay_ms = ai.retry.delayMs(options.retry_base_delay_ms, attempt);
        emit(options, .{
            .kind = .retry_scheduled,
            .source = options.source,
            .reason = options.reason,
            .attempt = attempt,
            .max_attempts = options.retry_max_retries,
            .delay_ms = delay_ms,
            .error_message = error_text,
        });

        if (!ai.retry.wait(options.io, delay_ms, options.abort_flag, options.retry_abort_flag)) {
            emit(options, .{
                .kind = .retry_finished,
                .source = options.source,
                .reason = options.reason,
                .attempt = attempt,
                .success = false,
                .final_error = error_text,
            });
            response.deinit(gpa);
            return error.SummarizationCancelled;
        }

        emit(options, .{
            .kind = .retry_attempt_start,
            .source = options.source,
            .reason = options.reason,
            .attempt = attempt,
            .max_attempts = options.retry_max_retries,
        });

        response.deinit(gpa);
        response = try completeOnce(gpa, options.client, messages, options.max_output_tokens);
    }

    if (retry_started) {
        const success = !responseIsError(response) and !responseIsAborted(response);
        emit(options, .{
            .kind = .retry_finished,
            .source = options.source,
            .reason = options.reason,
            .attempt = attempt,
            .success = success,
            .final_error = if (success) null else responseErrorText(response),
        });
    }

    return response;
}

const EventProbe = struct {
    scheduled: usize = 0,
    started: usize = 0,
    finished: usize = 0,
    success: bool = false,

    fn onEvent(raw: ?*anyopaque, event: Event) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        switch (event.kind) {
            .retry_scheduled => self.scheduled += 1,
            .retry_attempt_start => self.started += 1,
            .retry_finished => {
                self.finished += 1;
                self.success = event.success;
            },
        }
    }
};

test "summarization forwards request-local output cap" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\  {"content":"bounded summary","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "summarize" }};
    var response = try complete(gpa, &messages, .{
        .io = std.testing.io,
        .client = model.client(),
        .source = .branch_summary,
        .reason = .navigation,
        .max_output_tokens = 2048,
    });
    defer response.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 2048), model.last_completion_options.max_tokens);
    try std.testing.expect(model.last_completion_options.isolate_cache);
}

test "summarization retries transient response then succeeds" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\  {"content":"HTTP 503 Service Unavailable","stop_reason":"error","tool_calls":[]},
        \\  {"content":"summary ok","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var probe: EventProbe = .{};
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "summarize" }};
    var response = try complete(gpa, &messages, .{
        .io = std.testing.io,
        .client = model.client(),
        .source = .compaction,
        .reason = .manual,
        .retry_base_delay_ms = 0,
        .on_event = EventProbe.onEvent,
        .event_ctx = &probe,
    });
    defer response.deinit(gpa);

    try std.testing.expectEqualStrings("summary ok", response.content);
    try std.testing.expectEqual(@as(usize, 1), probe.scheduled);
    try std.testing.expectEqual(@as(usize, 1), probe.started);
    try std.testing.expectEqual(@as(usize, 1), probe.finished);
    try std.testing.expect(probe.success);
}

test "summarization quota failure is not retried" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\  {"content":"429 insufficient_quota billing required","stop_reason":"error","tool_calls":[]},
        \\  {"content":"must not be consumed","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var probe: EventProbe = .{};
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "summarize" }};
    var response = try complete(gpa, &messages, .{
        .io = std.testing.io,
        .client = model.client(),
        .source = .branch_summary,
        .reason = .navigation,
        .retry_base_delay_ms = 0,
        .on_event = EventProbe.onEvent,
        .event_ctx = &probe,
    });
    defer response.deinit(gpa);

    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expectEqual(@as(usize, 0), probe.scheduled);
    try std.testing.expectEqual(@as(usize, 1), model.index);
}

test "summarization retry backoff observes cancellation" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\  {"content":"HTTP 503 Service Unavailable","stop_reason":"error","tool_calls":[]},
        \\  {"content":"must not be consumed","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var retry_abort = true;
    var probe: EventProbe = .{};
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "summarize" }};
    try std.testing.expectError(error.SummarizationCancelled, complete(gpa, &messages, .{
        .io = std.testing.io,
        .client = model.client(),
        .source = .compaction,
        .reason = .overflow,
        .retry_base_delay_ms = 0,
        .retry_abort_flag = &retry_abort,
        .on_event = EventProbe.onEvent,
        .event_ctx = &probe,
    }));
    try std.testing.expectEqual(@as(usize, 0), model.index);
}

test "summarization cancellation during backoff emits finished and preserves next response" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\  {"content":"HTTP 503 Service Unavailable","stop_reason":"error","tool_calls":[]},
        \\  {"content":"must not be consumed","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var retry_abort = false;
    const Probe = struct {
        abort_flag: *bool,
        scheduled: usize = 0,
        started: usize = 0,
        finished: usize = 0,
        success: bool = true,

        fn onEvent(raw: ?*anyopaque, event: Event) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            switch (event.kind) {
                .retry_scheduled => {
                    self.scheduled += 1;
                    @atomicStore(bool, self.abort_flag, true, .release);
                },
                .retry_attempt_start => self.started += 1,
                .retry_finished => {
                    self.finished += 1;
                    self.success = event.success;
                },
            }
        }
    };
    var probe = Probe{ .abort_flag = &retry_abort };
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "summarize" }};
    try std.testing.expectError(error.SummarizationCancelled, complete(gpa, &messages, .{
        .io = std.testing.io,
        .client = model.client(),
        .source = .compaction,
        .reason = .overflow,
        .retry_base_delay_ms = 250,
        .retry_abort_flag = &retry_abort,
        .on_event = Probe.onEvent,
        .event_ctx = &probe,
    }));
    try std.testing.expectEqual(@as(usize, 1), model.index);
    try std.testing.expectEqual(@as(usize, 1), probe.scheduled);
    try std.testing.expectEqual(@as(usize, 0), probe.started);
    try std.testing.expectEqual(@as(usize, 1), probe.finished);
    try std.testing.expect(!probe.success);
}

test "summarization emits one finished event after retry exhaustion" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\  {"content":"HTTP 503 first","stop_reason":"error","tool_calls":[]},
        \\  {"content":"HTTP 503 second","stop_reason":"error","tool_calls":[]},
        \\  {"content":"HTTP 503 final","stop_reason":"error","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var probe: EventProbe = .{};
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "summarize" }};
    var response = try complete(gpa, &messages, .{
        .io = std.testing.io,
        .client = model.client(),
        .source = .branch_summary,
        .reason = .navigation,
        .retry_max_retries = 2,
        .retry_base_delay_ms = 0,
        .on_event = EventProbe.onEvent,
        .event_ctx = &probe,
    });
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expectEqualStrings("HTTP 503 final", response.content);
    try std.testing.expectEqual(@as(usize, 3), model.index);
    try std.testing.expectEqual(@as(usize, 2), probe.scheduled);
    try std.testing.expectEqual(@as(usize, 2), probe.started);
    try std.testing.expectEqual(@as(usize, 1), probe.finished);
    try std.testing.expect(!probe.success);
}
