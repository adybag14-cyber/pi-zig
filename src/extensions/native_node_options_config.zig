// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native ownership for the selected Node startup options consumed by the real
//! CommonJS/ESM declarations. This is a private component, not a completed CLI
//! parser or internal/options namespace. Unimplemented option admission fails
//! explicitly; Pi argv is never silently parsed as Node execArgv.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const charged = @import("native_env_charged_allocator.zig").ChargedAllocator;
extern fn pi_node_options_environment_allowed() callconv(.c) c_int;

/// This one default changed between the retained Node 24.13 and 24.14 sources:
/// 24.13 initializes strip_types=true; 24.14 uses the actual HAVE_AMARO build.
/// A host must supply its admitted build value before serializing these options.
pub const FeatureDefaults = struct { strip_types: ?bool = null, quic: bool = false };
pub const Embedder = struct {
    should_not_register_esm_loader: bool = false,
    no_global_search_paths: bool = false,
    no_browser_globals: bool = false,
    has_embedder_preload: bool = false,
};
/// Original EnvironmentOptions fields used by the active loader declarations.
/// Strings/lists supplied here are borrowed only for Config.create.
pub const Values = struct {
    conditions: []const []const u8 = &.{},
    allow_native_addons: bool = true,
    global_search_paths: bool = true,
    deprecation: bool = true,
    warnings: bool = true,
    pending_deprecation: bool = false,
    preserve_symlinks: bool = false,
    preserve_symlinks_main: bool = false,
    use_env_proxy: bool = false,
    redirect_warnings: []const u8 = "",
    require_module: bool = true,
    detect_module: bool = true,
    print_required_tla: bool = false,
    strip_types: ?bool = null,
    transform_types: bool = false,
    experimental_addon_modules: bool = false,
    experimental_import_meta_resolve: bool = false,
    experimental_vm_modules: bool = false,
    experimental_quic: bool = false,
    enable_source_maps: bool = false,
    input_type: []const u8 = "",
    trace_require_module: []const u8 = "",
    userland_loaders: []const []const u8 = &.{},
    preload_cjs_modules: []const []const u8 = &.{},
    preload_esm_modules: []const []const u8 = &.{},
    inspect_brk: bool = false,
    inspect_brk_node: bool = false,
    inspect_wait: bool = false,
    inspector_enabled: bool = false,
    inspect_host: []const u8 = "127.0.0.1",
    inspect_port: i32 = 9229,
};
pub const Input = struct {
    values: Values = .{},
    features: FeatureDefaults = .{},
    embedder: Embedder = .{},
    /// Actual Node execution-option tokens, with no program name. The embedding
    /// host supplies these separately from process.argv or Pi command arguments.
    exec_arguments: []const []const u8 = &.{},
};
pub const Kind = enum { boolean, string, string_list, optional_boolean };
pub const Entry = struct {
    name: [:0]const u8,
    field: std.meta.FieldEnum(Values),
    kind: Kind,
};
/// Exact names and field associations from the retained node_options.cc. Aliases
/// are parser inputs and are not extra keys in GetCLIOptionsValues's result.
pub const entries = [_]Entry{
    .{ .name = "--conditions", .field = .conditions, .kind = .string_list },
    .{ .name = "--addons", .field = .allow_native_addons, .kind = .boolean },
    .{ .name = "--global-search-paths", .field = .global_search_paths, .kind = .boolean },
    .{ .name = "--deprecation", .field = .deprecation, .kind = .boolean },
    .{ .name = "--warnings", .field = .warnings, .kind = .boolean },
    .{ .name = "--pending-deprecation", .field = .pending_deprecation, .kind = .boolean },
    .{ .name = "--preserve-symlinks", .field = .preserve_symlinks, .kind = .boolean },
    .{ .name = "--preserve-symlinks-main", .field = .preserve_symlinks_main, .kind = .boolean },
    .{ .name = "--use-env-proxy", .field = .use_env_proxy, .kind = .boolean },
    .{ .name = "--redirect-warnings", .field = .redirect_warnings, .kind = .string },
    .{ .name = "--experimental-require-module", .field = .require_module, .kind = .boolean },
    .{ .name = "--experimental-detect-module", .field = .detect_module, .kind = .boolean },
    .{ .name = "--experimental-print-required-tla", .field = .print_required_tla, .kind = .boolean },
    .{ .name = "--strip-types", .field = .strip_types, .kind = .optional_boolean },
    .{ .name = "--experimental-transform-types", .field = .transform_types, .kind = .boolean },
    .{ .name = "--experimental-addon-modules", .field = .experimental_addon_modules, .kind = .boolean },
    .{ .name = "--experimental-import-meta-resolve", .field = .experimental_import_meta_resolve, .kind = .boolean },
    .{ .name = "--experimental-vm-modules", .field = .experimental_vm_modules, .kind = .boolean },
    .{ .name = "--enable-source-maps", .field = .enable_source_maps, .kind = .boolean },
    .{ .name = "--input-type", .field = .input_type, .kind = .string },
    .{ .name = "--trace-require-module", .field = .trace_require_module, .kind = .string },
    .{ .name = "--experimental-loader", .field = .userland_loaders, .kind = .string_list },
    .{ .name = "--require", .field = .preload_cjs_modules, .kind = .string_list },
    .{ .name = "--import", .field = .preload_esm_modules, .kind = .string_list },
};
fn cloneStrings(allocator: std.mem.Allocator, strings: []const []const u8) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, strings.len);
    for (strings, result) |input, *output| output.* = try allocator.dupe(u8, input);
    return result;
}
fn cloneValues(allocator: std.mem.Allocator, input: Values) !Values {
    var output = input;
    inline for (std.meta.fields(Values)) |field| {
        if (field.type == []const u8) {
            @field(output, field.name) = try allocator.dupe(u8, @field(input, field.name));
        } else if (field.type == []const []const u8) {
            @field(output, field.name) = try cloneStrings(allocator, @field(input, field.name));
        }
    }
    return output;
}
pub const Config = struct {
    engine: *engine_mod.Engine,
    memory: charged,
    original_arena: std.heap.ArenaAllocator,
    environment_arena: ?std.heap.ArenaAllocator = null,
    original: Input,
    values: Values,
    environment_ready: bool = false,
    bootstrapped: bool = false,
    serialized: bool = false,

    pub fn create(engine: *engine_mod.Engine, input: Input) !*Config {
        if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Config)) == 0)
            return error.OutOfMemory;
        errdefer c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Config));
        const self = try engine.gpa.create(Config);
        errdefer engine.gpa.destroy(self);
        self.* = .{ .engine = engine, .memory = charged.init(engine),
            .original_arena = undefined, .original = input, .values = undefined };
        errdefer self.memory.deinit();
        self.original_arena = .init(self.memory.allocator());
        errdefer self.original_arena.deinit();
        const allocator = self.original_arena.allocator();
        self.original.values = try cloneValues(allocator, input.values);
        self.original.exec_arguments = try cloneStrings(allocator, input.exec_arguments);
        self.values = self.original.values;
        if (self.values.strip_types == null) self.values.strip_types = input.features.strip_types;
        return self;
    }
    pub fn destroy(self: *Config) void {
        const engine = self.engine;
        if (self.environment_arena) |*arena| arena.deinit();
        self.original_arena.deinit();
        self.memory.deinit();
        engine.gpa.destroy(self);
        c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Config));
    }
    /// Called from real process installation before any guest environment or
    /// options object is published. A later process facade cannot rewrite the
    /// already selected native startup configuration.
    pub fn captureEnvironment(self: *Config, environment: *const std.process.Environ.Map) !void {
        if (self.environment_ready) return;
        var arena: std.heap.ArenaAllocator = .init(self.memory.allocator());
        errdefer arena.deinit();
        const allocator = arena.allocator();
        var next = try cloneValues(allocator, self.original.values);
        if (next.strip_types == null) next.strip_types = self.original.features.strip_types;
        // Exact HandleEnvOptions assignments. The native environment is read
        // before its mutable JavaScript process.env counterpart exists.
        next.pending_deprecation = envOne(environment, "NODE_PENDING_DEPRECATION");
        next.preserve_symlinks = envOne(environment, "NODE_PRESERVE_SYMLINKS");
        next.preserve_symlinks_main = envOne(environment, "NODE_PRESERVE_SYMLINKS_MAIN");
        next.use_env_proxy = envOne(environment, "NODE_USE_ENV_PROXY");
        if (next.redirect_warnings.len == 0)
            next.redirect_warnings = try allocator.dupe(u8, envRead(environment, "NODE_REDIRECT_WARNINGS") orelse "");
        const raw = envRead(environment, "NODE_OPTIONS") orelse "";
        const tokens = try tokenize(allocator, raw);
        try parse(allocator, &next, tokens, .environment, self.original.features);
        try parse(allocator, &next, self.original.exec_arguments, .command_line, self.original.features);
        try validate(&next);
        self.environment_arena = arena;
        self.values = next;
        self.environment_ready = true;
    }
    pub fn finishBootstrap(self: *Config) void {
        std.debug.assert(self.environment_ready);
        self.bootstrapped = true;
    }
    pub fn checkBootstrap(self: *const Config) !void {
        if (!self.bootstrapped) return error.NodeOptionsBeforeBootstrapping;
    }
    pub fn beforeSerialize(self: *Config) !void {
        try self.checkBootstrap();
        if (self.values.strip_types == null) return error.ActualNodeStripTypesBuildDefaultRequired;
        self.serialized = true;
    }
};
fn envOne(environment: *const std.process.Environ.Map, name: []const u8) bool {
    return std.mem.eql(u8, envRead(environment, name) orelse "", "1");
}
fn envRead(environment: *const std.process.Environ.Map, name: []const u8) ?[]const u8 {
    // The selected original SafeGetenv credential check precedes EACH native
    // lookup. Denied startup environment entries behave as absent; explicit
    // execution-option tokens still keep their original parsing path.
    if (pi_node_options_environment_allowed() == 0) return null;
    return environment.get(name);
}
/// ParseNodeOptionsEnvVar: only ASCII space splits outside double quotes, and
/// backslash only escapes inside them. Empty quotes alone produce no argument.
pub fn tokenize(allocator: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tokens.items) |value| allocator.free(value);
        tokens.deinit(allocator);
    }
    var token: std.ArrayList(u8) = .empty;
    errdefer token.deinit(allocator);
    var quoted = false;
    var starts = true;
    var index: usize = 0;
    while (index < raw.len) : (index += 1) {
        var byte = raw[index];
        if (byte == '\\' and quoted) {
            index += 1;
            if (index == raw.len) return error.InvalidNodeOptionsEscape;
            byte = raw[index];
        } else if (byte == ' ' and !quoted) {
            starts = true;
            continue;
        } else if (byte == '"') {
            quoted = !quoted;
            continue;
        }
        if (starts) {
            if (token.items.len != 0) try appendToken(allocator, &tokens, &token);
            token = .empty;
            starts = false;
        }
        try token.append(allocator, byte);
    }
    if (quoted) return error.UnterminatedNodeOptionsString;
    if (token.items.len != 0) try appendToken(allocator, &tokens, &token);
    return tokens.toOwnedSlice(allocator);
}
fn appendToken(allocator: std.mem.Allocator, tokens: *std.ArrayList([]const u8), token: *std.ArrayList(u8)) !void {
    const value = try token.toOwnedSlice(allocator);
    errdefer allocator.free(value);
    try tokens.append(allocator, value);
}
const Source = enum { environment, command_line };
fn canonical(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "-C")) return "--conditions";
    if (std.mem.eql(u8, name, "-r")) return "--require";
    if (std.mem.eql(u8, name, "--loader")) return "--experimental-loader";
    if (std.mem.eql(u8, name, "--experimental-strip-types")) return "--strip-types";
    return name;
}
fn appendString(allocator: std.mem.Allocator, target: *[]const []const u8, value: []const u8) !void {
    const result = try allocator.alloc([]const u8, target.*.len + 1);
    @memcpy(result[0..target.len], target.*);
    result[target.len] = try allocator.dupe(u8, value);
    target.* = result;
}
fn parse(allocator: std.mem.Allocator, output: *Values, tokens: []const []const u8, source: Source, features: FeatureDefaults) !void {
    var position: usize = 0;
    while (position < tokens.len) : (position += 1) {
        const original = tokens[position];
        if (original.len <= 1 or original[0] != '-') {
            if (source == .environment) return error.NodeOptionsEntryNotAllowed;
            // A host supplied only execution-option tokens. Remaining program
            // arguments require the actual caller's argv split, not guessing.
            return error.ActualNodeExecArgumentBoundaryRequired;
        }
        if (std.mem.eql(u8, original, "--")) {
            if (source == .environment) return error.NodeOptionsEntryNotAllowed;
            if (position + 1 != tokens.len) return error.ActualNodeExecArgumentBoundaryRequired;
            return;
        }
        const equal = if (std.mem.startsWith(u8, original, "--")) std.mem.indexOfScalar(u8, original, '=') else null;
        const name_bytes = try allocator.dupe(u8, original[0..equal orelse original.len]);
        if (name_bytes.len > 2) for (name_bytes[2..]) |*byte| {
            if (byte.* == '_') byte.* = '-';
        }
        var name: []const u8 = name_bytes;
        var negative = false;
        if (std.mem.startsWith(u8, name, "--no-")) {
            name = try std.mem.concat(allocator, u8, &.{ "--", name[5..] });
            negative = true;
        }
        name = canonical(name);
        var selected = false;
        inline for (entries) |entry| {
            if (std.mem.eql(u8, name, entry.name)) {
                selected = true;
                switch (comptime entry.kind) {
                    .boolean => @field(output, @tagName(entry.field)) = !negative,
                    .optional_boolean => @field(output, @tagName(entry.field)) = !negative,
                    .string, .string_list => {
                        if (negative) return error.InvalidNodeOptionNegation;
                        var argument: []const u8 = undefined;
                        if (equal) |offset| {
                            argument = original[offset + 1 ..];
                            if (argument.len == 0) return error.NodeOptionRequiresArgument;
                        } else {
                            position += 1;
                            if (position == tokens.len) return error.NodeOptionRequiresArgument;
                            argument = tokens[position];
                            if (argument.len != 0 and argument[0] == '-') return error.NodeOptionRequiresArgument;
                            if (std.mem.startsWith(u8, argument, "\\-")) argument = argument[1..];
                        }
                        if (comptime entry.kind == .string)
                            @field(output, @tagName(entry.field)) = try allocator.dupe(u8, argument)
                        else
                            try appendString(allocator, &@field(output, @tagName(entry.field)), argument);
                    },
                }
            }
        }
        if (selected) {
            // The retained parser records these real option implications.
            if (std.mem.eql(u8, name, "--experimental-transform-types") and !negative) {
                output.strip_types = true;
                output.enable_source_maps = true;
            }
            continue;
        }
        if (std.mem.eql(u8, name, "--experimental-quic")) {
            if (features.quic) output.experimental_quic = !negative
            else if (negative) return error.InvalidNodeOptionNegation;
            continue;
        }
        // Inspector values require the actual original host/port parser and
        // enabled inspector owner. No dummy host connection or guessed port is
        // admitted by this selected execution-option parser.
        return error.RequiredActualNodeOptionParserEntry;
    }
}
fn validate(output: *const Values) !void {
    const tracing = output.trace_require_module;
    if (tracing.len != 0 and !std.mem.eql(u8, tracing, "all") and !std.mem.eql(u8, tracing, "no-node-modules"))
        return error.InvalidNodeTraceRequireModule;
    const input_type = output.input_type;
    if (input_type.len != 0 and !std.mem.eql(u8, input_type, "module") and
        !std.mem.eql(u8, input_type, "commonjs") and !std.mem.eql(u8, input_type, "module-typescript") and
        !std.mem.eql(u8, input_type, "commonjs-typescript")) return error.InvalidNodeInputType;
}
