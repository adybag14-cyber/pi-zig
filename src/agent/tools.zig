//! Built-in coding tools: read, write, edit, bash, grep, find, ls.
const std = @import("std");
const tool_manager = @import("tool_manager.zig");
const Io = std.Io;
const builtin = @import("builtin");
const truncate_mod = @import("truncate.zig");
const image_process = @import("../ai/image_process.zig");

pub const ToolCost = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    total: f64 = 0,
};

/// Accounting reported by the tool itself. Kept separate from ai.Usage so the
/// dependency-free tool package remains directly testable as a root module.
pub const ToolImage = struct {
    data_b64: []u8,
    mime_type: []u8,

    pub fn deinit(self: *ToolImage, gpa: std.mem.Allocator) void {
        gpa.free(self.data_b64);
        gpa.free(self.mime_type);
        self.* = undefined;
    }
};

pub fn cloneImages(gpa: std.mem.Allocator, images: []const ToolImage) ![]ToolImage {
    if (images.len == 0) return &.{};
    const out = try gpa.alloc(ToolImage, images.len);
    errdefer gpa.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |*image| image.deinit(gpa);
    for (images, 0..) |image, index| {
        out[index] = .{
            .data_b64 = try gpa.dupe(u8, image.data_b64),
            .mime_type = try gpa.dupe(u8, image.mime_type),
        };
        initialized += 1;
    }
    return out;
}

pub fn deinitImages(gpa: std.mem.Allocator, images: []ToolImage) void {
    for (images) |*image| image.deinit(gpa);
    if (images.len > 0) gpa.free(images);
}

pub const ToolUsage = struct {
    input: u64 = 0,
    output: u64 = 0,
    cache_read: u64 = 0,
    cache_write: u64 = 0,
    cache_write_1h: ?u64 = null,
    reasoning: ?u64 = null,
    total_tokens: u64 = 0,
    cost: ToolCost = .{},

    pub fn total(self: ToolUsage) u64 {
        if (self.total_tokens > 0) return self.total_tokens;
        return self.input + self.output + self.cache_read + self.cache_write;
    }
};

pub const ToolUpdate = struct {
    content: []u8,
    is_error: bool = false,
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    /// Additional image blocks, preserving every image returned by rich tools.
    /// The legacy singular fields above remain accepted for checkpoint/session
    /// compatibility and are serialized before this array when both are set.
    images: []ToolImage = &.{},
    details_json: ?[]u8 = null,
    /// Optional tool-local accounting. This is distinct from the surrounding
    /// model request usage and mirrors upstream AgentToolResult.usage.
    usage: ?ToolUsage = null,
    /// Tool names introduced by this partial result. Kept for fidelity even
    /// though most tools only publish the names on their terminal result.
    added_tool_names: []const []const u8 = &.{},
    /// This update was already delivered to the primary sink while an
    /// extension worker was executing. Replay it only to lifecycle observers.
    observer_deferred: bool = false,

    pub fn deinit(self: *ToolUpdate, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        if (self.image_b64) |data| gpa.free(data);
        if (self.image_mime) |mime| gpa.free(mime);
        deinitImages(gpa, self.images);
        if (self.details_json) |details| gpa.free(details);
        if (self.added_tool_names.len > 0) {
            for (self.added_tool_names) |name| gpa.free(name);
            gpa.free(self.added_tool_names);
        }
        self.* = undefined;
    }
};

pub const ToolResult = struct {
    content: []u8,
    is_error: bool,
    /// Optional binary image result encoded as base64. Built-ins are text-only
    /// today, but external/future tools can return vision content losslessly.
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    /// Additional image blocks. Together with the legacy singular image this
    /// models the upstream `(TextContent | ImageContent)[]` result without
    /// silently dropping the second and subsequent images.
    images: []ToolImage = &.{},
    /// Structured extension/native details used by terminal renderers and
    /// lifecycle observers. These never enter model context directly.
    details_json: ?[]u8 = null,
    /// Usage produced by the tool itself, not by the main assistant request.
    usage: ?ToolUsage = null,
    /// Tool definitions that become available from this transcript boundary.
    added_tool_names: []const []const u8 = &.{},
    /// Ordered partial results produced while the tool executes. The current
    /// bridge delivers them before the final event, retaining upstream event
    /// and renderer semantics even when a script runtime buffers transport I/O.
    updates: []ToolUpdate = &.{},
    /// Hint that the agent should stop after this tool batch. The batch only
    /// terminates when every finalized tool result sets this true.
    terminate: bool = false,

    pub fn deinit(self: *ToolResult, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        if (self.image_b64) |data| gpa.free(data);
        if (self.image_mime) |mime| gpa.free(mime);
        deinitImages(gpa, self.images);
        if (self.details_json) |details| gpa.free(details);
        if (self.added_tool_names.len > 0) {
            for (self.added_tool_names) |name| gpa.free(name);
            gpa.free(self.added_tool_names);
        }
        for (self.updates) |*update| update.deinit(gpa);
        if (self.updates.len > 0) gpa.free(self.updates);
        self.* = undefined;
    }
};

pub const ToolProgressFn = *const fn (?*anyopaque, []const u8) void;

pub const ToolContext = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    /// Parent process environment. When present, bash receives a cloned map
    /// augmented with pi's live session metadata.
    environ: ?*const std.process.Environ.Map = null,
    session_id: ?[]const u8 = null,
    session_file: ?[]const u8 = null,
    provider_name: ?[]const u8 = null,
    model_id: ?[]const u8 = null,
    reasoning_level: ?[]const u8 = null,
    /// Original `images.autoResize` policy for built-in read results.
    auto_resize_images: bool = true,
    /// Cooperative abort: checked around long tools (bash).
    abort_flag: ?*bool = null,
    /// Optional raw stdout/stderr progress callback used by direct RPC bash.
    progress_fn: ?ToolProgressFn = null,
    progress_ctx: ?*anyopaque = null,
};

pub const ToolName = enum {
    read,
    write,
    edit,
    bash,
    powershell,
    grep,
    find,
    ls,

    pub fn fromString(s: []const u8) ?ToolName {
        inline for (std.meta.fields(ToolName)) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }

    pub fn asString(self: ToolName) []const u8 {
        return @tagName(self);
    }
};

pub const default_tool_names = [_][]const u8{ "read", "write", "edit", "bash", "grep", "find", "ls" };
pub const all_tool_names = default_tool_names ++ [_][]const u8{"powershell"};

pub fn isBuiltin(name: []const u8) bool {
    for (all_tool_names) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}

pub const ToolFilter = struct {
    /// If non-null, only these tools are enabled.
    allow: ?[]const []const u8 = null,
    /// Settings-level defaultTools selects native built-ins only. Extension and
    /// SDK tools stay enabled unless an explicit `allow` list is supplied.
    builtin_allow: ?[]const []const u8 = &default_tool_names,
    /// Tools to exclude (applied after allow).
    exclude: ?[]const []const u8 = null,
    no_tools: bool = false,

    pub fn isEnabled(self: ToolFilter, name: []const u8) bool {
        if (self.no_tools) return false;
        if (self.allow) |a| {
            var found = false;
            for (a) |t| {
                if (std.mem.eql(u8, t, name)) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        } else if (isBuiltin(name)) {
            if (self.builtin_allow) |a| {
                var found = false;
                for (a) |t| if (std.mem.eql(u8, t, name)) {
                    found = true;
                    break;
                };
                if (!found) return false;
            }
        }
        if (self.exclude) |ex| {
            for (ex) |t| {
                if (std.mem.eql(u8, t, name)) return false;
            }
        }
        return true;
    }

    pub fn enabledNames(self: ToolFilter, gpa: std.mem.Allocator) ![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        errdefer list.deinit(gpa);
        for (all_tool_names) |n| {
            if (self.isEnabled(n)) try list.append(gpa, n);
        }
        return try list.toOwnedSlice(gpa);
    }
};

// Schemas aligned with upstream pi-coding-agent tools (plus legacy aliases accepted at execute time).
const schema_read =
    \\{"type":"function","function":{"name":"read","description":"Read a file from the filesystem. Supports optional 1-indexed line offset and limit.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to the file to read (relative or absolute)"},"offset":{"type":"number","description":"Line number to start reading from (1-indexed)"},"limit":{"type":"number","description":"Maximum number of lines to read"}},"required":["path"]}}}
;
const schema_write =
    \\{"type":"function","function":{"name":"write","description":"Write content to a file, creating parent directories as needed.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}
;
const schema_edit =
    \\{"type":"function","function":{"name":"edit","description":"Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to the file to edit (relative or absolute)"},"edits":{"type":"array","description":"One or more targeted replacements. Each edit is matched against the original file, not incrementally.","items":{"type":"object","properties":{"oldText":{"type":"string","description":"Exact text for one targeted replacement."},"newText":{"type":"string","description":"Replacement text for this targeted edit."}},"required":["oldText","newText"]}}},"required":["path","edits"]}}}
;
const schema_bash =
    \\{"type":"function","function":{"name":"bash","description":"Run a shell command and return stdout, stderr, and exit code. Optional timeout in seconds.","parameters":{"type":"object","properties":{"command":{"type":"string"},"timeout":{"type":"number","description":"Timeout in seconds (default 120)"}},"required":["command"]}}}
;
const schema_powershell =
    \\{"type":"function","function":{"name":"powershell","description":"Execute PowerShell commands and return stdout, stderr, and exit code. Optional timeout in seconds.","parameters":{"type":"object","properties":{"command":{"type":"string"},"timeout":{"type":"number","description":"Timeout in seconds (default 120)"}},"required":["command"]}}}
;
const schema_grep =
    \\{"type":"function","function":{"name":"grep","description":"Search files for a pattern. Uses regex when possible (rg if available); set literal=true for substring match.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"},"ignoreCase":{"type":"boolean"},"literal":{"type":"boolean"},"limit":{"type":"number"},"context":{"type":"number","description":"Lines of context before/after match"}},"required":["pattern"]}}}
;
const schema_find =
    \\{"type":"function","function":{"name":"find","description":"Find files by glob-like pattern (* and **).","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"limit":{"type":"number"}},"required":["pattern"]}}}
;
const schema_ls =
    \\{"type":"function","function":{"name":"ls","description":"List directory entries.","parameters":{"type":"object","properties":{"path":{"type":"string"},"limit":{"type":"number"}},"required":[]}}}
;

fn schemaFor(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "read")) return schema_read;
    if (std.mem.eql(u8, name, "write")) return schema_write;
    if (std.mem.eql(u8, name, "edit")) return schema_edit;
    if (std.mem.eql(u8, name, "bash")) return schema_bash;
    if (std.mem.eql(u8, name, "powershell")) return schema_powershell;
    if (std.mem.eql(u8, name, "grep")) return schema_grep;
    if (std.mem.eql(u8, name, "find")) return schema_find;
    if (std.mem.eql(u8, name, "ls")) return schema_ls;
    return null;
}

pub const ToolSchemaOptions = struct {
    /// Upstream exposes strict JSON-schema preference for the four default
    /// coding tools only when PI_EXPERIMENTAL=1. Providers that advertise
    /// strict-tool support consume this metadata; others safely omit it.
    experimental_strict: bool = false,
};

/// OpenAI-compatible tools array for enabled native tools (caller frees).
pub fn toolSchemasJsonWithOptions(gpa: std.mem.Allocator, filter: ToolFilter, options: ToolSchemaOptions) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "[");
    var first = true;
    for (all_tool_names) |n| {
        if (!filter.isEnabled(n)) continue;
        const schema = schemaFor(n) orelse continue;
        if (!first) try out.append(gpa, ',');
        first = false;
        const strict_default = options.experimental_strict and
            (std.mem.eql(u8, n, "read") or std.mem.eql(u8, n, "write") or std.mem.eql(u8, n, "edit") or std.mem.eql(u8, n, "bash"));
        if (strict_default) {
            std.debug.assert(schema.len > 0 and schema[schema.len - 1] == '}');
            try out.appendSlice(gpa, schema[0 .. schema.len - 1]);
            try out.appendSlice(gpa, ",\"constrainedSampling\":{\"type\":\"json_schema\",\"strict\":\"prefer\"}}");
        } else {
            try out.appendSlice(gpa, schema);
        }
    }
    try out.appendSlice(gpa, "]");
    return try out.toOwnedSlice(gpa);
}

pub fn toolSchemasJson(gpa: std.mem.Allocator, filter: ToolFilter) ![]u8 {
    return toolSchemasJsonWithOptions(gpa, filter, .{});
}

/// Default full schema JSON (all tools) as a static string for simple cases.
pub const tool_schemas_json_all =
    \\[{"type":"function","function":{"name":"read","description":"Read a file from the filesystem.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to the file to read"}},"required":["path"]}}},{"type":"function","function":{"name":"write","description":"Write content to a file, creating parent directories as needed.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},{"type":"function","function":{"name":"edit","description":"Apply exact text replacements in a file.","parameters":{"type":"object","properties":{"path":{"type":"string"},"edits":{"type":"array","items":{"type":"object","properties":{"oldText":{"type":"string"},"newText":{"type":"string"}},"required":["oldText","newText"]}}},"required":["path","edits"]}}},{"type":"function","function":{"name":"bash","description":"Run a shell command and return stdout, stderr, and exit code.","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},{"type":"function","function":{"name":"grep","description":"Search files for a pattern.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"},"ignoreCase":{"type":"boolean"},"limit":{"type":"number"}},"required":["pattern"]}}},{"type":"function","function":{"name":"find","description":"Find files by glob-like pattern.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"limit":{"type":"number"}},"required":["pattern"]}}},{"type":"function","function":{"name":"ls","description":"List directory entries.","parameters":{"type":"object","properties":{"path":{"type":"string"},"limit":{"type":"number"}},"required":[]}}}]
;

/// Upstream-compatible pre-validation compatibility shims. Returns owned JSON
/// only when arguments were transformed; null means use the original bytes.
pub fn prepareArguments(gpa: std.mem.Allocator, name: []const u8, arguments_json: []const u8) !?[]u8 {
    if (!std.mem.eql(u8, name, "edit")) return null;
    return prepareEditArgumentsJson(gpa, arguments_json);
}

/// Validate a tool call against the exact OpenAI-compatible schema array sent
/// to the model. Returns an owned human-readable error on validation failure,
/// or null when the call is valid. Compatibility preparation belongs before
/// this function; before-tool mutations intentionally happen after it and are
/// not revalidated, matching upstream pi-agent semantics.
pub fn validateArgumentsAgainstToolSchemas(
    gpa: std.mem.Allocator,
    tools_json: []const u8,
    tool_name: []const u8,
    arguments_json: []const u8,
) !?[]u8 {
    var tools_doc = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch {
        return try std.fmt.allocPrint(gpa, "Tool schema catalog is invalid JSON while validating \"{s}\"", .{tool_name});
    };
    defer tools_doc.deinit();
    if (tools_doc.value != .array) {
        return try std.fmt.allocPrint(gpa, "Tool schema catalog is not an array while validating \"{s}\"", .{tool_name});
    }

    var schema: ?std.json.Value = null;
    for (tools_doc.value.array.items) |item| {
        if (item != .object) continue;
        const function = item.object.get("function") orelse continue;
        if (function != .object) continue;
        const name = function.object.get("name") orelse continue;
        if (name != .string or !std.mem.eql(u8, name.string, tool_name)) continue;
        schema = function.object.get("parameters") orelse std.json.Value{ .object = function.object };
        break;
    }
    if (schema == null) return try std.fmt.allocPrint(gpa, "Tool {s} not found", .{tool_name});

    var args_doc = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch {
        return try std.fmt.allocPrint(
            gpa,
            "Validation failed for tool \"{s}\":\n  - root: invalid JSON\n\nReceived arguments:\n{s}",
            .{ tool_name, arguments_json },
        );
    };
    defer args_doc.deinit();

    if (try validateSchemaValue(gpa, schema.?, args_doc.value, "root")) |detail| {
        defer gpa.free(detail);
        return try std.fmt.allocPrint(
            gpa,
            "Validation failed for tool \"{s}\":\n  - {s}\n\nReceived arguments:\n{s}",
            .{ tool_name, detail, arguments_json },
        );
    }
    return null;
}

fn validateSchemaValue(
    gpa: std.mem.Allocator,
    schema: std.json.Value,
    value: std.json.Value,
    path: []const u8,
) !?[]u8 {
    if (schema != .object) return null;
    const object = schema.object;

    if (object.get("allOf")) |branches| {
        if (branches == .array) for (branches.array.items) |branch| {
            if (try validateSchemaValue(gpa, branch, value, path)) |err| return err;
        };
    }
    if (object.get("anyOf")) |branches| {
        if (branches == .array and branches.array.items.len > 0) {
            var matched = false;
            for (branches.array.items) |branch| {
                if (try validateSchemaValue(gpa, branch, value, path)) |err| {
                    gpa.free(err);
                } else {
                    matched = true;
                    break;
                }
            }
            if (!matched) return try std.fmt.allocPrint(gpa, "{s}: does not match any allowed schema", .{path});
        }
    }
    if (object.get("oneOf")) |branches| {
        if (branches == .array and branches.array.items.len > 0) {
            var matches: usize = 0;
            for (branches.array.items) |branch| {
                if (try validateSchemaValue(gpa, branch, value, path)) |err| {
                    gpa.free(err);
                } else matches += 1;
            }
            if (matches != 1) return try std.fmt.allocPrint(gpa, "{s}: must match exactly one allowed schema", .{path});
        }
    }

    if (object.get("type")) |type_spec| {
        if (!schemaTypeMatches(type_spec, value)) {
            return try std.fmt.allocPrint(gpa, "{s}: expected {s}, received {s}", .{ path, schemaTypeDescription(type_spec), jsonValueTypeName(value) });
        }
    }

    if (object.get("const")) |constant| {
        if (!jsonValueEqual(constant, value)) return try std.fmt.allocPrint(gpa, "{s}: value does not match const", .{path});
    }
    if (object.get("enum")) |choices| {
        if (choices == .array) {
            var matched = false;
            for (choices.array.items) |choice| if (jsonValueEqual(choice, value)) {
                matched = true;
                break;
            };
            if (!matched) return try std.fmt.allocPrint(gpa, "{s}: value is not in enum", .{path});
        }
    }

    if (value == .object) {
        if (object.get("required")) |required| {
            if (required == .array) for (required.array.items) |required_name| {
                if (required_name != .string) continue;
                if (!value.object.contains(required_name.string)) {
                    const child = try childPath(gpa, path, required_name.string);
                    defer gpa.free(child);
                    return try std.fmt.allocPrint(gpa, "{s}: required property is missing", .{child});
                }
            };
        }
        if (object.get("properties")) |properties| {
            if (properties == .object) {
                var it = properties.object.iterator();
                while (it.next()) |entry| {
                    if (value.object.get(entry.key_ptr.*)) |child_value| {
                        const child = try childPath(gpa, path, entry.key_ptr.*);
                        defer gpa.free(child);
                        if (try validateSchemaValue(gpa, entry.value_ptr.*, child_value, child)) |err| return err;
                    }
                }
                if (object.get("additionalProperties")) |additional| {
                    if (additional == .bool and !additional.bool) {
                        var actual = value.object.iterator();
                        while (actual.next()) |entry| {
                            if (!properties.object.contains(entry.key_ptr.*)) {
                                const child = try childPath(gpa, path, entry.key_ptr.*);
                                defer gpa.free(child);
                                return try std.fmt.allocPrint(gpa, "{s}: additional property is not allowed", .{child});
                            }
                        }
                    } else if (additional == .object) {
                        var actual = value.object.iterator();
                        while (actual.next()) |entry| {
                            if (properties.object.contains(entry.key_ptr.*)) continue;
                            const child = try childPath(gpa, path, entry.key_ptr.*);
                            defer gpa.free(child);
                            if (try validateSchemaValue(gpa, additional, entry.value_ptr.*, child)) |err| return err;
                        }
                    }
                }
            }
        }
    }

    if (value == .array) {
        if (object.get("minItems")) |minimum| if (jsonNonNegativeUsize(minimum)) |n| {
            if (value.array.items.len < n) return try std.fmt.allocPrint(gpa, "{s}: expected at least {d} items", .{ path, n });
        };
        if (object.get("maxItems")) |maximum| if (jsonNonNegativeUsize(maximum)) |n| {
            if (value.array.items.len > n) return try std.fmt.allocPrint(gpa, "{s}: expected at most {d} items", .{ path, n });
        };
        if (object.get("items")) |item_schema| {
            for (value.array.items, 0..) |item, index| {
                const child = try std.fmt.allocPrint(gpa, "{s}[{d}]", .{ path, index });
                defer gpa.free(child);
                if (try validateSchemaValue(gpa, item_schema, item, child)) |err| return err;
            }
        }
    }

    if (value == .string) {
        if (object.get("minLength")) |minimum| if (jsonNonNegativeUsize(minimum)) |n| {
            const length = std.unicode.utf8CountCodepoints(value.string) catch value.string.len;
            if (length < n) {
                return try std.fmt.allocPrint(gpa, "{s}: string is shorter than {d} characters", .{ path, n });
            }
        };
        if (object.get("maxLength")) |maximum| if (jsonNonNegativeUsize(maximum)) |n| {
            const length = std.unicode.utf8CountCodepoints(value.string) catch value.string.len;
            if (length > n) {
                return try std.fmt.allocPrint(gpa, "{s}: string is longer than {d} characters", .{ path, n });
            }
        };
    }

    const numeric = jsonNumber(value);
    if (numeric) |number| {
        if (object.get("minimum")) |minimum| if (jsonNumber(minimum)) |n| {
            if (number < n) return try std.fmt.allocPrint(gpa, "{s}: must be >= {d}", .{ path, n });
        };
        if (object.get("maximum")) |maximum| if (jsonNumber(maximum)) |n| {
            if (number > n) return try std.fmt.allocPrint(gpa, "{s}: must be <= {d}", .{ path, n });
        };
        if (object.get("exclusiveMinimum")) |minimum| if (jsonNumber(minimum)) |n| {
            if (number <= n) return try std.fmt.allocPrint(gpa, "{s}: must be > {d}", .{ path, n });
        };
        if (object.get("exclusiveMaximum")) |maximum| if (jsonNumber(maximum)) |n| {
            if (number >= n) return try std.fmt.allocPrint(gpa, "{s}: must be < {d}", .{ path, n });
        };
    }
    return null;
}

fn childPath(gpa: std.mem.Allocator, parent: []const u8, child: []const u8) ![]u8 {
    if (std.mem.eql(u8, parent, "root")) return try gpa.dupe(u8, child);
    return try std.fmt.allocPrint(gpa, "{s}.{s}", .{ parent, child });
}

fn schemaTypeMatches(type_spec: std.json.Value, value: std.json.Value) bool {
    if (type_spec == .string) return jsonValueMatchesType(value, type_spec.string);
    if (type_spec == .array) {
        for (type_spec.array.items) |candidate| {
            if (candidate == .string and jsonValueMatchesType(value, candidate.string)) return true;
        }
    }
    return true;
}

fn schemaTypeDescription(type_spec: std.json.Value) []const u8 {
    if (type_spec == .string) return type_spec.string;
    if (type_spec == .array) return "one of the declared types";
    return "declared type";
}

fn jsonValueMatchesType(value: std.json.Value, expected: []const u8) bool {
    if (std.mem.eql(u8, expected, "object")) return value == .object;
    if (std.mem.eql(u8, expected, "array")) return value == .array;
    if (std.mem.eql(u8, expected, "string")) return value == .string;
    if (std.mem.eql(u8, expected, "number")) return value == .integer or value == .float or value == .number_string;
    if (std.mem.eql(u8, expected, "integer")) return value == .integer;
    if (std.mem.eql(u8, expected, "boolean")) return value == .bool;
    if (std.mem.eql(u8, expected, "null")) return value == .null;
    return true;
}

fn jsonValueTypeName(value: std.json.Value) []const u8 {
    return switch (value) {
        .object => "object",
        .array => "array",
        .string => "string",
        .integer => "integer",
        .float, .number_string => "number",
        .bool => "boolean",
        .null => "null",
    };
}

fn jsonNonNegativeUsize(value: std.json.Value) ?usize {
    return switch (value) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        .float => |n| if (n >= 0 and std.math.isFinite(n)) @intFromFloat(n) else null,
        else => null,
    };
}

fn jsonNumber(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| if (std.math.isFinite(n)) n else null,
        .number_string => |s| std.fmt.parseFloat(f64, s) catch null,
        else => null,
    };
}

fn jsonValueEqual(a: std.json.Value, b: std.json.Value) bool {
    if (jsonNumber(a)) |an| if (jsonNumber(b)) |bn| return an == bn;
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => |v| v == b.bool,
        .integer => |v| v == b.integer,
        .float => |v| v == b.float,
        .number_string => |v| std.mem.eql(u8, v, b.number_string),
        .string => |v| std.mem.eql(u8, v, b.string),
        .array => |items| blk: {
            if (items.items.len != b.array.items.len) break :blk false;
            for (items.items, b.array.items) |av, bv| if (!jsonValueEqual(av, bv)) break :blk false;
            break :blk true;
        },
        .object => |map| blk: {
            if (map.count() != b.object.count()) break :blk false;
            var it = map.iterator();
            while (it.next()) |entry| {
                const other = b.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!jsonValueEqual(entry.value_ptr.*, other)) break :blk false;
            }
            break :blk true;
        },
    };
}

fn prepareEditArgumentsJson(gpa: std.mem.Allocator, arguments_json: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;

    const old_v = obj.get("oldText") orelse obj.get("old_string");
    const new_v = obj.get("newText") orelse obj.get("new_string");
    const has_legacy_pair = old_v != null and new_v != null and old_v.? == .string and new_v.? == .string;

    var parsed_string_edits: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed_string_edits) |*owned| owned.deinit();
    var edits_value: ?std.json.Value = obj.get("edits");
    var converted_string = false;
    if (edits_value) |ev| {
        if (ev == .string) {
            const p = std.json.parseFromSlice(std.json.Value, gpa, ev.string, .{}) catch null;
            if (p) |owned_value| {
                if (owned_value.value == .array) {
                    parsed_string_edits = owned_value;
                    edits_value = parsed_string_edits.?.value;
                    converted_string = true;
                } else {
                    var tmp = owned_value;
                    tmp.deinit();
                }
            }
        }
    }

    if (!has_legacy_pair and !converted_string) return null;

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('{');
    var first = true;
    if (obj.get("path")) |path_v| {
        try out.writer.writeAll("\"path\":");
        try std.json.Stringify.value(path_v, .{}, &out.writer);
        first = false;
    }
    if (!first) try out.writer.writeByte(',');
    try out.writer.writeAll("\"edits\":[");
    var wrote_edit = false;
    if (edits_value) |ev| {
        if (ev == .array) {
            for (ev.array.items) |item| {
                if (wrote_edit) try out.writer.writeByte(',');
                try std.json.Stringify.value(item, .{}, &out.writer);
                wrote_edit = true;
            }
        } else if (!converted_string and !has_legacy_pair) {
            return null;
        }
    }
    if (has_legacy_pair) {
        if (wrote_edit) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"oldText\":");
        try std.json.Stringify.value(old_v.?.string, .{}, &out.writer);
        try out.writer.writeAll(",\"newText\":");
        try std.json.Stringify.value(new_v.?.string, .{}, &out.writer);
        try out.writer.writeByte('}');
    }
    try out.writer.writeAll("]}");
    return try out.toOwnedSlice();
}

pub fn execute(ctx: ToolContext, name: []const u8, arguments_json: []const u8) !ToolResult {
    if (std.mem.eql(u8, name, "read")) return executeRead(ctx, arguments_json);
    if (std.mem.eql(u8, name, "write")) return executeWrite(ctx, arguments_json);
    if (std.mem.eql(u8, name, "edit")) return executeEdit(ctx, arguments_json);
    if (std.mem.eql(u8, name, "bash")) return executeBash(ctx, arguments_json);
    if (std.mem.eql(u8, name, "powershell")) return executePowerShell(ctx, arguments_json);
    if (std.mem.eql(u8, name, "grep")) return executeGrep(ctx, arguments_json);
    if (std.mem.eql(u8, name, "find")) return executeFind(ctx, arguments_json);
    if (std.mem.eql(u8, name, "ls")) return executeLs(ctx, arguments_json);
    return try errMsg(ctx.gpa, "unknown tool: {s}", .{name});
}

fn ownedResult(msg: []u8, is_error: bool) ToolResult {
    return .{ .content = msg, .is_error = is_error };
}

/// Apply upstream-aligned output truncation (2000 lines / 50KB) to tool output.
/// Takes ownership of `msg` and may free/replace it.
fn maybeTruncate(gpa: std.mem.Allocator, msg: []u8, is_error: bool) !ToolResult {
    // Errors stay short; still cap pathological messages.
    if (is_error and msg.len < 4096) return ownedResult(msg, true);
    const truncated = try truncate_mod.apply(gpa, msg);
    gpa.free(msg);
    return ownedResult(truncated, is_error);
}

fn errMsg(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ToolResult {
    return ownedResult(try std.fmt.allocPrint(gpa, fmt, args), true);
}

fn okMsg(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ToolResult {
    return ownedResult(try std.fmt.allocPrint(gpa, fmt, args), false);
}

fn resolvePath(gpa: std.mem.Allocator, cwd: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return try gpa.dupe(u8, path);
    return try std.fs.path.join(gpa, &.{ cwd, path });
}

fn parseStringField(gpa: std.mem.Allocator, arguments_json: []const u8, field: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const v = parsed.value.object.get(field) orelse return null;
    if (v != .string) return null;
    return try gpa.dupe(u8, v.string);
}

/// Path field: accepts `path` or upstream alias `file_path`.
fn parsePathField(gpa: std.mem.Allocator, arguments_json: []const u8) !?[]u8 {
    if (try parseStringField(gpa, arguments_json, "path")) |p| return p;
    return try parseStringField(gpa, arguments_json, "file_path");
}

fn parseBoolField(gpa: std.mem.Allocator, arguments_json: []const u8, field: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const v = parsed.value.object.get(field) orelse return false;
    return switch (v) {
        .bool => |b| b,
        else => false,
    };
}

fn parseIntField(gpa: std.mem.Allocator, arguments_json: []const u8, field: []const u8, default: i64) i64 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return default;
    defer parsed.deinit();
    if (parsed.value != .object) return default;
    const v = parsed.value.object.get(field) orelse return default;
    return switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => default,
    };
}

fn executeRead(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parsePathField(ctx.gpa, arguments_json) orelse
        return try errMsg(ctx.gpa, "read: missing path", .{});
    defer ctx.gpa.free(path_owned);

    const offset_raw = parseIntField(ctx.gpa, arguments_json, "offset", 0); // 0 = unset; 1-indexed when set
    const limit_raw = parseIntField(ctx.gpa, arguments_json, "limit", 0); // 0 = no limit

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(32 * 1024 * 1024)) catch |err| {
        return try errMsg(ctx.gpa, "read failed: {s}", .{@errorName(err)});
    };

    // Images ignore line slicing and become structured tool content. Safe
    // provider-native payloads remain byte-for-byte; oversized, rotated and
    // BMP inputs are normalized according to `images.autoResize`.
    if (image_process.inspect(data)) |inspection| {
        defer ctx.gpa.free(data);
        var normalized = try image_process.processBytes(ctx.gpa, ctx.io, data, .{
            .auto_resize = ctx.auto_resize_images,
            .environ = ctx.environ,
        });
        if (normalized) |*image| {
            errdefer image.deinit(ctx.gpa);
            const hints = try image.formatHints(ctx.gpa);
            defer ctx.gpa.free(hints);
            const content = if (hints.len > 0)
                try std.fmt.allocPrint(ctx.gpa, "Read image file [{s}]\n{s}", .{ image.mime_type, hints })
            else
                try std.fmt.allocPrint(ctx.gpa, "Read image file [{s}]", .{image.mime_type});
            if (image.converted_from) |value| ctx.gpa.free(value);
            return .{
                .content = content,
                .is_error = false,
                .image_b64 = image.data_b64,
                .image_mime = image.mime_type,
            };
        }

        const content = if (std.mem.eql(u8, inspection.mime_type, "image/bmp"))
            try std.fmt.allocPrint(ctx.gpa, "Read image file [{s}]\n[Image omitted: could not be converted to a supported inline image format.]", .{inspection.mime_type})
        else
            try std.fmt.allocPrint(ctx.gpa, "Read image file [{s}]\n[Image omitted: could not be resized below the inline image size limit.]", .{inspection.mime_type});
        return .{ .content = content, .is_error = false };
    }

    // Apply line offset/limit when requested (upstream pi read tool)
    if (offset_raw > 0 or limit_raw > 0) {
        defer ctx.gpa.free(data);
        const start_line: usize = if (offset_raw > 0) @intCast(offset_raw) else 1;
        const max_lines: ?usize = if (limit_raw > 0) @intCast(limit_raw) else null;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(ctx.gpa);
        var line_no: usize = 1;
        var kept: usize = 0;
        var it = std.mem.splitScalar(u8, data, '\n');
        while (it.next()) |line| {
            defer line_no += 1;
            if (line_no < start_line) continue;
            if (max_lines) |ml| {
                if (kept >= ml) break;
            }
            if (out.items.len > 0) try out.append(ctx.gpa, '\n');
            try out.appendSlice(ctx.gpa, line);
            kept += 1;
        }
        return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
    }

    return try maybeTruncate(ctx.gpa, data, false);
}

fn executeWrite(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parsePathField(ctx.gpa, arguments_json) orelse
        return try errMsg(ctx.gpa, "write: missing path", .{});
    defer ctx.gpa.free(path_owned);
    const content_owned = try parseStringField(ctx.gpa, arguments_json, "content") orelse
        return try errMsg(ctx.gpa, "write: missing content", .{});
    defer ctx.gpa.free(content_owned);

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    if (std.fs.path.dirname(full)) |parent| {
        if (parent.len > 0) {
            std.Io.Dir.cwd().createDirPath(ctx.io, parent) catch |err| {
                return try errMsg(ctx.gpa, "write mkdir failed: {s}", .{@errorName(err)});
            };
        }
    }

    std.Io.Dir.cwd().writeFile(ctx.io, .{
        .sub_path = full,
        .data = content_owned,
    }) catch |err| {
        return try errMsg(ctx.gpa, "write failed: {s}", .{@errorName(err)});
    };

    return try okMsg(ctx.gpa, "Wrote {d} bytes to {s}", .{ content_owned.len, path_owned });
}

const EditPair = struct { old: []const u8, new: []const u8 };

fn collectEditPairs(gpa: std.mem.Allocator, arguments_json: []const u8) ![]EditPair {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidArgs;

    var list: std.ArrayList(EditPair) = .empty;
    errdefer {
        for (list.items) |p| {
            gpa.free(p.old);
            gpa.free(p.new);
        }
        list.deinit(gpa);
    }

    // Upstream: edits: [{oldText, newText}, ...]
    if (parsed.value.object.get("edits")) |ev| {
        if (ev == .array) {
            for (ev.array.items) |item| {
                if (item != .object) continue;
                const ot = item.object.get("oldText") orelse item.object.get("old_string") orelse continue;
                const nt = item.object.get("newText") orelse item.object.get("new_string") orelse continue;
                if (ot != .string or nt != .string) continue;
                try list.append(gpa, .{
                    .old = try gpa.dupe(u8, ot.string),
                    .new = try gpa.dupe(u8, nt.string),
                });
            }
        }
    }

    // Single-edit aliases: oldText/newText or old_string/new_string
    if (list.items.len == 0) {
        const old = parsed.value.object.get("oldText") orelse parsed.value.object.get("old_string");
        const newv = parsed.value.object.get("newText") orelse parsed.value.object.get("new_string");
        if (old != null and newv != null and old.? == .string and newv.? == .string) {
            try list.append(gpa, .{
                .old = try gpa.dupe(u8, old.?.string),
                .new = try gpa.dupe(u8, newv.?.string),
            });
        }
    }

    if (list.items.len == 0) return error.MissingEdits;
    return try list.toOwnedSlice(gpa);
}

fn freeEditPairs(gpa: std.mem.Allocator, pairs: []EditPair) void {
    for (pairs) |p| {
        gpa.free(p.old);
        gpa.free(p.new);
    }
    gpa.free(pairs);
}

fn executeEdit(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parsePathField(ctx.gpa, arguments_json) orelse
        return try errMsg(ctx.gpa, "edit: missing path", .{});
    defer ctx.gpa.free(path_owned);

    const pairs = collectEditPairs(ctx.gpa, arguments_json) catch |err| switch (err) {
        error.MissingEdits => return try errMsg(ctx.gpa, "edit: missing edits[] or oldText/newText (or old_string/new_string)", .{}),
        else => return try errMsg(ctx.gpa, "edit: invalid arguments", .{}),
    };
    defer freeEditPairs(ctx.gpa, pairs);

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    const original = std.Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(8 * 1024 * 1024)) catch |err| {
        return try errMsg(ctx.gpa, "edit read failed: {s}", .{@errorName(err)});
    };
    defer ctx.gpa.free(original);

    // Match ALL edits against the original file (upstream non-incremental semantics),
    // then apply from highest index to lowest so positions stay valid.
    const Match = struct { start: usize, end: usize, new: []const u8, old: []const u8 };
    var matches: std.ArrayList(Match) = .empty;
    defer matches.deinit(ctx.gpa);

    for (pairs) |pair| {
        const found = findUniqueMatch(original, pair.old) orelse {
            // Fuzzy: collapse whitespace runs and retry
            const fuzzy = try findFuzzyUniqueMatch(ctx.gpa, original, pair.old);
            if (fuzzy) |f| {
                try matches.append(ctx.gpa, .{ .start = f.start, .end = f.end, .new = pair.new, .old = pair.old });
                continue;
            }
            return try errMsg(ctx.gpa, "edit: oldText not found: {s}", .{truncatePreview(pair.old, 60)});
        };
        try matches.append(ctx.gpa, .{ .start = found.start, .end = found.end, .new = pair.new, .old = pair.old });
    }

    // Overlap check
    for (matches.items, 0..) |a, i| {
        for (matches.items[i + 1 ..]) |b| {
            if (!(a.end <= b.start or b.end <= a.start)) {
                return try errMsg(ctx.gpa, "edit: overlapping edits are not allowed", .{});
            }
        }
    }

    // Sort by start descending
    std.mem.sort(Match, matches.items, {}, struct {
        fn less(_: void, a: Match, b: Match) bool {
            return a.start > b.start;
        }
    }.less);

    var working = try ctx.gpa.dupe(u8, original);
    defer ctx.gpa.free(working);
    var diff_summary: std.ArrayList(u8) = .empty;
    defer diff_summary.deinit(ctx.gpa);

    for (matches.items) |m| {
        var next: std.ArrayList(u8) = .empty;
        defer next.deinit(ctx.gpa);
        try next.appendSlice(ctx.gpa, working[0..m.start]);
        try next.appendSlice(ctx.gpa, m.new);
        try next.appendSlice(ctx.gpa, working[m.end..]);
        ctx.gpa.free(working);
        working = try next.toOwnedSlice(ctx.gpa);
        try diff_summary.appendSlice(ctx.gpa, "@@ edit\n- ");
        try diff_summary.appendSlice(ctx.gpa, truncatePreview(m.old, 80));
        try diff_summary.appendSlice(ctx.gpa, "\n+ ");
        try diff_summary.appendSlice(ctx.gpa, truncatePreview(m.new, 80));
        try diff_summary.append(ctx.gpa, '\n');
    }

    std.Io.Dir.cwd().writeFile(ctx.io, .{
        .sub_path = full,
        .data = working,
    }) catch |err| {
        return try errMsg(ctx.gpa, "edit write failed: {s}", .{@errorName(err)});
    };

    return try okMsg(ctx.gpa, "Edited {s} ({d} replacement(s))\n{s}", .{ path_owned, matches.items.len, diff_summary.items });
}

const Span = struct { start: usize, end: usize };

fn findUniqueMatch(hay: []const u8, needle: []const u8) ?Span {
    if (needle.len == 0) return null;
    const idx = std.mem.indexOf(u8, hay, needle) orelse return null;
    if (std.mem.indexOfPos(u8, hay, idx + needle.len, needle) != null) return null;
    return .{ .start = idx, .end = idx + needle.len };
}

/// Collapse runs of whitespace to single space for fuzzy unique match (models often drift on indent).
fn collapseWs(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    var in_ws = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            if (!in_ws) {
                try out.append(gpa, ' ');
                in_ws = true;
            }
        } else {
            try out.append(gpa, c);
            in_ws = false;
        }
    }
    return try out.toOwnedSlice(gpa);
}

fn findFuzzyUniqueMatch(gpa: std.mem.Allocator, hay: []const u8, needle: []const u8) !?Span {
    const n_col = try collapseWs(gpa, needle);
    defer gpa.free(n_col);
    if (n_col.len == 0) return null;

    // Scan original by expanding windows; map collapsed needle back to original span.
    // Strategy: find all substrings of hay whose collapse equals n_col — require exactly one.
    var first: ?Span = null;
    var start: usize = 0;
    while (start < hay.len) : (start += 1) {
        // Expand end until collapsed length >= needle collapsed length
        var end = start;
        var col: std.ArrayList(u8) = .empty;
        defer col.deinit(gpa);
        var in_ws = false;
        while (end < hay.len and col.items.len < n_col.len) {
            const c = hay[end];
            end += 1;
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                if (!in_ws and col.items.len > 0) {
                    try col.append(gpa, ' ');
                    in_ws = true;
                }
            } else {
                try col.append(gpa, c);
                in_ws = false;
            }
        }
        // Trim trailing space from col for compare
        var cslice = col.items;
        while (cslice.len > 0 and cslice[cslice.len - 1] == ' ') cslice = cslice[0 .. cslice.len - 1];
        var nslice = n_col;
        while (nslice.len > 0 and nslice[nslice.len - 1] == ' ') nslice = nslice[0 .. nslice.len - 1];
        // Also trim leading
        while (cslice.len > 0 and cslice[0] == ' ') cslice = cslice[1..];
        while (nslice.len > 0 and nslice[0] == ' ') nslice = nslice[1..];
        if (std.mem.eql(u8, cslice, nslice)) {
            if (first != null) return null; // not unique
            first = .{ .start = start, .end = end };
        }
    }
    return first;
}

fn truncatePreview(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

fn executeBash(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const command = try parseStringField(ctx.gpa, arguments_json, "command") orelse
        return try errMsg(ctx.gpa, "bash: missing command", .{});
    defer ctx.gpa.free(command);

    if (ctx.abort_flag) |f| {
        if (@atomicLoad(bool, f, .acquire)) return try errMsg(ctx.gpa, "bash: aborted before start", .{});
    }

    const timeout_sec: i64 = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "timeout", 120)));
    const argv: []const []const u8 = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/C", command }
    else
        &[_][]const u8{ "sh", "-c", command };

    // Mid-process kill: spawn Child, poll abort_flag, kill on abort or timeout.
    return executeProcessTool(ctx, "bash", argv, timeout_sec);
}

fn executePowerShell(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const command = try parseStringField(ctx.gpa, arguments_json, "command") orelse
        return try errMsg(ctx.gpa, "powershell: missing command", .{});
    defer ctx.gpa.free(command);
    if (builtin.os.tag != .windows) return try errMsg(ctx.gpa, "powershell: only available on Windows", .{});
    if (ctx.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire))
        return try errMsg(ctx.gpa, "powershell: aborted before start", .{});
    const timeout_sec: i64 = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "timeout", 120)));
    const utf8_command = try std.fmt.allocPrint(ctx.gpa, "try {{ [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 }} catch {{}}\n{s}", .{command});
    defer ctx.gpa.free(utf8_command);
    const argv = powershell_command_prefix ++ [_][]const u8{utf8_command};
    return executeProcessTool(ctx, "powershell", &argv, timeout_sec);
}

const powershell_command_prefix = [_][]const u8{
    "powershell.exe",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
};

fn buildBashEnvironment(ctx: ToolContext) !?std.process.Environ.Map {
    const parent = ctx.environ orelse return null;
    var child = try parent.clone(ctx.gpa);
    errdefer child.deinit();

    // AI_AGENT is the cross-agent convention; PI_* is intentionally scoped to
    // subprocesses rather than mutating the parent process environment.
    try child.put("AI_AGENT", "pi");
    if (ctx.session_id) |value| try child.put("PI_SESSION_ID", value);
    if (ctx.session_file) |value| try child.put("PI_SESSION_FILE", value);
    if (ctx.provider_name) |value| try child.put("PI_PROVIDER", value);
    if (ctx.model_id) |value| try child.put("PI_MODEL", value);
    if (ctx.reasoning_level) |value| try child.put("PI_REASONING_LEVEL", value);
    return child;
}

fn executeProcessTool(ctx: ToolContext, tool_label: []const u8, argv: []const []const u8, timeout_sec: i64) !ToolResult {
    var child_environment = try buildBashEnvironment(ctx);
    defer if (child_environment) |*environment| environment.deinit();
    const child_environment_ptr: ?*const std.process.Environ.Map = if (child_environment) |*environment| environment else null;

    // When neither cancellation nor live progress is needed, use the compact
    // process.run path. Progress requires the pipe-draining child path so
    // updates can be forwarded while the command is still running.
    if (ctx.abort_flag == null and ctx.progress_fn == null) {
        const run_result = std.process.run(ctx.gpa, ctx.io, .{
            .argv = argv,
            .cwd = .{ .path = ctx.cwd },
            .environ_map = child_environment_ptr,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(timeout_sec), .clock = .real } },
        }) catch |err| {
            if (err == error.Timeout) return try errMsg(ctx.gpa, "{s}: timed out after {d}s", .{ tool_label, timeout_sec });
            return try errMsg(ctx.gpa, "{s} spawn failed: {s}", .{ tool_label, @errorName(err) });
        };
        defer ctx.gpa.free(run_result.stdout);
        defer ctx.gpa.free(run_result.stderr);
        const code: i32 = switch (run_result.term) {
            .exited => |c| @intCast(c),
            .signal => -1,
            .stopped => -1,
            .unknown => |u| -@as(i32, @intCast(u)),
        };
        if (ctx.progress_fn) |progress| {
            if (run_result.stdout.len > 0) progress(ctx.progress_ctx, run_result.stdout);
            if (run_result.stderr.len > 0) progress(ctx.progress_ctx, run_result.stderr);
        }
        const body = try std.fmt.allocPrint(ctx.gpa, "exit={d}\nstdout:\n{s}\nstderr:\n{s}", .{
            code, run_result.stdout, run_result.stderr,
        });
        return try maybeTruncate(ctx.gpa, body, code != 0);
    }

    // Abort-capable path: Child + OS force-kill (not Child.kill — that races with wait).
    // Waiter owns wait/cleanup; main only signals the process.
    var child = std.process.spawn(ctx.io, .{
        .argv = argv,
        .cwd = .{ .path = ctx.cwd },
        .environ_map = child_environment_ptr,
        .stdout = .pipe,
        .stderr = .pipe,
        .stdin = .ignore,
        .pgid = if (builtin.os.tag == .windows) null else 0,
    }) catch |err| {
        return try errMsg(ctx.gpa, "{s} spawn failed: {s}", .{ tool_label, @errorName(err) });
    };

    const WaitState = struct {
        term: ?std.process.Child.Term = null,
        done: std.atomic.Value(bool) = .init(false),
        child: *std.process.Child,
        io: Io,
        gpa: std.mem.Allocator,
        stdout: []u8 = &.{},
        stderr: []u8 = &.{},
    };
    var state = WaitState{ .child = &child, .io = ctx.io, .gpa = ctx.gpa };

    // Drain stdout/stderr concurrently so full pipes don't deadlock wait.
    const PipeState = struct {
        file: ?std.Io.File,
        io: Io,
        gpa: std.mem.Allocator,
        out: *[]u8,
        progress_fn: ?ToolProgressFn,
        progress_ctx: ?*anyopaque,
    };
    const drainPipe = struct {
        fn run(ps: *PipeState) void {
            const f = ps.file orelse {
                ps.out.* = ps.gpa.alloc(u8, 0) catch &.{};
                return;
            };
            var aw: std.Io.Writer.Allocating = .init(ps.gpa);
            defer aw.deinit();
            var buf: [4096]u8 = undefined;
            while (true) {
                var slice = [_][]u8{buf[0..]};
                const n = f.readStreaming(ps.io, &slice) catch break;
                if (n == 0) break;
                if (ps.progress_fn) |progress| progress(ps.progress_ctx, buf[0..n]);
                aw.writer.writeAll(buf[0..n]) catch break;
                if (aw.written().len > 1024 * 1024) break;
            }
            ps.out.* = aw.toOwnedSlice() catch &.{};
        }
    }.run;

    var stdout_owned: []u8 = &.{};
    var stderr_owned: []u8 = &.{};
    var out_ps = PipeState{ .file = child.stdout, .io = ctx.io, .gpa = ctx.gpa, .out = &stdout_owned, .progress_fn = ctx.progress_fn, .progress_ctx = ctx.progress_ctx };
    var err_ps = PipeState{ .file = child.stderr, .io = ctx.io, .gpa = ctx.gpa, .out = &stderr_owned, .progress_fn = ctx.progress_fn, .progress_ctx = ctx.progress_ctx };
    const out_thr = try std.Thread.spawn(.{}, drainPipe, .{&out_ps});
    const err_thr = try std.Thread.spawn(.{}, drainPipe, .{&err_ps});

    const waiter = try std.Thread.spawn(.{}, struct {
        fn run(s: *WaitState) void {
            defer s.done.store(true, .release);
            s.term = s.child.wait(s.io) catch null;
        }
    }.run, .{&state});

    const deadline_ms: i64 = timeout_sec * 1000;
    var elapsed_ms: i64 = 0;
    var killed_for_abort = false;
    var killed_for_timeout = false;
    while (!state.done.load(.acquire)) {
        if (ctx.abort_flag) |f| {
            if (@atomicLoad(bool, f, .acquire)) {
                forceKillProcess(&child);
                killed_for_abort = true;
                break;
            }
        }
        if (elapsed_ms >= deadline_ms) {
            forceKillProcess(&child);
            killed_for_timeout = true;
            break;
        }
        const st: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(50), .clock = .real } };
        st.sleep(ctx.io) catch {};
        elapsed_ms += 50;
    }
    waiter.join();
    out_thr.join();
    err_thr.join();
    state.stdout = stdout_owned;
    state.stderr = stderr_owned;
    defer if (state.stdout.len > 0) ctx.gpa.free(state.stdout);
    defer if (state.stderr.len > 0) ctx.gpa.free(state.stderr);

    if (killed_for_abort) return try errMsg(ctx.gpa, "{s}: aborted (process killed)", .{tool_label});
    if (killed_for_timeout) return try errMsg(ctx.gpa, "{s}: timed out after {d}s (process killed)", .{ tool_label, timeout_sec });

    const code: i32 = if (state.term) |t| switch (t) {
        .exited => |c| @intCast(c),
        .signal => -1,
        .stopped => -1,
        .unknown => |u| -@as(i32, @intCast(u)),
    } else -1;

    const body = try std.fmt.allocPrint(ctx.gpa, "exit={d}\nstdout:\n{s}\nstderr:\n{s}", .{
        code, state.stdout, state.stderr,
    });
    return try maybeTruncate(ctx.gpa, body, code != 0);
}

/// Signal the OS process without Zig Child cleanup (waiter owns wait/cleanup).
fn forceKillProcess(child: *std.process.Child) void {
    const id = child.id orelse return;
    if (builtin.os.tag == .windows) {
        // Do not call Child.kill — it races with the waiter thread's wait().
        _ = std.os.windows.ntdll.NtTerminateProcess(id, @enumFromInt(1));
    } else {
        // Child was spawned into its own process group (pgid=0), so kill the
        // group rather than only the shell. This prevents grandchildren from
        // retaining stdout/stderr pipes after an abort.
        std.posix.kill(-id, std.posix.SIG.KILL) catch {
            std.posix.kill(id, std.posix.SIG.KILL) catch {};
        };
    }
}

/// Try ripgrep for regex search. Returns null if rg is unavailable.
fn tryRipgrep(
    ctx: ToolContext,
    pattern: []const u8,
    search_root: []const u8,
    glob_opt: ?[]const u8,
    ignore_case: bool,
    limit: usize,
    context_lines: usize,
) !?ToolResult {
    const rg_path = tool_manager.ensure(ctx.gpa, ctx.io, ctx.environ, .rg, .{}) catch return null;
    const rg_executable = rg_path orelse return null;
    defer ctx.gpa.free(rg_executable);

    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(ctx.gpa);
    try argv_list.append(ctx.gpa, rg_executable);
    try argv_list.append(ctx.gpa, "-n");
    try argv_list.append(ctx.gpa, "--no-heading");
    try argv_list.append(ctx.gpa, "--color");
    try argv_list.append(ctx.gpa, "never");
    if (ignore_case) try argv_list.append(ctx.gpa, "-i");
    if (context_lines > 0) {
        const cstr = try std.fmt.allocPrint(ctx.gpa, "{d}", .{context_lines});
        defer ctx.gpa.free(cstr);
        try argv_list.append(ctx.gpa, "-C");
        try argv_list.append(ctx.gpa, cstr);
    }
    const max_str = try std.fmt.allocPrint(ctx.gpa, "{d}", .{limit});
    defer ctx.gpa.free(max_str);
    try argv_list.append(ctx.gpa, "-m");
    try argv_list.append(ctx.gpa, max_str);
    if (glob_opt) |g| {
        try argv_list.append(ctx.gpa, "-g");
        try argv_list.append(ctx.gpa, g);
    }
    try argv_list.append(ctx.gpa, "--");
    try argv_list.append(ctx.gpa, pattern);
    try argv_list.append(ctx.gpa, search_root);

    const run_result = std.process.run(ctx.gpa, ctx.io, .{
        .argv = argv_list.items,
        .cwd = .{ .path = ctx.cwd },
        .environ_map = ctx.environ,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
        .timeout = .{ .duration = .{
            .raw = .fromSeconds(60),
            .clock = .real,
        } },
    }) catch return null;
    defer ctx.gpa.free(run_result.stdout);
    defer ctx.gpa.free(run_result.stderr);

    // rg not found / spawn failure already caught; exit 2 usually means error, 1 no matches
    const code: u8 = switch (run_result.term) {
        .exited => |c| @intCast(c),
        else => return null,
    };
    // If rg missing, Windows often returns non-zero with empty and error message
    if (code > 1 and run_result.stdout.len == 0) {
        if (std.mem.indexOf(u8, run_result.stderr, "not recognized") != null or
            std.mem.indexOf(u8, run_result.stderr, "not found") != null)
            return null;
    }
    if (run_result.stdout.len == 0) {
        return try okMsg(ctx.gpa, "No matches for {s}", .{pattern});
    }
    return try maybeTruncate(ctx.gpa, try ctx.gpa.dupe(u8, run_result.stdout), false);
}

/// Simple glob match: supports `*` (segment) and `**` (recursive path).
pub fn matchGlob(pattern: []const u8, path: []const u8) bool {
    // Normalize to forward slashes for matching
    return matchGlobRec(pattern, path);
}

fn matchGlobRec(pattern: []const u8, path: []const u8) bool {
    var pi: usize = 0;
    var si: usize = 0;
    while (pi < pattern.len) {
        if (pi + 1 < pattern.len and pattern[pi] == '*' and pattern[pi + 1] == '*') {
            // ** — match any number of path chars
            pi += 2;
            if (pi < pattern.len and (pattern[pi] == '/' or pattern[pi] == '\\')) pi += 1;
            if (pi >= pattern.len) return true;
            while (si <= path.len) : (si += 1) {
                if (matchGlobRec(pattern[pi..], path[si..])) return true;
            }
            return false;
        } else if (pattern[pi] == '*') {
            pi += 1;
            // match within segment (no /)
            if (pi >= pattern.len) {
                // rest of segment only
                while (si < path.len and path[si] != '/' and path[si] != '\\') si += 1;
                return si >= path.len or path[si] == '/' or path[si] == '\\' or matchGlobRec(pattern[pi..], path[si..]);
            }
            while (si < path.len) {
                if (path[si] == '/' or path[si] == '\\') break;
                if (matchGlobRec(pattern[pi..], path[si..])) return true;
                si += 1;
            }
            return matchGlobRec(pattern[pi..], path[si..]);
        } else if (pattern[pi] == '?') {
            if (si >= path.len) return false;
            if (path[si] == '/' or path[si] == '\\') return false;
            pi += 1;
            si += 1;
        } else {
            if (si >= path.len) return false;
            const pc = if (pattern[pi] == '\\') '/' else pattern[pi];
            const sc = if (path[si] == '\\') '/' else path[si];
            if (pc != sc) return false;
            pi += 1;
            si += 1;
        }
    }
    return si >= path.len;
}

fn executeGrep(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const pattern = try parseStringField(ctx.gpa, arguments_json, "pattern") orelse
        return try errMsg(ctx.gpa, "grep: missing pattern", .{});
    defer ctx.gpa.free(pattern);
    const path_opt = try parseStringField(ctx.gpa, arguments_json, "path");
    defer if (path_opt) |p| ctx.gpa.free(p);
    const glob_opt = try parseStringField(ctx.gpa, arguments_json, "glob");
    defer if (glob_opt) |g| ctx.gpa.free(g);
    const ignore_case = parseBoolField(ctx.gpa, arguments_json, "ignoreCase");
    const literal = parseBoolField(ctx.gpa, arguments_json, "literal");
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 100)));
    const context_lines: usize = @intCast(@max(0, parseIntField(ctx.gpa, arguments_json, "context", 0)));

    const search_root = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(search_root);

    // Prefer ripgrep when available for real regex (unless literal=true)
    if (!literal) {
        if (try tryRipgrep(ctx, pattern, search_root, glob_opt, ignore_case, limit, context_lines)) |rg_result| {
            return rg_result;
        }
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.gpa);
    var matches: usize = 0;

    // If single file
    const is_dir = blk: {
        std.Io.Dir.cwd().access(ctx.io, search_root, .{}) catch {
            return try errMsg(ctx.gpa, "grep: path not found: {s}", .{search_root});
        };
        var d = std.Io.Dir.cwd().openDir(ctx.io, search_root, .{ .iterate = true }) catch {
            break :blk false;
        };
        d.close(ctx.io);
        break :blk true;
    };

    if (!is_dir) {
        try grepFileCtx(ctx, search_root, search_root, pattern, ignore_case, &out, &matches, limit, context_lines);
    } else {
        var dir = std.Io.Dir.cwd().openDir(ctx.io, search_root, .{ .iterate = true }) catch |err| {
            return try errMsg(ctx.gpa, "grep open failed: {s}", .{@errorName(err)});
        };
        defer dir.close(ctx.io);
        var walker = try dir.walk(ctx.gpa);
        defer walker.deinit();
        while (try walker.next(ctx.io)) |entry| {
            if (matches >= limit) break;
            if (entry.kind != .file) continue;
            if (glob_opt) |g| {
                if (!matchGlob(g, entry.path)) continue;
            }
            // skip common heavy dirs
            if (std.mem.indexOf(u8, entry.path, "node_modules") != null) continue;
            if (std.mem.indexOf(u8, entry.path, ".git") != null) continue;
            if (std.mem.indexOf(u8, entry.path, "zig-cache") != null) continue;

            const full = try std.fs.path.join(ctx.gpa, &.{ search_root, entry.path });
            defer ctx.gpa.free(full);
            try grepFileCtx(ctx, full, entry.path, pattern, ignore_case, &out, &matches, limit, context_lines);
        }
    }

    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "No matches for {s}", .{pattern});
    }
    return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
}

fn grepFile(
    ctx: ToolContext,
    full_path: []const u8,
    display_path: []const u8,
    pattern: []const u8,
    ignore_case: bool,
    out: *std.ArrayList(u8),
    matches: *usize,
    limit: usize,
) !void {
    // context_lines not threaded here; fallback path is match lines only (rg handles -C).
    try grepFileCtx(ctx, full_path, display_path, pattern, ignore_case, out, matches, limit, 0);
}

fn grepFileCtx(
    ctx: ToolContext,
    full_path: []const u8,
    display_path: []const u8,
    pattern: []const u8,
    ignore_case: bool,
    out: *std.ArrayList(u8),
    matches: *usize,
    limit: usize,
    context_lines: usize,
) !void {
    const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, full_path, ctx.gpa, .limited(2 * 1024 * 1024)) catch return;
    defer ctx.gpa.free(data);

    // Materialize lines for context windows
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(ctx.gpa);
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        try lines.append(ctx.gpa, line);
    }

    var line_no: usize = 1;
    while (line_no <= lines.items.len) : (line_no += 1) {
        if (matches.* >= limit) return;
        const line = lines.items[line_no - 1];
        const hit = if (ignore_case)
            containsIgnoreCase(line, pattern)
        else
            std.mem.indexOf(u8, line, pattern) != null;
        if (hit) {
            if (context_lines > 0) {
                const start = if (line_no > context_lines) line_no - context_lines else 1;
                const end = @min(lines.items.len, line_no + context_lines);
                var ln = start;
                while (ln <= end) : (ln += 1) {
                    const mark: u8 = if (ln == line_no) ':' else '-';
                    const line_out = try std.fmt.allocPrint(ctx.gpa, "{s}{c}{d}{c}{s}\n", .{ display_path, mark, ln, mark, lines.items[ln - 1] });
                    defer ctx.gpa.free(line_out);
                    try out.appendSlice(ctx.gpa, line_out);
                }
            } else {
                const line_out = try std.fmt.allocPrint(ctx.gpa, "{s}:{d}:{s}\n", .{ display_path, line_no, line });
                defer ctx.gpa.free(line_out);
                try out.appendSlice(ctx.gpa, line_out);
            }
            matches.* += 1;
        }
    }
}

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (hay.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn tryFdFind(
    ctx: ToolContext,
    pattern: []const u8,
    search_root: []const u8,
    limit: usize,
) !?ToolResult {
    const fd_path = tool_manager.ensure(ctx.gpa, ctx.io, ctx.environ, .fd, .{
        // Unit tests and embedders without an environment retain the native
        // walker and never perform an implicit network operation.
        .offline = ctx.environ == null,
    }) catch return null;
    const fd_executable = fd_path orelse return null;
    defer ctx.gpa.free(fd_executable);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(ctx.gpa);
    try argv.append(ctx.gpa, fd_executable);
    try argv.append(ctx.gpa, "--glob");
    try argv.append(ctx.gpa, "--color=never");
    try argv.append(ctx.gpa, "--hidden");
    try argv.append(ctx.gpa, "--exclude");
    try argv.append(ctx.gpa, "node_modules");
    try argv.append(ctx.gpa, "--exclude");
    try argv.append(ctx.gpa, ".git");
    try argv.append(ctx.gpa, "--max-results");
    const limit_text = try std.fmt.allocPrint(ctx.gpa, "{d}", .{limit});
    defer ctx.gpa.free(limit_text);
    try argv.append(ctx.gpa, limit_text);

    var effective_pattern: []const u8 = pattern;
    var owned_pattern: ?[]u8 = null;
    defer if (owned_pattern) |value| ctx.gpa.free(value);
    if (std.mem.indexOfAny(u8, pattern, "/\\") != null) {
        try argv.append(ctx.gpa, "--full-path");
        if (!std.mem.startsWith(u8, pattern, "/") and !std.mem.startsWith(u8, pattern, "**/") and !std.mem.eql(u8, pattern, "**")) {
            owned_pattern = try std.fmt.allocPrint(ctx.gpa, "**/{s}", .{pattern});
            effective_pattern = owned_pattern.?;
        }
    }
    try argv.append(ctx.gpa, "--");
    try argv.append(ctx.gpa, effective_pattern);
    try argv.append(ctx.gpa, ".");

    const result = std.process.run(ctx.gpa, ctx.io, .{
        .argv = argv.items,
        .cwd = .{ .path = search_root },
        .environ_map = ctx.environ,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .real } },
    }) catch return null;
    defer ctx.gpa.free(result.stdout);
    defer ctx.gpa.free(result.stderr);
    const code: u8 = switch (result.term) {
        .exited => |value| @intCast(value),
        else => return null,
    };
    if (code != 0) return null;
    if (result.stdout.len == 0) return try okMsg(ctx.gpa, "No files matching {s}", .{pattern});
    return try maybeTruncate(ctx.gpa, try ctx.gpa.dupe(u8, result.stdout), false);
}

fn executeFind(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const pattern = try parseStringField(ctx.gpa, arguments_json, "pattern") orelse
        return try errMsg(ctx.gpa, "find: missing pattern", .{});
    defer ctx.gpa.free(pattern);
    const path_opt = try parseStringField(ctx.gpa, arguments_json, "path");
    defer if (path_opt) |p| ctx.gpa.free(p);
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 1000)));

    const search_root = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(search_root);

    if (try tryFdFind(ctx, pattern, search_root, limit)) |result| return result;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.gpa);
    var count: usize = 0;

    var dir = std.Io.Dir.cwd().openDir(ctx.io, search_root, .{ .iterate = true }) catch |err| {
        return try errMsg(ctx.gpa, "find open failed: {s}", .{@errorName(err)});
    };
    defer dir.close(ctx.io);
    var walker = try dir.walk(ctx.gpa);
    defer walker.deinit();
    while (try walker.next(ctx.io)) |entry| {
        if (count >= limit) break;
        if (entry.kind != .file and entry.kind != .directory) continue;
        if (std.mem.indexOf(u8, entry.path, "node_modules") != null) continue;
        if (std.mem.indexOf(u8, entry.path, ".git") != null) continue;
        if (matchGlob(pattern, entry.path) or matchGlob(pattern, entry.basename)) {
            try out.appendSlice(ctx.gpa, entry.path);
            try out.append(ctx.gpa, '\n');
            count += 1;
        }
    }

    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "No files matching {s}", .{pattern});
    }
    return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
}

fn executeLs(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_opt = try parseStringField(ctx.gpa, arguments_json, "path");
    defer if (path_opt) |p| ctx.gpa.free(p);
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 500)));

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(full);

    var dir = std.Io.Dir.cwd().openDir(ctx.io, full, .{ .iterate = true }) catch |err| {
        return try errMsg(ctx.gpa, "ls failed: {s}", .{@errorName(err)});
    };
    defer dir.close(ctx.io);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.gpa);
    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |entry| {
        if (count >= limit) {
            try out.appendSlice(ctx.gpa, "... (limit reached)\n");
            break;
        }
        const kind_ch: u8 = switch (entry.kind) {
            .directory => 'd',
            .file => 'f',
            .sym_link => 'l',
            else => '?',
        };
        const line_out = try std.fmt.allocPrint(ctx.gpa, "{c} {s}\n", .{ kind_ch, entry.name });
        defer ctx.gpa.free(line_out);
        try out.appendSlice(ctx.gpa, line_out);
        count += 1;
    }
    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "(empty directory)", .{});
    }
    return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
}

test "read write edit tools on temp fixture" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var w = try execute(ctx, "write",
        \\{"path":"hello.txt","content":"hello world"}
    );
    defer w.deinit(gpa);
    try std.testing.expect(!w.is_error);

    var r = try execute(ctx, "read",
        \\{"path":"hello.txt"}
    );
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expectEqualStrings("hello world", r.content);

    var e = try execute(ctx, "edit",
        \\{"path":"hello.txt","old_string":"world","new_string":"pi"}
    );
    defer e.deinit(gpa);
    try std.testing.expect(!e.is_error);

    var r2 = try execute(ctx, "read",
        \\{"path":"hello.txt"}
    );
    defer r2.deinit(gpa);
    try std.testing.expectEqualStrings("hello pi", r2.content);
}

test "read tool returns structured provider image content" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var png = [_]u8{0} ** 24;
    @memcpy(png[0..8], &[_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a });
    png[11] = 13;
    @memcpy(png[12..16], "IHDR");
    png[19] = 2;
    png[23] = 3;
    try tmp.dir.writeFile(io, .{ .sub_path = "renamed.data", .data = &png });

    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };
    var result = try execute(ctx, "read", "{\"path\":\"renamed.data\",\"offset\":99}");
    defer result.deinit(gpa);
    try std.testing.expect(!result.is_error);
    try std.testing.expect(result.image_b64 != null);
    try std.testing.expectEqualStrings("image/png", result.image_mime.?);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "Read image file [image/png]") != null);
}

test "read tool omits unsupported image when conversion is unavailable" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("PI_IMAGE_CONVERTER", "none");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var bmp = [_]u8{0} ** 58;
    bmp[0] = 'B';
    bmp[1] = 'M';
    bmp[2] = 58;
    bmp[10] = 54;
    bmp[14] = 40;
    bmp[18] = 1;
    bmp[22] = 1;
    bmp[26] = 1;
    bmp[28] = 24;
    bmp[34] = 4;
    try tmp.dir.writeFile(io, .{ .sub_path = "photo.bmp", .data = &bmp });

    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path, .environ = &env };
    var result = try execute(ctx, "read", "{\"path\":\"photo.bmp\"}");
    defer result.deinit(gpa);
    try std.testing.expect(!result.is_error);
    try std.testing.expect(result.image_b64 == null);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "Image omitted") != null);
}

test "bash tool echoes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var b = try execute(ctx, "bash",
        \\{"command":"echo pi-bash-ok"}
    );
    defer b.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, b.content, "pi-bash-ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, b.content, "exit=0") != null);
}

test "grep find ls tools" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    // setup files
    {
        var w1 = try execute(ctx, "write",
            \\{"path":"a.txt","content":"alpha unique-token beta"}
        );
        defer w1.deinit(gpa);
        var w2 = try execute(ctx, "write",
            \\{"path":"sub/b.md","content":"no match here"}
        );
        defer w2.deinit(gpa);
    }

    var g = try execute(ctx, "grep",
        \\{"pattern":"unique-token"}
    );
    defer g.deinit(gpa);
    try std.testing.expect(!g.is_error);
    try std.testing.expect(std.mem.indexOf(u8, g.content, "unique-token") != null);

    var f = try execute(ctx, "find",
        \\{"pattern":"*.txt"}
    );
    defer f.deinit(gpa);
    try std.testing.expect(!f.is_error);
    try std.testing.expect(std.mem.indexOf(u8, f.content, "a.txt") != null);

    var l = try execute(ctx, "ls",
        \\{"path":"."}
    );
    defer l.deinit(gpa);
    try std.testing.expect(!l.is_error);
    try std.testing.expect(std.mem.indexOf(u8, l.content, "a.txt") != null);
}

test "tool filter allowlist" {
    const gpa = std.testing.allocator;
    const filter = ToolFilter{ .allow = &[_][]const u8{ "read", "write" } };
    try std.testing.expect(filter.isEnabled("read"));
    try std.testing.expect(!filter.isEnabled("bash"));
    const json = try toolSchemasJson(gpa, filter);
    defer gpa.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bash\"") == null);
}

test "experimental default tools prefer strict JSON schema without affecting optional tools" {
    const gpa = std.testing.allocator;
    const json = try toolSchemasJsonWithOptions(gpa, .{ .allow = &.{ "read", "grep" } }, .{ .experimental_strict = true });
    defer gpa.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    const read = parsed.value.array.items[0].object;
    const grep = parsed.value.array.items[1].object;
    try std.testing.expect(read.get("constrainedSampling") != null);
    try std.testing.expect(grep.get("constrainedSampling") == null);
    try std.testing.expectEqualStrings("prefer", read.get("constrainedSampling").?.object.get("strict").?.string);
}

test "default built-in selection keeps custom tools and leaves PowerShell opt-in" {
    const defaults = ToolFilter{ .builtin_allow = &.{ "read", "bash" } };
    try std.testing.expect(defaults.isEnabled("read"));
    try std.testing.expect(!defaults.isEnabled("write"));
    try std.testing.expect(!defaults.isEnabled("powershell"));
    try std.testing.expect(defaults.isEnabled("extension_tool"));

    const explicit = ToolFilter{ .allow = &.{"read"} };
    try std.testing.expect(explicit.isEnabled("read"));
    try std.testing.expect(!explicit.isEnabled("extension_tool"));
    const powershell = ToolFilter{ .allow = &.{"powershell"} };
    try std.testing.expect(powershell.isEnabled("powershell"));
}

test "PowerShell tool uses process-local bypass and UTF-8 output on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &path_buf);
    const ctx = ToolContext{ .gpa = std.testing.allocator, .io = std.testing.io, .cwd = path_buf[0..n] };
    try std.testing.expectEqualSlices([]const u8, &.{ "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command" }, &powershell_command_prefix);
    var result = try execute(ctx, "powershell", "{\"command\":\"Write-Output 'héllo €'\"}");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "héllo €") != null);
}

test "matchGlob basics" {
    try std.testing.expect(matchGlob("*.txt", "a.txt"));
    try std.testing.expect(!matchGlob("*.txt", "a.md"));
    try std.testing.expect(matchGlob("**/*.md", "sub/b.md"));
    try std.testing.expect(matchGlob("sub/*", "sub/b.md"));
}

test "edit multi-edit matches all on original not sequential" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    // Both needles exist in original; sequential apply would break the second if order wrong
    var w = try execute(ctx, "write",
        \\{"path":"m.txt","content":"foo bar foo"}
    );
    defer w.deinit(gpa);

    // Two non-overlapping unique replacements on original content
    var e = try execute(ctx, "edit",
        \\{"path":"m.txt","edits":[{"oldText":"foo bar","newText":"X"},{"oldText":" foo","newText":" Y"}]}
    );
    defer e.deinit(gpa);
    try std.testing.expect(!e.is_error);

    var r = try execute(ctx, "read",
        \\{"path":"m.txt"}
    );
    defer r.deinit(gpa);
    try std.testing.expectEqualStrings("X Y", r.content);
}

test "edit accepts oldText/newText and multi-edit edits array" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var w = try execute(ctx, "write",
        \\{"path":"e.txt","content":"alpha beta gamma"}
    );
    defer w.deinit(gpa);

    var e1 = try execute(ctx, "edit",
        \\{"path":"e.txt","oldText":"beta","newText":"BETA"}
    );
    defer e1.deinit(gpa);
    try std.testing.expect(!e1.is_error);
    try std.testing.expect(std.mem.indexOf(u8, e1.content, "replacement") != null);

    var r1 = try execute(ctx, "read",
        \\{"path":"e.txt"}
    );
    defer r1.deinit(gpa);
    try std.testing.expectEqualStrings("alpha BETA gamma", r1.content);

    var e2 = try execute(ctx, "edit",
        \\{"path":"e.txt","edits":[{"oldText":"alpha","newText":"A"},{"oldText":"gamma","newText":"G"}]}
    );
    defer e2.deinit(gpa);
    try std.testing.expect(!e2.is_error);

    var r2 = try execute(ctx, "read",
        \\{"path":"e.txt"}
    );
    defer r2.deinit(gpa);
    try std.testing.expectEqualStrings("A BETA G", r2.content);
}

test "read supports offset and limit lines" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var w = try execute(ctx, "write",
        \\{"path":"lines.txt","content":"L1\nL2\nL3\nL4\nL5"}
    );
    defer w.deinit(gpa);

    var r = try execute(ctx, "read",
        \\{"path":"lines.txt","offset":2,"limit":2}
    );
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expectEqualStrings("L2\nL3", r.content);
}

test "read tool truncates oversized file output" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    // Build a file exceeding the default 2000-line limit via write tool path.
    var big: std.ArrayList(u8) = .empty;
    defer big.deinit(gpa);
    var i: usize = 0;
    while (i < 2500) : (i += 1) {
        try big.appendSlice(gpa, "line-content-for-truncation-test\n");
    }
    const path = try std.fs.path.join(gpa, &.{ tmp_path, "big.txt" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = big.items });

    var r = try execute(ctx, "read",
        \\{"path":"big.txt"}
    );
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expect(std.mem.indexOf(u8, r.content, "truncated") != null);
    // Output should be well under full size
    try std.testing.expect(r.content.len < big.items.len);
}

test "prepareArguments folds legacy edit pair into edits array" {
    const gpa = std.testing.allocator;
    const prepared = (try prepareArguments(gpa, "edit", "{\"path\":\"file.txt\",\"oldText\":\"before\",\"newText\":\"after\"}")).?;
    defer gpa.free(prepared);
    try std.testing.expectEqualStrings("{\"path\":\"file.txt\",\"edits\":[{\"oldText\":\"before\",\"newText\":\"after\"}]}", prepared);
}

test "prepareArguments appends legacy edit and parses stringified edits" {
    const gpa = std.testing.allocator;
    const prepared = (try prepareArguments(gpa, "edit", "{\"path\":\"f\",\"edits\":\"[{\\\"oldText\\\":\\\"a\\\",\\\"newText\\\":\\\"b\\\"}]\",\"oldText\":\"c\",\"newText\":\"d\"}")).?;
    defer gpa.free(prepared);
    try std.testing.expect(std.mem.indexOf(u8, prepared, "{\"oldText\":\"a\",\"newText\":\"b\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, prepared, "{\"oldText\":\"c\",\"newText\":\"d\"}") != null);
}

test "prepareArguments leaves current edit shape unchanged" {
    const prepared = try prepareArguments(std.testing.allocator, "edit", "{\"path\":\"f\",\"edits\":[{\"oldText\":\"a\",\"newText\":\"b\"}]}");
    try std.testing.expect(prepared == null);
}

test "tool schema validator handles required nested types and additional properties" {
    const gpa = std.testing.allocator;
    const schemas =
        \\[{"type":"function","function":{"name":"typed_probe","parameters":{"type":"object","properties":{"value":{"type":"string"},"items":{"type":"array","items":{"type":"integer"}}},"required":["value"],"additionalProperties":false}}}]
    ;
    try std.testing.expect((try validateArgumentsAgainstToolSchemas(gpa, schemas, "typed_probe", "{\"value\":\"ok\",\"items\":[1,2]}")) == null);

    if (try validateArgumentsAgainstToolSchemas(gpa, schemas, "typed_probe", "{\"value\":123}")) |err| {
        defer gpa.free(err);
        try std.testing.expect(std.mem.indexOf(u8, err, "value: expected string") != null);
    } else return error.TestExpectedValidationFailure;

    if (try validateArgumentsAgainstToolSchemas(gpa, schemas, "typed_probe", "{\"value\":\"ok\",\"extra\":true}")) |err| {
        defer gpa.free(err);
        try std.testing.expect(std.mem.indexOf(u8, err, "extra: additional property") != null);
    } else return error.TestExpectedValidationFailure;
}

test "tool schema validator reports missing tool and invalid JSON" {
    const gpa = std.testing.allocator;
    const schemas = "[]";
    if (try validateArgumentsAgainstToolSchemas(gpa, schemas, "missing", "{}")) |err| {
        defer gpa.free(err);
        try std.testing.expectEqualStrings("Tool missing not found", err);
    } else return error.TestExpectedValidationFailure;

    const one = "[{\"type\":\"function\",\"function\":{\"name\":\"one\",\"parameters\":{\"type\":\"object\"}}}]";
    if (try validateArgumentsAgainstToolSchemas(gpa, one, "one", "{")) |err| {
        defer gpa.free(err);
        try std.testing.expect(std.mem.indexOf(u8, err, "invalid JSON") != null);
    } else return error.TestExpectedValidationFailure;
}

test "edit public schema stays strict while legacy arguments prepare before validation" {
    const gpa = std.testing.allocator;
    const schemas = try toolSchemasJson(gpa, .{ .allow = &[_][]const u8{"edit"} });
    defer gpa.free(schemas);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, schemas, .{});
    defer parsed.deinit();
    const function = parsed.value.array.items[0].object.get("function").?;
    const params = function.object.get("parameters").?;
    const props = params.object.get("properties").?.object;
    try std.testing.expect(props.contains("path"));
    try std.testing.expect(props.contains("edits"));
    try std.testing.expect(!props.contains("oldText"));
    try std.testing.expect(!props.contains("newText"));
    try std.testing.expect(!props.contains("old_string"));
    try std.testing.expect(!props.contains("new_string"));

    const required = params.object.get("required").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), required.len);
    try std.testing.expectEqualStrings("path", required[0].string);
    try std.testing.expectEqualStrings("edits", required[1].string);

    const legacy = "{\"path\":\"a.txt\",\"oldText\":\"before\",\"newText\":\"after\"}";
    const prepared = (try prepareArguments(gpa, "edit", legacy)).?;
    defer gpa.free(prepared);
    try std.testing.expect(std.mem.indexOf(u8, prepared, "\"oldText\":\"before\"") != null);
    try std.testing.expect((try validateArgumentsAgainstToolSchemas(gpa, schemas, "edit", prepared)) == null);
}

test "bash child environment exposes live pi metadata without mutating parent" {
    const gpa = std.testing.allocator;
    var parent = std.process.Environ.Map.init(gpa);
    defer parent.deinit();
    try parent.put("PATH", "/bin");
    try parent.put("PI_MODEL", "parent-model");

    const ctx = ToolContext{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .environ = &parent,
        .session_id = "session-42",
        .session_file = "/tmp/session-42.jsonl",
        .provider_name = "anthropic",
        .model_id = "claude-test",
        .reasoning_level = "high",
    };
    var child = (try buildBashEnvironment(ctx)).?;
    defer child.deinit();

    try std.testing.expectEqualStrings("pi", child.get("AI_AGENT").?);
    try std.testing.expectEqualStrings("session-42", child.get("PI_SESSION_ID").?);
    try std.testing.expectEqualStrings("/tmp/session-42.jsonl", child.get("PI_SESSION_FILE").?);
    try std.testing.expectEqualStrings("anthropic", child.get("PI_PROVIDER").?);
    try std.testing.expectEqualStrings("claude-test", child.get("PI_MODEL").?);
    try std.testing.expectEqualStrings("high", child.get("PI_REASONING_LEVEL").?);
    try std.testing.expectEqualStrings("parent-model", parent.get("PI_MODEL").?);
    try std.testing.expect(parent.get("AI_AGENT") == null);
}

test "tool image arrays deep clone and deinitialize" {
    const gpa = std.testing.allocator;
    var input = [_]ToolImage{
        .{ .data_b64 = try gpa.dupe(u8, "AA=="), .mime_type = try gpa.dupe(u8, "image/png") },
        .{ .data_b64 = try gpa.dupe(u8, "AQ=="), .mime_type = try gpa.dupe(u8, "image/jpeg") },
    };
    defer for (&input) |*image| image.deinit(gpa);

    const cloned = try cloneImages(gpa, &input);

    defer deinitImages(gpa, cloned);
    try std.testing.expectEqual(@as(usize, 2), cloned.len);
    try std.testing.expectEqualStrings("AQ==", cloned[1].data_b64);
    try std.testing.expect(cloned[0].data_b64.ptr != input[0].data_b64.ptr);
}
