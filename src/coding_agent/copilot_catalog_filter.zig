//! Account-scoped GitHub Copilot model visibility.
//!
//! Upstream filters the generated provider catalog only when an OAuth credential
//! explicitly carries `availableModelIds`; API-key credentials remain unfiltered.
//! This port also keeps account-advertised models usable when the bundled curated
//! catalog lags GitHub: known entries retain their metadata, while unknown IDs are
//! synthesized from the same API-routing rules used by upstream model generation.
const std = @import("std");
const Io = std.Io;
const providers = @import("../ai/providers.zig");
const api = @import("../ai/api.zig");
const thinking = @import("../ai/thinking.zig");
const auth = @import("../auth/storage.zig");

fn allowed(ids: []const []u8, model_id: []const u8) bool {
    for (ids) |id| if (std.mem.eql(u8, id, model_id)) return true;
    return false;
}

fn isCopilotClaude(id: []const u8) bool {
    const prefixes = [_][]const u8{
        "claude-haiku-4",  "claude-haiku-5",
        "claude-sonnet-4", "claude-sonnet-5",
        "claude-opus-4",   "claude-opus-5",
    };
    for (prefixes) |prefix| if (std.mem.startsWith(u8, id, prefix)) return true;
    return false;
}

fn usesResponses(id: []const u8) bool {
    return std.mem.eql(u8, id, "grok-4.5") or std.mem.startsWith(u8, id, "gpt-5") or
        std.mem.startsWith(u8, id, "oswe") or std.mem.startsWith(u8, id, "mai-");
}

fn isExtendedContext(id: []const u8) bool {
    const ids = [_][]const u8{
        "claude-fable-5", "claude-opus-4.6",   "claude-opus-4.7", "claude-opus-4.8",
        "claude-opus-5",  "claude-sonnet-4.6", "claude-sonnet-5", "gpt-5.3-codex",
        "gpt-5.4",        "gpt-5.5",
    };
    for (ids) |candidate| if (std.mem.eql(u8, id, candidate)) return true;
    return false;
}

fn hasOpenAiXhigh(id: []const u8) bool {
    return std.mem.indexOf(u8, id, "gpt-5.2") != null or std.mem.indexOf(u8, id, "gpt-5.3") != null or
        std.mem.indexOf(u8, id, "gpt-5.4") != null or std.mem.indexOf(u8, id, "gpt-5.5") != null or
        std.mem.indexOf(u8, id, "gpt-5.6") != null;
}

fn synthThinkingMap(id: []const u8) ?thinking.ThinkingLevelMap {
    if (std.mem.startsWith(u8, id, "gpt-5")) {
        var map: thinking.ThinkingLevelMap = .{ .off = .unsupported, .minimal = .{ .mapped = "low" } };
        if (hasOpenAiXhigh(id)) map.xhigh = .{ .mapped = "xhigh" };
        if (std.mem.indexOf(u8, id, "gpt-5.6") != null) map.max = .{ .mapped = "max" };
        return map;
    }
    if (std.mem.eql(u8, id, "claude-sonnet-4.6"))
        return .{ .minimal = .{ .mapped = "low" }, .max = .{ .mapped = "max" } };
    if (std.mem.eql(u8, id, "claude-opus-4.7") or std.mem.eql(u8, id, "claude-opus-4.8") or std.mem.eql(u8, id, "claude-opus-5"))
        return .{ .minimal = .{ .mapped = "low" }, .xhigh = .{ .mapped = "xhigh" }, .max = .{ .mapped = "max" } };
    return null;
}

fn inferReasoning(id: []const u8) bool {
    return std.mem.startsWith(u8, id, "gpt-5") or std.mem.eql(u8, id, "grok-4.5") or
        std.mem.indexOf(u8, id, "sonnet") != null or std.mem.indexOf(u8, id, "opus") != null or
        std.mem.startsWith(u8, id, "gemini-3") or std.mem.startsWith(u8, id, "oswe") or
        std.mem.startsWith(u8, id, "mai-");
}

fn synthModel(id: []const u8) providers.ModelInfo {
    const selected_api: api.Api = if (isCopilotClaude(id))
        .anthropic_messages
    else if (usesResponses(id))
        .openai_responses
    else
        .openai_completions;
    return .{
        .provider = selected_api.nativeProvider(),
        .provider_id = "github-copilot",
        .api = selected_api,
        .id = id,
        .display = id,
        .reasoning = inferReasoning(id),
        // Unknown account entries use upstream's generator fallbacks. Known
        // curated entries still win and retain their richer capability metadata.
        .context_window = if (isExtendedContext(id)) 1_000_000 else 128_000,
        .max_tokens = 8_192,
        .thinking_level_map = synthThinkingMap(id),
    };
}

pub const Set = struct {
    gpa: std.mem.Allocator,
    infos: []providers.ModelInfo = &.{},
    credential: ?auth.Credential = null,

    pub fn deinit(self: *Set) void {
        if (self.infos.len > 0) self.gpa.free(self.infos);
        if (self.credential) |*credential| credential.deinit(self.gpa);
        self.* = undefined;
    }
};

/// Owned catalog overlay. The retained credential owns any synthesized model IDs.
pub fn load(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    catalog: []const providers.ModelInfo,
) !Set {
    const ad = agent_dir orelse return .{ .gpa = gpa, .infos = try gpa.dupe(providers.ModelInfo, catalog) };
    var store = try auth.AuthStorage.init(gpa, io, ad);
    defer store.deinit();
    var credential = (try store.read("github-copilot")) orelse return .{ .gpa = gpa, .infos = try gpa.dupe(providers.ModelInfo, catalog) };
    errdefer credential.deinit(gpa);
    const oauth = switch (credential) {
        .oauth => |*value| value,
        else => {
            credential.deinit(gpa);
            return .{ .gpa = gpa, .infos = try gpa.dupe(providers.ModelInfo, catalog) };
        },
    };
    if (!oauth.available_model_ids_present) {
        credential.deinit(gpa);
        return .{ .gpa = gpa, .infos = try gpa.dupe(providers.ModelInfo, catalog) };
    }

    var out: std.ArrayList(providers.ModelInfo) = .empty;
    errdefer out.deinit(gpa);
    // Preserve normal catalog ordering while filtering Copilot to the account list.
    for (catalog) |model| {
        if (std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot") and !allowed(oauth.available_model_ids, model.id)) continue;
        try out.append(gpa, model);
    }
    // Add account-visible models that were not bundled in the curated snapshot.
    for (oauth.available_model_ids) |id| {
        var known = false;
        for (catalog) |model| {
            if (std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot") and std.mem.eql(u8, model.id, id)) {
                known = true;
                break;
            }
        }
        if (!known) try out.append(gpa, synthModel(id));
    }
    return .{ .gpa = gpa, .infos = try out.toOwnedSlice(gpa), .credential = credential };
}

/// Compatibility filtering helper for callers that do not need synthesized IDs.
pub fn apply(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    catalog: []const providers.ModelInfo,
) ![]providers.ModelInfo {
    const ad = agent_dir orelse return try gpa.dupe(providers.ModelInfo, catalog);
    var store = try auth.AuthStorage.init(gpa, io, ad);
    defer store.deinit();
    var credential = (try store.read("github-copilot")) orelse return try gpa.dupe(providers.ModelInfo, catalog);
    defer credential.deinit(gpa);
    const oauth = switch (credential) {
        .oauth => |value| value,
        else => return try gpa.dupe(providers.ModelInfo, catalog),
    };
    if (!oauth.available_model_ids_present) return try gpa.dupe(providers.ModelInfo, catalog);

    var out: std.ArrayList(providers.ModelInfo) = .empty;
    errdefer out.deinit(gpa);
    for (catalog) |model| {
        if (std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot") and !allowed(oauth.available_model_ids, model.id)) continue;
        try out.append(gpa, model);
    }
    return try out.toOwnedSlice(gpa);
}

test "Copilot OAuth availableModelIds filters only that provider" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    var store = try auth.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    var ids = [_][]u8{@constCast("gpt-5-mini")};
    try store.setOAuth("github-copilot", .{
        .refresh = @constCast("gh"),
        .access = @constCast("cp"),
        .expires = 123,
        .available_model_ids = &ids,
        .available_model_ids_present = true,
    });
    const input = [_]providers.ModelInfo{
        .{ .provider = .openai, .provider_id = "github-copilot", .id = "gpt-5-mini", .display = "yes" },
        .{ .provider = .anthropic, .provider_id = "github-copilot", .id = "claude-sonnet-4.6", .display = "no" },
        .{ .provider = .openai, .id = "gpt-4o", .display = "other" },
    };
    const filtered = try apply(gpa, io, root, &input);
    defer gpa.free(filtered);
    try std.testing.expectEqual(@as(usize, 2), filtered.len);
    try std.testing.expectEqualStrings("gpt-5-mini", filtered[0].id);
    try std.testing.expectEqualStrings("gpt-4o", filtered[1].id);
}

test "Copilot OAuth explicit empty model list hides all Copilot models" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    var store = try auth.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    try store.setOAuth("github-copilot", .{
        .refresh = @constCast("gh"),
        .access = @constCast("cp"),
        .expires = 123,
        .available_model_ids_present = true,
    });
    const input = [_]providers.ModelInfo{
        .{ .provider = .openai, .provider_id = "github-copilot", .id = "gpt-5-mini", .display = "hidden" },
        .{ .provider = .openai, .id = "gpt-4o", .display = "other" },
    };
    const filtered = try apply(gpa, io, root, &input);
    defer gpa.free(filtered);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("gpt-4o", filtered[0].id);
}

test "Copilot account overlay synthesizes an unknown selectable model with upstream routing" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    var store = try auth.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    var ids = [_][]u8{ @constCast("gpt-5.4"), @constCast("claude-opus-4.8"), @constCast("gemini-new") };
    try store.setOAuth("github-copilot", .{
        .refresh = @constCast("gh"),
        .access = @constCast("cp"),
        .expires = 123,
        .available_model_ids = &ids,
        .available_model_ids_present = true,
    });
    var set = try load(gpa, io, root, &.{});
    defer set.deinit();
    try std.testing.expectEqual(@as(usize, 3), set.infos.len);
    try std.testing.expect(set.infos[0].apiKind() == .openai_responses);
    try std.testing.expectEqual(@as(u64, 1_000_000), set.infos[0].context_window);
    try std.testing.expect(set.infos[1].apiKind() == .anthropic_messages);
    try std.testing.expectEqualStrings("xhigh", set.infos[1].thinking_level_map.?.xhigh.mapped);
    try std.testing.expect(set.infos[2].apiKind() == .openai_completions);
    try std.testing.expectEqual(@as(u64, 128_000), set.infos[2].context_window);
}
