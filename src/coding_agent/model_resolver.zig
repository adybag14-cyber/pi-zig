//! Pi-compatible model reference parsing and scope resolution.
//!
//! Ported from upstream `packages/coding-agent/src/core/model-resolver.ts`.
//! This module deliberately operates on real runtime `ModelInfo` entries only.
const std = @import("std");
const ai = @import("../ai/root.zig");
const providers = @import("../ai/providers.zig");

pub const ModelInfo = providers.ModelInfo;
pub const Provider = providers.Provider;
pub const ThinkingLevel = ai.ThinkingLevel;

pub const PatternWarning = struct {
    invalid_suffix: []const u8,
    pattern: []const u8,
};

pub const ParsedModelResult = struct {
    model: ?ModelInfo = null,
    thinking_level: ?ThinkingLevel = null,
    warning: ?PatternWarning = null,
};

pub const ScopedModel = struct {
    model: ModelInfo,
    thinking_level: ?ThinkingLevel = null,
};

pub const DiagnosticCode = enum { no_match, invalid_thinking_level };
pub const Diagnostic = struct {
    code: DiagnosticCode,
    pattern: []const u8,
    invalid_suffix: ?[]const u8 = null,
};

pub const ScopeResult = struct {
    scoped_models: []ScopedModel,
    diagnostics: []Diagnostic,

    pub fn deinit(self: *ScopeResult, gpa: std.mem.Allocator) void {
        gpa.free(self.scoped_models);
        gpa.free(self.diagnostics);
        self.* = undefined;
    }
};

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

pub fn parseThinkingLevel(s: []const u8) ?ThinkingLevel {
    return ThinkingLevel.parse(s);
}

/// Alias heuristic used by upstream: `-latest` is an alias; a trailing `-YYYYMMDD` is dated.
pub fn isAlias(id: []const u8) bool {
    if (std.mem.endsWith(u8, id, "-latest")) return true;
    if (id.len >= 9 and id[id.len - 9] == '-') {
        const tail = id[id.len - 8 ..];
        var all_digits = true;
        for (tail) |c| {
            if (c < '0' or c > '9') {
                all_digits = false;
                break;
            }
        }
        if (all_digits) return false;
    }
    return true;
}

fn modelEqual(a: ModelInfo, b: ModelInfo) bool {
    return std.ascii.eqlIgnoreCase(a.providerName(), b.providerName()) and std.mem.eql(u8, a.id, b.id);
}

/// Exact matching semantics from upstream:
/// - canonical provider/id is case-insensitive
/// - provider/id split is accepted
/// - bare ids are accepted only when unique across providers
pub fn findExactModelReferenceMatch(reference_raw: []const u8, models: []const ModelInfo) ?ModelInfo {
    const reference = trim(reference_raw);
    if (reference.len == 0) return null;

    var canonical: ?ModelInfo = null;
    var canonical_count: usize = 0;
    for (models) |m| {
        const slash = std.mem.indexOfScalar(u8, reference, '/');
        if (slash) |idx| {
            const p = trim(reference[0..idx]);
            const id = trim(reference[idx + 1 ..]);
            if (p.len > 0 and id.len > 0 and std.ascii.eqlIgnoreCase(p, m.providerName()) and std.ascii.eqlIgnoreCase(id, m.id)) {
                canonical = m;
                canonical_count += 1;
            }
        }
    }
    if (canonical_count == 1) return canonical;
    if (canonical_count > 1) return null;

    var id_match: ?ModelInfo = null;
    var id_count: usize = 0;
    for (models) |m| {
        if (std.ascii.eqlIgnoreCase(reference, m.id)) {
            id_match = m;
            id_count += 1;
        }
    }
    return if (id_count == 1) id_match else null;
}

fn betterMatch(candidate: ModelInfo, current: ?ModelInfo) bool {
    const existing = current orelse return true;
    const ca = isAlias(candidate.id);
    const ea = isAlias(existing.id);
    if (ca != ea) return ca;
    return std.mem.order(u8, candidate.id, existing.id) == .gt;
}

/// Exact first, then partial id/display matching. Prefer aliases, otherwise latest dated id.
pub fn tryMatchModel(pattern: []const u8, models: []const ModelInfo) ?ModelInfo {
    if (findExactModelReferenceMatch(pattern, models)) |m| return m;

    var best: ?ModelInfo = null;
    for (models) |m| {
        if (containsIgnoreCase(m.id, pattern) or containsIgnoreCase(m.display, pattern)) {
            if (betterMatch(m, best)) best = m;
        }
    }
    return best;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// Parse `<model>[:thinking]`, preserving colon-bearing model IDs by trying the full pattern first.
pub fn parseModelPattern(pattern: []const u8, models: []const ModelInfo, allow_invalid_fallback: bool) ParsedModelResult {
    if (tryMatchModel(pattern, models)) |m| return .{ .model = m };

    const colon = std.mem.lastIndexOfScalar(u8, pattern, ':') orelse return .{};
    const prefix = pattern[0..colon];
    const suffix = pattern[colon + 1 ..];

    if (parseThinkingLevel(suffix)) |thinking| {
        const inner = parseModelPattern(prefix, models, allow_invalid_fallback);
        if (inner.model != null) {
            return .{
                .model = inner.model,
                .thinking_level = if (inner.warning == null) thinking else null,
                .warning = inner.warning,
            };
        }
        return inner;
    }

    if (!allow_invalid_fallback) return .{};
    const inner = parseModelPattern(prefix, models, allow_invalid_fallback);
    if (inner.model != null) {
        return .{
            .model = inner.model,
            .warning = .{ .invalid_suffix = suffix, .pattern = pattern },
        };
    }
    return inner;
}

fn hasGlob(pattern: []const u8) bool {
    return std.mem.indexOfAny(u8, pattern, "*?[") != null;
}

/// Small minimatch-compatible subset needed by Pi model scopes: `*`, `?`, and `[abc]`/`[a-z]`.
/// Matching is ASCII case-insensitive, like upstream's `{ nocase: true }`.
pub fn globMatch(pattern: []const u8, text: []const u8) bool {
    return globAt(pattern, 0, text, 0);
}

fn globAt(pattern: []const u8, pi: usize, text: []const u8, ti: usize) bool {
    if (pi == pattern.len) return ti == text.len;

    if (pattern[pi] == '*') {
        var next = pi;
        while (next < pattern.len and pattern[next] == '*') : (next += 1) {}
        if (next == pattern.len) return true;
        var j = ti;
        while (j <= text.len) : (j += 1) if (globAt(pattern, next, text, j)) return true;
        return false;
    }

    if (ti == text.len) return false;
    if (pattern[pi] == '?') return globAt(pattern, pi + 1, text, ti + 1);

    if (pattern[pi] == '[') {
        var end = pi + 1;
        while (end < pattern.len and pattern[end] != ']') : (end += 1) {}
        if (end == pattern.len) {
            return std.ascii.toLower(pattern[pi]) == std.ascii.toLower(text[ti]) and globAt(pattern, pi + 1, text, ti + 1);
        }
        var matched = false;
        var k = pi + 1;
        const tc = std.ascii.toLower(text[ti]);
        while (k < end) {
            if (k + 2 < end and pattern[k + 1] == '-') {
                const lo = std.ascii.toLower(pattern[k]);
                const hi = std.ascii.toLower(pattern[k + 2]);
                if (tc >= lo and tc <= hi) matched = true;
                k += 3;
            } else {
                if (tc == std.ascii.toLower(pattern[k])) matched = true;
                k += 1;
            }
        }
        return matched and globAt(pattern, end + 1, text, ti + 1);
    }

    return std.ascii.toLower(pattern[pi]) == std.ascii.toLower(text[ti]) and globAt(pattern, pi + 1, text, ti + 1);
}

fn alreadyScoped(items: []const ScopedModel, model: ModelInfo) bool {
    for (items) |sm| if (modelEqual(sm.model, model)) return true;
    return false;
}

/// Resolve model scope patterns with the same exact/fuzzy/glob/colon precedence as upstream Pi.
pub fn resolveModelScopeFromModels(gpa: std.mem.Allocator, patterns: []const []const u8, models: []const ModelInfo) !ScopeResult {
    var scoped: std.ArrayList(ScopedModel) = .empty;
    errdefer scoped.deinit(gpa);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    errdefer diagnostics.deinit(gpa);

    for (patterns) |pattern| {
        if (hasGlob(pattern)) {
            var glob_pattern = pattern;
            var thinking: ?ThinkingLevel = null;
            if (std.mem.lastIndexOfScalar(u8, pattern, ':')) |colon| {
                if (parseThinkingLevel(pattern[colon + 1 ..])) |level| {
                    thinking = level;
                    glob_pattern = pattern[0..colon];
                }
            }

            if (findExactModelReferenceMatch(glob_pattern, models)) |exact| {
                if (!alreadyScoped(scoped.items, exact)) try scoped.append(gpa, .{ .model = exact, .thinking_level = thinking });
                continue;
            }

            var match_count: usize = 0;
            for (models) |m| {
                var full_buf: [512]u8 = undefined;
                const full = std.fmt.bufPrint(&full_buf, "{s}/{s}", .{ m.providerName(), m.id }) catch m.id;
                if (globMatch(glob_pattern, full) or globMatch(glob_pattern, m.id)) {
                    match_count += 1;
                    if (!alreadyScoped(scoped.items, m)) try scoped.append(gpa, .{ .model = m, .thinking_level = thinking });
                }
            }
            if (match_count == 0) try diagnostics.append(gpa, .{ .code = .no_match, .pattern = pattern });
            continue;
        }

        const parsed = parseModelPattern(pattern, models, true);
        if (parsed.warning) |w| {
            try diagnostics.append(gpa, .{ .code = .invalid_thinking_level, .pattern = pattern, .invalid_suffix = w.invalid_suffix });
        }
        if (parsed.model) |m| {
            if (!alreadyScoped(scoped.items, m)) try scoped.append(gpa, .{ .model = m, .thinking_level = parsed.thinking_level });
        } else {
            try diagnostics.append(gpa, .{ .code = .no_match, .pattern = pattern });
        }
    }

    return .{
        .scoped_models = try scoped.toOwnedSlice(gpa),
        .diagnostics = try diagnostics.toOwnedSlice(gpa),
    };
}

pub const CliError = enum { no_models, unknown_provider, ambiguous_model, model_not_found };
pub const CliWarning = enum { custom_model_id };

pub const ResolveCliModelResult = struct {
    model: ?ModelInfo = null,
    thinking_level: ?ThinkingLevel = null,
    warning: ?CliWarning = null,
    err: ?CliError = null,
};

fn providerRepresented(provider_id: []const u8, models: []const ModelInfo) bool {
    for (models) |m| if (std.ascii.eqlIgnoreCase(m.providerName(), provider_id)) return true;
    return false;
}

fn providerConfigured(provider_id: []const u8, configured: []const []const u8) bool {
    for (configured) |c| if (std.ascii.eqlIgnoreCase(c, provider_id)) return true;
    return false;
}

fn findRawExact(id: []const u8, models: []const ModelInfo, excluded: ?ModelInfo) struct { one: ?ModelInfo, count: usize } {
    var one: ?ModelInfo = null;
    var count: usize = 0;
    for (models) |m| {
        if (excluded) |e| if (modelEqual(m, e)) continue;
        if (std.ascii.eqlIgnoreCase(m.id, id)) {
            one = m;
            count += 1;
        }
    }
    return .{ .one = one, .count = count };
}

/// CLI resolver port: provider/model inference, ambiguity rejection, fuzzy match,
/// colon-thinking parsing, raw slash-bearing ids, and explicit-provider custom ids.
pub fn resolveCliModel(
    cli_provider_raw: ?[]const u8,
    cli_model_raw: ?[]const u8,
    cli_thinking: ?ThinkingLevel,
    models: []const ModelInfo,
    configured_providers: []const []const u8,
) ResolveCliModelResult {
    const cli_model = cli_model_raw orelse return .{};
    if (models.len == 0) return .{ .err = .no_models };

    var provider_id: ?[]const u8 = null;
    if (cli_provider_raw) |raw| {
        if (!providerRepresented(raw, models)) return .{ .err = .unknown_provider };
        provider_id = raw;
    }

    var pattern = cli_model;
    var inferred_provider = false;
    if (provider_id == null) {
        if (std.mem.indexOfScalar(u8, cli_model, '/')) |slash| {
            const prefix = cli_model[0..slash];
            if (providerRepresented(prefix, models)) {
                provider_id = prefix;
                pattern = cli_model[slash + 1 ..];
                inferred_provider = true;
            }
        }
    }

    // Exact raw IDs before fuzzy selection; ambiguity is an error unless exactly one provider has auth.
    if (provider_id == null) {
        var exact_count: usize = 0;
        var exact: ?ModelInfo = null;
        var auth_count: usize = 0;
        var auth_exact: ?ModelInfo = null;
        for (models) |m| {
            if (std.ascii.eqlIgnoreCase(m.id, cli_model)) {
                exact_count += 1;
                exact = m;
                if (providerConfigured(m.providerName(), configured_providers)) {
                    auth_count += 1;
                    auth_exact = m;
                }
            }
        }
        if (exact_count == 1) return .{ .model = exact };
        if (exact_count > 1) {
            if (auth_count == 1) return .{ .model = auth_exact };
            return .{ .err = .ambiguous_model };
        }
    }

    if (cli_provider_raw != null and provider_id != null) {
        const pfx_len = provider_id.?.len + 1;
        if (cli_model.len >= pfx_len and std.ascii.eqlIgnoreCase(cli_model[0 .. pfx_len - 1], provider_id.?) and cli_model[pfx_len - 1] == '/') {
            pattern = cli_model[pfx_len..];
        }
    }

    var candidate_buf: [knownMaxModels()]ModelInfo = undefined;
    var candidate_len: usize = 0;
    for (models) |m| {
        if (provider_id == null or std.ascii.eqlIgnoreCase(m.providerName(), provider_id.?)) {
            if (candidate_len < candidate_buf.len) {
                candidate_buf[candidate_len] = m;
                candidate_len += 1;
            }
        }
    }
    const candidates = candidate_buf[0..candidate_len];
    const parsed = parseModelPattern(pattern, candidates, false);
    if (parsed.model) |m| {
        if (inferred_provider and !providerConfigured(m.providerName(), configured_providers)) {
            const raw = findRawExact(cli_model, models, m);
            if (raw.count > 0) {
                var auth_count: usize = 0;
                var auth: ?ModelInfo = null;
                for (models) |rm| {
                    if (!modelEqual(rm, m) and std.ascii.eqlIgnoreCase(rm.id, cli_model) and providerConfigured(rm.providerName(), configured_providers)) {
                        auth_count += 1;
                        auth = rm;
                    }
                }
                if (auth_count == 1) return .{ .model = auth };
            }
        }
        return .{ .model = m, .thinking_level = if (parsed.thinking_level) |level| m.clampThinkingLevel(level) else null };
    }

    if (inferred_provider) {
        // Full input may itself be a slash-bearing model id (common on OpenRouter/gateways).
        const raw = findRawExact(cli_model, models, null);
        if (raw.count == 1) return .{ .model = raw.one };
        const fallback = parseModelPattern(cli_model, models, false);
        if (fallback.model) |m| return .{ .model = m, .thinking_level = if (fallback.thinking_level) |level| m.clampThinkingLevel(level) else null };
    }

    if (provider_id) |p| {
        var fallback_pattern = pattern;
        var fallback_thinking: ?ThinkingLevel = null;
        if (cli_thinking == null) {
            if (std.mem.lastIndexOfScalar(u8, pattern, ':')) |colon| {
                if (parseThinkingLevel(pattern[colon + 1 ..])) |level| {
                    fallback_pattern = pattern[0..colon];
                    fallback_thinking = level;
                }
            }
        }

        // Explicit providers may use custom model IDs as long as the runtime has that provider.
        var base: ?ModelInfo = null;
        for (models) |m| if (std.ascii.eqlIgnoreCase(m.providerName(), p)) {
            base = m;
            break;
        };
        if (base) |b| {
            var custom = b;
            custom.id = fallback_pattern;
            custom.display = fallback_pattern;
            const requested = cli_thinking orelse fallback_thinking;
            if (requested) |t| {
                if (t != .off) custom.reasoning = true;
            }
            return .{ .model = custom, .thinking_level = fallback_thinking, .warning = .custom_model_id };
        }
    }

    return .{ .err = .model_not_found };
}

fn knownMaxModels() comptime_int {
    // Keeps CLI resolution allocation-free for the static/runtime registry used by pi-zig.
    return providers.known_models.len + 128;
}

// Tests below mirror the behavioral cases in upstream model-resolver.test.ts.
const test_models = [_]ModelInfo{
    .{ .provider = .openai, .id = "gpt-4o", .display = "GPT-4o" },
    .{ .provider = .anthropic, .id = "claude-sonnet-4-5", .display = "Claude Sonnet 4.5", .reasoning = true },
    .{ .provider = .anthropic, .id = "claude-sonnet-4-5-20250929", .display = "Claude Sonnet dated", .reasoning = true },
    .{ .provider = .openrouter, .id = "openai/gpt-4o:extended", .display = "GPT-4o Extended" },
    .{ .provider = .openrouter, .id = "qwen/qwen3-coder:exacto", .display = "Qwen3 Coder Exacto" },
};

test "exact model reference supports canonical provider/model and rejects ambiguous bare id" {
    const models = [_]ModelInfo{
        .{ .provider = .openai, .id = "same", .display = "OpenAI same" },
        .{ .provider = .openrouter, .id = "same", .display = "OpenRouter same" },
    };
    try std.testing.expect(findExactModelReferenceMatch("OPENAI/same", &models).?.provider == .openai);
    try std.testing.expect(findExactModelReferenceMatch("same", &models) == null);
}

test "fuzzy model pattern prefers alias over dated version" {
    const got = tryMatchModel("sonnet", &test_models).?;
    try std.testing.expectEqualStrings("claude-sonnet-4-5", got.id);
}

test "model pattern keeps colon-bearing raw id before thinking parsing" {
    const got = parseModelPattern("openai/gpt-4o:extended", &test_models, false);
    try std.testing.expect(got.model != null);
    try std.testing.expect(got.model.?.provider == .openrouter);
    try std.testing.expectEqualStrings("openai/gpt-4o:extended", got.model.?.id);
    try std.testing.expect(got.thinking_level == null);
}

test "model pattern extracts thinking suffix" {
    const got = parseModelPattern("sonnet:high", &test_models, false);
    try std.testing.expectEqualStrings("claude-sonnet-4-5", got.model.?.id);
    try std.testing.expect(got.thinking_level.? == .high);
}

test "scope resolver handles globs thinking and deduplication" {
    const patterns = [_][]const u8{ "anthropic/*sonnet*:high", "claude-sonnet-4-5" };
    var result = try resolveModelScopeFromModels(std.testing.allocator, &patterns, &test_models);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), result.scoped_models.len);
    try std.testing.expect(result.scoped_models[0].thinking_level.? == .high);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "scope invalid thinking suffix warns and resolves prefix" {
    const patterns = [_][]const u8{"sonnet:turbo"};
    var result = try resolveModelScopeFromModels(std.testing.allocator, &patterns, &test_models);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), result.scoped_models.len);
    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expect(result.diagnostics[0].code == .invalid_thinking_level);
}

test "CLI provider/model split beats slash-bearing gateway ids" {
    const models = [_]ModelInfo{
        .{ .provider = .deepseek, .id = "glm-5", .display = "GLM 5" },
        .{ .provider = .openrouter, .id = "deepseek/glm-5", .display = "Gateway GLM 5" },
    };
    const configured = [_][]const u8{ "deepseek", "openrouter" };
    const got = resolveCliModel(null, "deepseek/glm-5", null, &models, &configured);
    try std.testing.expect(got.err == null);
    try std.testing.expect(got.model.?.provider == .deepseek);
    try std.testing.expectEqualStrings("glm-5", got.model.?.id);
}

test "CLI ambiguous bare exact id prefers sole authenticated provider" {
    const models = [_]ModelInfo{
        .{ .provider = .openai, .id = "shared", .display = "Shared" },
        .{ .provider = .openrouter, .id = "shared", .display = "Shared" },
    };
    const configured = [_][]const u8{"openrouter"};
    const got = resolveCliModel(null, "shared", null, &models, &configured);
    try std.testing.expect(got.model.?.provider == .openrouter);
}

test "CLI ambiguous bare exact id errors without unique authenticated provider" {
    const models = [_]ModelInfo{
        .{ .provider = .openai, .id = "shared", .display = "Shared" },
        .{ .provider = .openrouter, .id = "shared", .display = "Shared" },
    };
    const got = resolveCliModel(null, "shared", null, &models, &.{});
    try std.testing.expect(got.model == null);
    try std.testing.expect(got.err.? == .ambiguous_model);
}

test "CLI explicit provider custom model strips thinking suffix" {
    const models = [_]ModelInfo{.{ .provider = .openrouter, .id = "base", .display = "Base" }};
    const got = resolveCliModel("openrouter", "zai-org/GLM-5.1-FP8:high", null, &models, &.{"openrouter"});
    try std.testing.expect(got.err == null);
    try std.testing.expectEqualStrings("zai-org/GLM-5.1-FP8", got.model.?.id);
    try std.testing.expect(got.model.?.reasoning);
    try std.testing.expect(got.thinking_level.? == .high);
}

test "glob matcher supports case insensitive star question and ranges" {
    try std.testing.expect(globMatch("anthropic/*SONNET*", "anthropic/claude-sonnet-4"));
    try std.testing.expect(globMatch("gpt-4?", "gpt-4o"));
    try std.testing.expect(globMatch("model-[a-c]", "model-B"));
    try std.testing.expect(!globMatch("model-[a-c]", "model-z"));
}

test "CLI resolves arbitrary models.json provider identity without collapsing transport" {
    const models = [_]ModelInfo{
        .{ .provider = .openai, .provider_id = "my-company-proxy", .id = "corp-model", .display = "Corp Model" },
    };
    const configured = [_][]const u8{"my-company-proxy"};
    const got = resolveCliModel("my-company-proxy", "corp-model", null, &models, &configured);
    try std.testing.expect(got.err == null);
    try std.testing.expectEqualStrings("my-company-proxy", got.model.?.providerName());
    try std.testing.expectEqualStrings("corp-model", got.model.?.id);
    try std.testing.expect(got.model.?.provider == .openai);
}
