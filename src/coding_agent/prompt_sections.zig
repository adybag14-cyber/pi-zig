//! Ordered system-message sections, including declaration-aware tool rules.
const std = @import("std");
const skills_mod = @import("skills.zig");
pub const Text = struct { name: []const u8, content: []const u8 };
pub const Guidelines = struct { name: []const u8, rules: []const []const u8 };
pub const ContextFile = struct { path: []const u8, content: []const u8 };
pub const Options = struct {
    cwd: []const u8,
    custom_prompt: ?[]const u8 = null,
    force_system_prompt: ?[]const u8 = null,
    selected_tools: []const []const u8 = &.{ "read", "bash", "edit", "write" },
    hidden_tools: []const []const u8 = &.{},
    tool_snippets: []const Text = &.{},
    tool_guidelines: []const Guidelines = &.{},
    prompt_guidelines: []const []const u8 = &.{},
    append_system_prompt: []const u8 = "",
    sections: []const Text = &.{},
    context_files: []const ContextFile = &.{},
    skills: []const skills_mod.Skill = &.{},
    readme_path: []const u8 = "README.md",
    docs_path: []const u8 = "docs",
    examples_path: []const u8 = "examples",
};
pub const Sections = struct {
    gpa: std.mem.Allocator,
    values: std.StringArrayHashMapUnmanaged(?[]u8) = .empty,
    pub fn deinit(self: *Sections) void {
        for (self.values.keys()) |key| self.gpa.free(key);
        for (self.values.values()) |value| if (value) |text| self.gpa.free(text);
        self.values.deinit(self.gpa);
        self.* = undefined;
    }
    pub fn get(self: *const Sections, name: []const u8) ?[]const u8 {
        return self.values.get(name) orelse null;
    }
    pub fn put(self: *Sections, name: []const u8, value: ?[]const u8) !void {
        const owned_value = if (value) |text| try self.gpa.dupe(u8, text) else null;
        errdefer if (owned_value) |text| self.gpa.free(text);
        if (self.values.getPtr(name)) |previous| {
            if (previous.*) |text| self.gpa.free(text);
            previous.* = owned_value;
            return;
        }
        const owned_name = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(owned_name);
        try self.values.putNoClobber(self.gpa, owned_name, owned_value);
    }
    pub fn render(self: *const Sections) ![]u8 {
        return self.renderAllocating() catch |err| switch (err) {
            error.WriteFailed => error.OutOfMemory,
            else => err,
        };
    }
    fn renderAllocating(self: *const Sections) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        defer out.deinit();
        for (self.values.values()) |value| if (value) |text| {
            if (text.len == 0) continue;
            if (out.written().len != 0) try out.writer.writeAll("\n\n");
            try out.writer.writeAll(text);
        };
        return self.gpa.dupe(u8, out.written());
    }
};
fn contains(values: []const []const u8, wanted: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, wanted)) return true;
    return false;
}
fn textFor(values: []const Text, name: []const u8) ?[]const u8 {
    var result: ?[]const u8 = null;
    for (values) |value| if (std.mem.eql(u8, value.name, name)) {
        result = value.content;
    };
    return result;
}
fn validSection(name: []const u8) bool {
    if (name.len == 0 or name[0] < 'a' or name[0] > 'z' or std.mem.eql(u8, name, "preamble")) return false;
    for (name[1..]) |byte| if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '_' and byte != '-') return false;
    return true;
}
fn whitespace(point: u21) bool {
    return switch (point) {
        0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn trim(text: []const u8) []const u8 {
    var begin: usize = 0;
    var end = text.len;
    while (begin < end) {
        const length = std.unicode.utf8ByteSequenceLength(text[begin]) catch break;
        if (begin + length > end) break;
        const point = std.unicode.utf8Decode(text[begin..][0..length]) catch break;
        if (!whitespace(point)) break;
        begin += length;
    }
    while (end > begin) {
        var start = end - 1;
        while (start > begin and text[start] & 0xc0 == 0x80) start -= 1;
        const point = std.unicode.utf8Decode(text[start..end]) catch break;
        if (!whitespace(point)) break;
        end = start;
    }
    return text[begin..end];
}
fn addRule(gpa: std.mem.Allocator, rules: *std.ArrayList([]const u8), text: []const u8) !void {
    const value = trim(text);
    if (value.len == 0 or contains(rules.items, value)) return;
    try rules.append(gpa, value);
}
fn putWrapped(sections: *Sections, name: []const u8, content: []const u8) !void {
    const value = try std.fmt.allocPrint(sections.gpa, "<{s}>\n{s}\n</{s}>", .{ name, content, name });
    defer sections.gpa.free(value);
    try sections.put(name, value);
}
pub fn build(gpa: std.mem.Allocator, options: Options) !Sections {
    return buildAllocating(gpa, options) catch |err| switch (err) {
        error.WriteFailed => error.OutOfMemory,
        else => err,
    };
}
fn buildAllocating(gpa: std.mem.Allocator, options: Options) !Sections {
    for (options.sections) |section| if (!validSection(section.name)) return error.InvalidSystemPromptSectionName;
    var sections: Sections = .{ .gpa = gpa };
    errdefer sections.deinit();
    var declared: std.ArrayList([]const u8) = .empty;
    defer declared.deinit(gpa);
    for (options.selected_tools) |name| if (!contains(options.hidden_tools, name)) try declared.append(gpa, name);
    if (options.custom_prompt != null and options.custom_prompt.?.len != 0) {
        try sections.put("preamble", options.custom_prompt.?);
    } else {
        try sections.put("preamble", "You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.");
        var tools: std.Io.Writer.Allocating = .init(gpa);
        defer tools.deinit();
        for (declared.items) |name| if (textFor(options.tool_snippets, name)) |snippet| {
            if (snippet.len == 0) continue;
            if (tools.written().len != 0) try tools.writer.writeByte('\n');
            try tools.writer.print("- {s}: {s}", .{ name, snippet });
        };
        if (tools.written().len == 0) try tools.writer.writeAll("(none)");
        try tools.writer.writeAll("\n\nIn addition to the tools above, you may have access to other custom tools depending on the project.");
        try putWrapped(&sections, "tools", tools.written());
        var rules: std.ArrayList([]const u8) = .empty;
        defer rules.deinit(gpa);
        const bash = contains(declared.items, "bash");
        const powershell = contains(declared.items, "powershell");
        if ((bash or powershell) and !contains(declared.items, "grep") and !contains(declared.items, "find") and !contains(declared.items, "ls")) {
            try addRule(gpa, &rules, if (bash and powershell) "Use bash or PowerShell for file operations like listing, searching, and finding files" else if (powershell) "Use PowerShell for file operations like listing, searching, and finding files" else "Use bash for file operations like ls, rg, find");
        }
        for (declared.items) |name| for (options.tool_guidelines) |guidelines| {
            if (!std.mem.eql(u8, name, guidelines.name)) continue;
            for (guidelines.rules) |rule| try addRule(gpa, &rules, rule);
        };
        for (options.prompt_guidelines) |rule| try addRule(gpa, &rules, rule);
        try addRule(gpa, &rules, "Be concise in your responses");
        try addRule(gpa, &rules, "Show file paths clearly when working with files");
        var bullets: std.Io.Writer.Allocating = .init(gpa);
        defer bullets.deinit();
        for (rules.items, 0..) |rule, index| {
            if (index != 0) try bullets.writer.writeByte('\n');
            try bullets.writer.print("- {s}", .{rule});
        }
        try putWrapped(&sections, "rules", bullets.written());
        const docs = try std.fmt.allocPrint(gpa, "Pi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):\n" ++
            "- Main documentation: {s}\n- Additional docs: {s}\n- Examples: {s} (extensions, custom tools, SDK)\n" ++
            "- When reading pi docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory\n" ++
            "- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), pi packages (docs/packages.md), environment variables (docs/environment-variables.md), MCP servers (docs/mcp.md), codemode scripts and non-LLM models such as classifiers and image models (docs/codemode.md)\n" ++
            "- When working on pi topics, read the docs and examples, and follow .md cross-references before implementing\n" ++
            "- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)", .{ options.readme_path, options.docs_path, options.examples_path });
        defer gpa.free(docs);
        try putWrapped(&sections, "docs", docs);
    }
    if (options.append_system_prompt.len != 0) try putWrapped(&sections, "addendum", options.append_system_prompt);
    if (options.context_files.len != 0) {
        var context: std.Io.Writer.Allocating = .init(gpa);
        defer context.deinit();
        try context.writer.writeAll("Project-specific instructions and guidelines:");
        for (options.context_files) |file| try context.writer.print("\n\n<project_instructions path=\"{s}\">\n{s}\n</project_instructions>", .{ file.path, file.content });
        try putWrapped(&sections, "project_context", context.written());
    }
    const reader: ?skills_mod.FileReadTool = if (contains(declared.items, "read")) .read else if (contains(declared.items, "bash")) .bash else if (contains(options.selected_tools, "read") or contains(options.selected_tools, "bash")) .indirect else null;
    if (reader) |available| {
        const summary = try skills_mod.summarizeWithReader(gpa, options.skills, available);
        defer gpa.free(summary);
        const content = trim(summary);
        if (content.len != 0) try putWrapped(&sections, "skills", content);
    }
    const cwd = try gpa.dupe(u8, options.cwd);
    defer gpa.free(cwd);
    std.mem.replaceScalar(u8, cwd, '\\', '/');
    try putWrapped(&sections, "cwd", cwd);
    for (options.sections) |section| if (section.content.len != 0) try putWrapped(&sections, section.name, section.content);
    return sections;
}
pub fn diff(gpa: std.mem.Allocator, previous: *const Sections, current: *const Sections) !?Sections {
    var patch: Sections = .{ .gpa = gpa };
    errdefer patch.deinit();
    for (current.values.keys(), current.values.values()) |name, value| {
        const equal = if (previous.values.getIndex(name)) |index| block: {
            const old = previous.values.values()[index];
            break :block if (old == null or value == null) old == null and value == null else std.mem.eql(u8, old.?, value.?);
        } else false;
        if (!equal) try patch.put(name, value);
    }
    for (previous.values.keys()) |name| if (!current.values.contains(name)) try patch.put(name, null);
    if (patch.values.count() == 0) {
        patch.deinit();
        return null;
    }
    return patch;
}
pub fn buildText(gpa: std.mem.Allocator, options: Options) ![]u8 {
    if (options.force_system_prompt) |forced| return gpa.dupe(u8, forced);
    var sections = try build(gpa, options);
    defer sections.deinit();
    return sections.render();
}
fn strings(gpa: std.mem.Allocator, value: ?std.json.Value) ![]const []const u8 {
    const items = if (value) |present| present.array.items else return &.{};
    const result = try gpa.alloc([]const u8, items.len);
    for (items, result) |item, *slot| slot.* = item.string;
    return result;
}
fn capturedOptions(gpa: std.mem.Allocator, value: std.json.Value) !Options {
    const object = value.object;
    var result: Options = .{ .cwd = object.get("cwd").?.string };
    if (object.get("selectedTools")) |field| result.selected_tools = try strings(gpa, field);
    result.hidden_tools = try strings(gpa, object.get("hiddenTools"));
    result.prompt_guidelines = try strings(gpa, object.get("promptGuidelines"));
    if (object.get("customPrompt")) |field| result.custom_prompt = field.string;
    if (object.get("forceSystemPrompt")) |field| result.force_system_prompt = field.string;
    if (object.get("appendSystemPrompt")) |field| result.append_system_prompt = field.string;
    if (object.get("toolSnippets")) |field| {
        const snippets = try gpa.alloc(Text, field.object.count());
        var iterator = field.object.iterator();
        var index: usize = 0;
        while (iterator.next()) |entry| : (index += 1) snippets[index] = .{ .name = entry.key_ptr.*, .content = entry.value_ptr.string };
        result.tool_snippets = snippets;
    }
    if (object.get("toolGuidelines")) |field| {
        const guidelines = try gpa.alloc(Guidelines, field.object.count());
        var iterator = field.object.iterator();
        var index: usize = 0;
        while (iterator.next()) |entry| : (index += 1) guidelines[index] = .{ .name = entry.key_ptr.*, .rules = try strings(gpa, entry.value_ptr.*) };
        result.tool_guidelines = guidelines;
    }
    if (object.get("sections")) |field| {
        const sections = try gpa.alloc(Text, field.object.count());
        var iterator = field.object.iterator();
        var index: usize = 0;
        while (iterator.next()) |entry| : (index += 1) sections[index] = .{ .name = entry.key_ptr.*, .content = entry.value_ptr.string };
        result.sections = sections;
    }
    if (object.get("contextFiles")) |field| {
        const files = try gpa.alloc(ContextFile, field.array.items.len);
        for (field.array.items, files) |file, *slot| slot.* = .{ .path = file.object.get("path").?.string, .content = file.object.get("content").?.string };
        result.context_files = files;
    }
    if (object.get("skills")) |field| {
        const skills = try gpa.alloc(skills_mod.Skill, field.array.items.len);
        for (field.array.items, skills) |skill, *slot| slot.* = .{ .name = skill.object.get("name").?.string, .description = skill.object.get("description").?.string, .path = skill.object.get("filePath").?.string, .content = "", .disable_model_invocation = skill.object.get("disableModelInvocation").?.bool };
        result.skills = skills;
    }
    return result;
}
fn expectSections(actual: *const Sections, expected: std.json.Value) !void {
    try std.testing.expectEqual(expected.object.count(), actual.values.count());
    var iterator = expected.object.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        try std.testing.expectEqualStrings(entry.key_ptr.*, actual.values.keys()[index]);
        if (entry.value_ptr.* == .null) {
            try std.testing.expect(actual.values.values()[index] == null);
        } else try std.testing.expectEqualStrings(entry.value_ptr.string, actual.values.values()[index].?);
    }
}
fn loadSections(gpa: std.mem.Allocator, value: std.json.Value) !Sections {
    var result: Sections = .{ .gpa = gpa };
    errdefer result.deinit();
    var iterator = value.object.iterator();
    while (iterator.next()) |entry| try result.put(entry.key_ptr.*, if (entry.value_ptr.* == .null) null else entry.value_ptr.string);
    return result;
}
test "structured prompts and section patches match nine actual latest upstream captures" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/prompt_sections_98d2.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("cases").?.array.items) |case| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const options = try capturedOptions(arena.allocator(), case.object.get("input").?);
        var actual = try build(gpa, options);
        defer actual.deinit();
        try expectSections(&actual, case.object.get("sections").?);
        if (options.force_system_prompt) |forced| {
            const text = try buildText(gpa, options);
            defer gpa.free(text);
            try std.testing.expectEqualStrings(forced, text);
        }
        try std.testing.expect((try diff(gpa, &actual, &actual)) == null);
    }
    for (captured.value.object.get("diffs").?.array.items) |case| {
        var previous = try loadSections(gpa, case.object.get("previous").?);
        defer previous.deinit();
        var current = try loadSections(gpa, case.object.get("current").?);
        defer current.deinit();
        var patch = (try diff(gpa, &previous, &current)).?;
        defer patch.deinit();
        try expectSections(&patch, case.object.get("patch").?);
    }
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    var sections = try build(gpa, .{ .cwd = "C:\\owned\\Ω", .hidden_tools = &.{"read"}, .skills = &.{.{ .name = "<&", .description = "original", .path = "owned", .content = "" }}, .sections = &.{.{ .name = "extra", .content = "new" }}, .tool_guidelines = &.{.{ .name = "bash", .rules = &.{ "\xc2\xa0shared\xef\xbb\xbf", "shared" } }} });
    defer sections.deinit();
    const rendered = try sections.render();
    defer gpa.free(rendered);
    var previous: Sections = .{ .gpa = gpa };
    defer previous.deinit();
    try previous.put("removed", "old");
    if (try diff(gpa, &previous, &sections)) |value| {
        var patch = value;
        defer patch.deinit();
    }
}
test "section allocation failures release ownership and forced opaque prompts bypass section validation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
    try std.testing.expectError(error.InvalidSystemPromptSectionName, build(std.testing.allocator, .{ .cwd = ".", .sections = &.{.{ .name = "preamble", .content = "reject" }} }));
    const forced = try buildText(std.testing.allocator, .{ .cwd = ".", .force_system_prompt = "", .sections = &.{.{ .name = "INVALID", .content = "ignored" }} });
    defer std.testing.allocator.free(forced);
    try std.testing.expectEqualStrings("", forced);
}
