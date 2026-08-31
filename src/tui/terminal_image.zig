//! Inline terminal image support compatible with Kitty and iTerm2.
//!
//! The original Pi TUI treats terminal images as first-class rendered lines:
//! capability detection is conservative, Kitty transmissions can be replaced by
//! placement-only commands, and viewport clipping rewrites source rectangles.
//! This module keeps those operations allocation-explicit and testable without a
//! process-global JavaScript environment.
const std = @import("std");

pub const ImageProtocol = enum {
    kitty,
    iterm2,
};

pub const TerminalCapabilities = struct {
    images: ?ImageProtocol = null,
    true_color: bool = false,
    hyperlinks: bool = false,
};

pub const CapabilityOverrides = struct {
    images: ??ImageProtocol = null,
    true_color: ?bool = null,
    hyperlinks: ?bool = null,
};

pub const CellDimensions = struct {
    width_px: u32 = 9,
    height_px: u32 = 18,

    pub fn normalized(self: CellDimensions) CellDimensions {
        return .{
            .width_px = @max(1, self.width_px),
            .height_px = @max(1, self.height_px),
        };
    }
};

pub const ImageDimensions = struct {
    width_px: u32,
    height_px: u32,

    pub fn normalized(self: ImageDimensions) ImageDimensions {
        return .{
            .width_px = @max(1, self.width_px),
            .height_px = @max(1, self.height_px),
        };
    }
};

pub const Environment = struct {
    term_program: ?[]const u8 = null,
    terminal_emulator: ?[]const u8 = null,
    term: ?[]const u8 = null,
    color_term: ?[]const u8 = null,
    tmux: ?[]const u8 = null,
    kitty_window_id: ?[]const u8 = null,
    ghostty_resources_dir: ?[]const u8 = null,
    wezterm_pane: ?[]const u8 = null,
    warp_session_id: ?[]const u8 = null,
    warp_terminal_session_uuid: ?[]const u8 = null,
    iterm_session_id: ?[]const u8 = null,
    wt_session: ?[]const u8 = null,
    pi_hyperlinks: ?[]const u8 = null,
    pi_image_protocol: ?[]const u8 = null,
    pi_true_color: ?[]const u8 = null,
};

/// Snapshot the terminal-identifying process variables without allocating.
pub fn environmentFromMap(environ: *const std.process.Environ.Map) Environment {
    return .{
        .term_program = environ.get("TERM_PROGRAM"),
        .terminal_emulator = environ.get("TERMINAL_EMULATOR"),
        .term = environ.get("TERM"),
        .color_term = environ.get("COLORTERM"),
        .tmux = environ.get("TMUX"),
        .kitty_window_id = environ.get("KITTY_WINDOW_ID"),
        .ghostty_resources_dir = environ.get("GHOSTTY_RESOURCES_DIR"),
        .wezterm_pane = environ.get("WEZTERM_PANE"),
        .warp_session_id = environ.get("WARP_SESSION_ID"),
        .warp_terminal_session_uuid = environ.get("WARP_IS_LOCAL_SHELL_SESSION"),
        .iterm_session_id = environ.get("ITERM_SESSION_ID"),
        .wt_session = environ.get("WT_SESSION"),
        .pi_hyperlinks = environ.get("PI_HYPERLINKS"),
        .pi_image_protocol = environ.get("PI_IMAGE_PROTOCOL"),
        .pi_true_color = environ.get("PI_TRUE_COLOR"),
    };
}

fn eqlLower(value: ?[]const u8, expected: []const u8) bool {
    return if (value) |actual| std.ascii.eqlIgnoreCase(actual, expected) else false;
}

fn containsLower(value: ?[]const u8, needle: []const u8) bool {
    const actual = value orelse return false;
    if (needle.len == 0) return true;
    if (needle.len > actual.len) return false;
    var index: usize = 0;
    while (index + needle.len <= actual.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(actual[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn startsLower(value: ?[]const u8, prefix: []const u8) bool {
    const actual = value orelse return false;
    return actual.len >= prefix.len and std.ascii.eqlIgnoreCase(actual[0..prefix.len], prefix);
}

fn present(value: ?[]const u8) bool {
    return value != null;
}

/// Detect terminal capabilities using the same positive-identification policy as
/// Pi's TypeScript TUI. Image protocols are intentionally disabled in tmux and
/// screen because their passthrough behavior is not reliable enough for redraws.
fn detectCapabilitiesBase(env: Environment, is_windows_console: bool, tmux_forwards_hyperlinks: bool) TerminalCapabilities {
    const has_true_color_hint = eqlLower(env.color_term, "truecolor") or eqlLower(env.color_term, "24bit");

    if (present(env.tmux) or startsLower(env.term, "tmux")) {
        return .{ .images = null, .true_color = has_true_color_hint, .hyperlinks = tmux_forwards_hyperlinks };
    }
    if (startsLower(env.term, "screen")) {
        return .{ .images = null, .true_color = has_true_color_hint, .hyperlinks = false };
    }
    if (present(env.kitty_window_id) or eqlLower(env.term_program, "kitty")) {
        return .{ .images = .kitty, .true_color = true, .hyperlinks = true };
    }
    if (eqlLower(env.term_program, "ghostty") or containsLower(env.term, "ghostty") or present(env.ghostty_resources_dir)) {
        return .{ .images = .kitty, .true_color = true, .hyperlinks = true };
    }
    if (present(env.wezterm_pane) or eqlLower(env.term_program, "wezterm")) {
        return .{ .images = .kitty, .true_color = true, .hyperlinks = true };
    }
    if (eqlLower(env.term_program, "warpterminal") or present(env.warp_session_id) or present(env.warp_terminal_session_uuid)) {
        return .{ .images = .kitty, .true_color = true, .hyperlinks = true };
    }
    if (present(env.iterm_session_id) or eqlLower(env.term_program, "iterm.app")) {
        return .{ .images = .iterm2, .true_color = true, .hyperlinks = true };
    }
    if (present(env.wt_session) or eqlLower(env.term_program, "vscode") or eqlLower(env.term_program, "alacritty")) {
        return .{ .images = null, .true_color = true, .hyperlinks = true };
    }
    if (eqlLower(env.terminal_emulator, "jetbrains-jediterm")) {
        return .{ .images = null, .true_color = true, .hyperlinks = false };
    }
    if (is_windows_console) {
        return .{ .images = null, .true_color = true, .hyperlinks = false };
    }
    return .{ .images = null, .true_color = has_true_color_hint, .hyperlinks = false };
}

fn booleanOverride(value: ?[]const u8) ?bool {
    const text = value orelse return null;
    if (std.mem.eql(u8, text, "1")) return true;
    if (std.mem.eql(u8, text, "0")) return false;
    return null;
}

pub fn environmentOverrides(env: Environment) CapabilityOverrides {
    const protocol: ??ImageProtocol = if (env.pi_image_protocol) |value|
        if (std.ascii.eqlIgnoreCase(value, "kitty")) @as(?ImageProtocol, .kitty) else if (std.ascii.eqlIgnoreCase(value, "iterm2")) @as(?ImageProtocol, .iterm2) else if (std.ascii.eqlIgnoreCase(value, "none") or std.mem.eql(u8, value, "0")) @as(?ImageProtocol, null) else null
    else
        null;
    return .{
        .images = protocol,
        .true_color = booleanOverride(env.pi_true_color),
        .hyperlinks = booleanOverride(env.pi_hyperlinks),
    };
}

pub fn applyOverrides(base: TerminalCapabilities, overrides: CapabilityOverrides) TerminalCapabilities {
    return .{
        .images = if (overrides.images) |value| value else base.images,
        .true_color = overrides.true_color orelse base.true_color,
        .hyperlinks = overrides.hyperlinks orelse base.hyperlinks,
    };
}

pub fn detectCapabilities(env: Environment, is_windows_console: bool, tmux_forwards_hyperlinks: bool) TerminalCapabilities {
    return applyOverrides(detectCapabilitiesBase(env, is_windows_console, tmux_forwards_hyperlinks), environmentOverrides(env));
}

/// Explicit cache object avoids hidden process-global state and permits separate
/// capability views for embedded clients and extension hosts.
pub const CapabilityCache = struct {
    value: ?TerminalCapabilities = null,
    overrides: CapabilityOverrides = .{},

    pub fn get(self: *CapabilityCache, env: Environment, is_windows_console: bool, tmux_forwards_hyperlinks: bool) TerminalCapabilities {
        if (self.value == null) self.value = applyOverrides(detectCapabilities(env, is_windows_console, tmux_forwards_hyperlinks), self.overrides);
        return self.value.?;
    }

    pub fn reset(self: *CapabilityCache) void {
        self.value = null;
    }

    pub fn set(self: *CapabilityCache, value: TerminalCapabilities) void {
        self.value = value;
    }

    pub fn setOverrides(self: *CapabilityCache, overrides: CapabilityOverrides) void {
        self.overrides = overrides;
        self.reset();
    }
};

pub const CellDimensionState = struct {
    value: CellDimensions = .{},

    pub fn get(self: *const CellDimensionState) CellDimensions {
        return self.value;
    }

    pub fn set(self: *CellDimensionState, value: CellDimensions) void {
        self.value = value.normalized();
    }
};

pub const kitty_prefix = "\x1b_G";
pub const iterm2_prefix = "\x1b]1337;File=";
pub const string_terminator = "\x1b\\";

pub fn isImageLine(line: []const u8) bool {
    return std.mem.indexOf(u8, line, kitty_prefix) != null or std.mem.indexOf(u8, line, iterm2_prefix) != null;
}

pub fn allocateImageId(io: std.Io) u32 {
    var bytes: [4]u8 = undefined;
    io.random(&bytes);
    var id = readLe32(&bytes);
    if (id == 0) id = 1;
    return id;
}

pub const KittyEncodeOptions = struct {
    columns: ?u32 = null,
    rows: ?u32 = null,
    image_id: ?u32 = null,
    move_cursor: bool = true,
};

fn appendIntParam(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: u64) !void {
    const formatted = try std.fmt.allocPrint(gpa, ",{s}={d}", .{ key, value });
    defer gpa.free(formatted);
    try out.appendSlice(gpa, formatted);
}

/// Encode already-base64 image bytes as a Kitty direct-transmission command.
/// Kitty requires payload chunks no larger than 4096 bytes.
pub fn encodeKitty(gpa: std.mem.Allocator, base64_data: []const u8, options: KittyEncodeOptions) ![]u8 {
    const chunk_size: usize = 4096;
    var controls: std.ArrayList(u8) = .empty;
    defer controls.deinit(gpa);
    try controls.appendSlice(gpa, "a=T,f=100,q=2");
    if (!options.move_cursor) try controls.appendSlice(gpa, ",C=1");
    if (options.columns) |columns| if (columns != 0) try appendIntParam(gpa, &controls, "c", columns);
    if (options.rows) |rows| if (rows != 0) try appendIntParam(gpa, &controls, "r", rows);
    if (options.image_id) |image_id| if (image_id != 0) try appendIntParam(gpa, &controls, "i", image_id);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    if (base64_data.len <= chunk_size) {
        try out.appendSlice(gpa, kitty_prefix);
        try out.appendSlice(gpa, controls.items);
        try out.append(gpa, ';');
        try out.appendSlice(gpa, base64_data);
        try out.appendSlice(gpa, string_terminator);
        return try out.toOwnedSlice(gpa);
    }

    var offset: usize = 0;
    var first = true;
    while (offset < base64_data.len) {
        const end = @min(base64_data.len, offset + chunk_size);
        const last = end == base64_data.len;
        try out.appendSlice(gpa, kitty_prefix);
        if (first) {
            try out.appendSlice(gpa, controls.items);
            try out.appendSlice(gpa, ",m=1;");
            first = false;
        } else if (last) {
            try out.appendSlice(gpa, "m=0;");
        } else {
            try out.appendSlice(gpa, "m=1;");
        }
        try out.appendSlice(gpa, base64_data[offset..end]);
        try out.appendSlice(gpa, string_terminator);
        offset = end;
    }
    return try out.toOwnedSlice(gpa);
}

pub fn deleteKittyImage(gpa: std.mem.Allocator, image_id: u32) ![]u8 {
    return std.fmt.allocPrint(gpa, "\x1b_Ga=d,d=I,i={d},q=2\x1b\\", .{image_id});
}

pub const delete_all_kitty_images = "\x1b_Ga=d,d=A,q=2\x1b\\";
pub const delete_all_kitty_placements = "\x1b_Ga=d,d=a,q=2\x1b\\";

pub const ITermDimension = union(enum) {
    cells: u32,
    value: []const u8,
};

pub const ITerm2EncodeOptions = struct {
    width: ?ITermDimension = null,
    height: ?ITermDimension = null,
    name: ?[]const u8 = null,
    preserve_aspect_ratio: bool = true,
    inline_image: bool = true,
};

fn appendITermDimension(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: ITermDimension) !void {
    try out.append(gpa, ';');
    try out.appendSlice(gpa, key);
    try out.append(gpa, '=');
    switch (value) {
        .cells => |cells| {
            const formatted = try std.fmt.allocPrint(gpa, "{d}", .{cells});
            defer gpa.free(formatted);
            try out.appendSlice(gpa, formatted);
        },
        .value => |text| try out.appendSlice(gpa, text),
    }
}

pub fn decodedBase64Size(base64_data: []const u8) !usize {
    return std.base64.standard.Decoder.calcSizeForSlice(base64_data);
}

pub fn encodeITerm2(gpa: std.mem.Allocator, base64_data: []const u8, options: ITerm2EncodeOptions) ![]u8 {
    const decoded_size = try decodedBase64Size(base64_data);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const head = try std.fmt.allocPrint(gpa, "\x1b]1337;File=inline={d};size={d}", .{
        @intFromBool(options.inline_image),
        decoded_size,
    });
    defer gpa.free(head);
    try out.appendSlice(gpa, head);
    if (options.width) |width| try appendITermDimension(gpa, &out, "width", width);
    if (options.height) |height| try appendITermDimension(gpa, &out, "height", height);
    if (options.name) |name| {
        const encoded_len = std.base64.standard.Encoder.calcSize(name.len);
        const encoded = try gpa.alloc(u8, encoded_len);
        defer gpa.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, name);
        try out.appendSlice(gpa, ";name=");
        try out.appendSlice(gpa, encoded);
    }
    if (!options.preserve_aspect_ratio) try out.appendSlice(gpa, ";preserveAspectRatio=0");
    try out.append(gpa, ':');
    try out.appendSlice(gpa, base64_data);
    try out.append(gpa, 0x07);
    return try out.toOwnedSlice(gpa);
}

pub const ImageCellSize = struct {
    columns: u32,
    rows: u32,
};

pub const KittyImageMetadata = struct {
    image_id: u32,
    columns: u32,
    rows: u32,
    width_px: u32,
    height_px: u32,
};

const RegisteredKittyImageMetadata = struct {
    metadata: KittyImageMetadata,
    transmission_generation: u64,
};

pub const KittyImagePlacement = struct {
    image_id: u32,
    transmission_generation: u64,
    transmission_bytes: usize,
    estimated_decoded_bytes: u64,
    sequence: []u8,
    replacement_line: []u8,

    pub fn deinit(self: *KittyImagePlacement, gpa: std.mem.Allocator) void {
        gpa.free(self.sequence);
        gpa.free(self.replacement_line);
        self.* = undefined;
    }
};

const ControlRange = struct {
    command_start: usize,
    controls_start: usize,
    controls_end: usize,
};

fn firstKittyControls(line: []const u8) ?ControlRange {
    const start = std.mem.indexOf(u8, line, kitty_prefix) orelse return null;
    const controls_start = start + kitty_prefix.len;
    const rel_end = std.mem.indexOfScalar(u8, line[controls_start..], ';') orelse return null;
    return .{ .command_start = start, .controls_start = controls_start, .controls_end = controls_start + rel_end };
}

fn controlValue(controls: []const u8, key: []const u8) ?[]const u8 {
    var iterator = std.mem.splitScalar(u8, controls, ',');
    while (iterator.next()) |control| {
        const equals = std.mem.indexOfScalar(u8, control, '=') orelse continue;
        if (std.mem.eql(u8, control[0..equals], key)) return control[equals + 1 ..];
    }
    return null;
}

fn hasControl(controls: []const u8, key: []const u8, expected: []const u8) bool {
    const value = controlValue(controls, key) orelse return false;
    return std.mem.eql(u8, value, expected);
}

fn parseImageId(line: []const u8) ?u32 {
    const range = firstKittyControls(line) orelse return null;
    const value = controlValue(line[range.controls_start..range.controls_end], "i") orelse return null;
    return std.fmt.parseUnsigned(u32, value, 10) catch null;
}

fn placementControlKey(key: []const u8) bool {
    const allowed = [_][]const u8{ "i", "p", "x", "y", "w", "h", "X", "Y", "c", "r", "C", "U", "z", "P", "Q", "H", "V" };
    for (allowed) |candidate| if (std.mem.eql(u8, key, candidate)) return true;
    return false;
}

pub const KittyRegistry = struct {
    gpa: std.mem.Allocator,
    entries: std.AutoHashMap(u32, RegisteredKittyImageMetadata),
    order: std.ArrayList(u32) = .empty,
    transmission_generation: u64 = 0,
    max_entries: usize = 1000,

    pub fn init(gpa: std.mem.Allocator) KittyRegistry {
        return .{
            .gpa = gpa,
            .entries = std.AutoHashMap(u32, RegisteredKittyImageMetadata).init(gpa),
        };
    }

    pub fn deinit(self: *KittyRegistry) void {
        self.entries.deinit();
        self.order.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn register(self: *KittyRegistry, metadata: KittyImageMetadata) !void {
        self.transmission_generation +%= 1;
        if (self.transmission_generation == 0) self.transmission_generation = 1;
        if (self.entries.contains(metadata.image_id)) {
            var index: usize = 0;
            while (index < self.order.items.len) : (index += 1) {
                if (self.order.items[index] == metadata.image_id) {
                    _ = self.order.orderedRemove(index);
                    break;
                }
            }
        }
        try self.entries.put(metadata.image_id, .{
            .metadata = metadata,
            .transmission_generation = self.transmission_generation,
        });
        try self.order.append(self.gpa, metadata.image_id);
        while (self.order.items.len > self.max_entries) {
            const oldest = self.order.orderedRemove(0);
            _ = self.entries.remove(oldest);
        }
    }

    fn registered(self: *const KittyRegistry, line: []const u8) ?RegisteredKittyImageMetadata {
        const image_id = parseImageId(line) orelse return null;
        return self.entries.get(image_id);
    }

    pub fn getMetadata(self: *const KittyRegistry, line: []const u8) ?KittyImageMetadata {
        return (self.registered(line) orelse return null).metadata;
    }

    /// Convert the direct-transmission portion of an emitted image line to a
    /// placement-only command. This allows redraws without retransmitting pixels.
    pub fn getPlacement(self: *const KittyRegistry, gpa: std.mem.Allocator, line: []const u8) !?KittyImagePlacement {
        const first = firstKittyControls(line) orelse return null;
        const registered_metadata = self.registered(line) orelse return null;

        var command_start = first.command_start;
        var controls_start = first.controls_start;
        var controls_end = first.controls_end;
        var transmission_end: usize = undefined;
        while (true) {
            const rel_terminator = std.mem.indexOf(u8, line[controls_end + 1 ..], string_terminator) orelse return null;
            transmission_end = controls_end + 1 + rel_terminator + string_terminator.len;
            const controls = line[controls_start..controls_end];
            if (!hasControl(controls, "m", "1")) break;
            command_start = transmission_end;
            if (!std.mem.startsWith(u8, line[command_start..], kitty_prefix)) return null;
            controls_start = command_start + kitty_prefix.len;
            const rel_controls_end = std.mem.indexOfScalar(u8, line[controls_start..], ';') orelse return null;
            controls_end = controls_start + rel_controls_end;
        }

        var sequence_list: std.ArrayList(u8) = .empty;
        errdefer sequence_list.deinit(gpa);
        try sequence_list.appendSlice(gpa, "\x1b_Ga=p,q=2");
        var iterator = std.mem.splitScalar(u8, line[first.controls_start..first.controls_end], ',');
        while (iterator.next()) |control| {
            const equals = std.mem.indexOfScalar(u8, control, '=') orelse continue;
            if (!placementControlKey(control[0..equals])) continue;
            try sequence_list.append(gpa, ',');
            try sequence_list.appendSlice(gpa, control);
        }
        try sequence_list.appendSlice(gpa, string_terminator);
        const sequence = try sequence_list.toOwnedSlice(gpa);
        errdefer gpa.free(sequence);

        var replacement: std.ArrayList(u8) = .empty;
        errdefer replacement.deinit(gpa);
        try replacement.appendSlice(gpa, line[0..first.command_start]);
        try replacement.appendSlice(gpa, sequence);
        try replacement.appendSlice(gpa, line[transmission_end..]);
        const replacement_line = try replacement.toOwnedSlice(gpa);

        const width: u64 = registered_metadata.metadata.width_px;
        const height: u64 = registered_metadata.metadata.height_px;
        return .{
            .image_id = registered_metadata.metadata.image_id,
            .transmission_generation = registered_metadata.transmission_generation,
            .transmission_bytes = transmission_end - first.command_start,
            .estimated_decoded_bytes = std.math.mul(u64, std.math.mul(u64, width, height) catch std.math.maxInt(u64), 4) catch std.math.maxInt(u64),
            .sequence = sequence,
            .replacement_line = replacement_line,
        };
    }

    /// Rewrite the first Kitty command so only a vertical source slice is placed.
    pub fn cropLine(self: *const KittyRegistry, gpa: std.mem.Allocator, line: []const u8, hidden_rows: u32, visible_rows: u32) ![]u8 {
        const metadata = self.getMetadata(line) orelse return gpa.dupe(u8, line);
        const range = firstKittyControls(line) orelse return gpa.dupe(u8, line);
        if (hidden_rows >= metadata.rows or visible_rows == 0) return gpa.dupe(u8, line);
        const cropped_rows = @min(visible_rows, metadata.rows - hidden_rows);
        if (hidden_rows == 0 and cropped_rows == metadata.rows) return gpa.dupe(u8, line);

        const source_y_u64 = (@as(u64, metadata.height_px) * hidden_rows) / metadata.rows;
        const end_numerator = @as(u64, metadata.height_px) * (@as(u64, hidden_rows) + cropped_rows);
        const source_end = @min(@as(u64, metadata.height_px), (end_numerator + metadata.rows - 1) / metadata.rows);
        const source_height = @max(@as(u64, 1), source_end - source_y_u64);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try out.appendSlice(gpa, line[0..range.command_start]);
        try out.appendSlice(gpa, kitty_prefix);
        var wrote_control = false;
        var iterator = std.mem.splitScalar(u8, line[range.controls_start..range.controls_end], ',');
        while (iterator.next()) |control| {
            const equals = std.mem.indexOfScalar(u8, control, '=') orelse continue;
            const key = control[0..equals];
            if (std.mem.eql(u8, key, "y") or std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "r")) continue;
            if (wrote_control) try out.append(gpa, ',');
            try out.appendSlice(gpa, control);
            wrote_control = true;
        }
        const crop_controls = try std.fmt.allocPrint(gpa, "{s}y={d},h={d},r={d};", .{
            if (wrote_control) "," else "",
            source_y_u64,
            source_height,
            cropped_rows,
        });
        defer gpa.free(crop_controls);
        try out.appendSlice(gpa, crop_controls);
        try out.appendSlice(gpa, line[range.controls_end + 1 ..]);
        return try out.toOwnedSlice(gpa);
    }
};

pub fn calculateImageCellSize(
    image_dimensions_raw: ImageDimensions,
    max_width_cells_raw: u32,
    max_height_cells_raw: ?u32,
    cell_dimensions_raw: CellDimensions,
) ImageCellSize {
    const image_dimensions = image_dimensions_raw.normalized();
    const cell_dimensions = cell_dimensions_raw.normalized();
    const max_width_cells = @max(1, max_width_cells_raw);
    const max_height_cells = if (max_height_cells_raw) |value| @max(1, value) else null;

    const width_scale = (@as(f64, @floatFromInt(max_width_cells)) * @as(f64, @floatFromInt(cell_dimensions.width_px))) /
        @as(f64, @floatFromInt(image_dimensions.width_px));
    const height_scale = if (max_height_cells) |max_height|
        (@as(f64, @floatFromInt(max_height)) * @as(f64, @floatFromInt(cell_dimensions.height_px))) /
            @as(f64, @floatFromInt(image_dimensions.height_px))
    else
        width_scale;
    const scale = @min(width_scale, height_scale);
    const scaled_width_px = @as(f64, @floatFromInt(image_dimensions.width_px)) * scale;
    const scaled_height_px = @as(f64, @floatFromInt(image_dimensions.height_px)) * scale;
    const columns_float = @ceil(scaled_width_px / @as(f64, @floatFromInt(cell_dimensions.width_px)));
    const rows_float = @ceil(scaled_height_px / @as(f64, @floatFromInt(cell_dimensions.height_px)));
    const columns: u32 = @intFromFloat(@max(1.0, columns_float));
    const rows: u32 = @intFromFloat(@max(1.0, rows_float));
    return .{
        .columns = @min(max_width_cells, columns),
        .rows = if (max_height_cells) |max_height| @min(max_height, rows) else rows,
    };
}

pub fn calculateImageRows(image_dimensions: ImageDimensions, target_width_cells: u32, cell_dimensions: CellDimensions) u32 {
    return calculateImageCellSize(image_dimensions, target_width_cells, null, cell_dimensions).rows;
}

fn readBe16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readLe16(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

fn readBe32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) | (@as(u32, bytes[2]) << 8) | bytes[3];
}

fn readLe32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
}

pub fn getPngDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 24) return null;
    if (!std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n")) return null;
    const width = readBe32(bytes[16..20]);
    const height = readBe32(bytes[20..24]);
    if (width == 0 or height == 0) return null;
    return .{ .width_px = width, .height_px = height };
}

pub fn getJpegDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 2 or bytes[0] != 0xff or bytes[1] != 0xd8) return null;
    var offset: usize = 2;
    while (offset + 9 < bytes.len) {
        if (bytes[offset] != 0xff) {
            offset += 1;
            continue;
        }
        while (offset < bytes.len and bytes[offset] == 0xff) : (offset += 1) {}
        if (offset >= bytes.len) return null;
        const marker = bytes[offset];
        // Standalone markers do not carry a length.
        if (marker == 0xd8 or marker == 0xd9 or (marker >= 0xd0 and marker <= 0xd7) or marker == 0x01) {
            offset += 1;
            continue;
        }
        if (offset + 2 >= bytes.len) return null;
        const segment_length = readBe16(bytes[offset + 1 .. offset + 3]);
        if (segment_length < 2) return null;
        const segment_start = offset - 1;
        const sof = marker >= 0xc0 and marker <= 0xc2;
        if (sof) {
            if (segment_start + 9 >= bytes.len) return null;
            const height = readBe16(bytes[segment_start + 5 .. segment_start + 7]);
            const width = readBe16(bytes[segment_start + 7 .. segment_start + 9]);
            if (width == 0 or height == 0) return null;
            return .{ .width_px = width, .height_px = height };
        }
        offset += 1 + segment_length;
    }
    return null;
}

pub fn getGifDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 10) return null;
    if (!std.mem.eql(u8, bytes[0..6], "GIF87a") and !std.mem.eql(u8, bytes[0..6], "GIF89a")) return null;
    const width = readLe16(bytes[6..8]);
    const height = readLe16(bytes[8..10]);
    if (width == 0 or height == 0) return null;
    return .{ .width_px = width, .height_px = height };
}

pub fn getWebpDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 25) return null;
    if (!std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WEBP")) return null;
    const chunk = bytes[12..16];
    if (std.mem.eql(u8, chunk, "VP8 ")) {
        if (bytes.len < 30) return null;
        const width = readLe16(bytes[26..28]) & 0x3fff;
        const height = readLe16(bytes[28..30]) & 0x3fff;
        if (width == 0 or height == 0) return null;
        return .{ .width_px = width, .height_px = height };
    }
    if (std.mem.eql(u8, chunk, "VP8L")) {
        if (bytes.len < 25 or bytes[20] != 0x2f) return null;
        const bits = readLe32(bytes[21..25]);
        return .{
            .width_px = (bits & 0x3fff) + 1,
            .height_px = ((bits >> 14) & 0x3fff) + 1,
        };
    }
    if (std.mem.eql(u8, chunk, "VP8X")) {
        if (bytes.len < 30) return null;
        const width = @as(u32, bytes[24]) | (@as(u32, bytes[25]) << 8) | (@as(u32, bytes[26]) << 16);
        const height = @as(u32, bytes[27]) | (@as(u32, bytes[28]) << 8) | (@as(u32, bytes[29]) << 16);
        return .{ .width_px = width + 1, .height_px = height + 1 };
    }
    return null;
}

pub fn getImageDimensions(bytes: []const u8, mime_type: []const u8) ?ImageDimensions {
    if (std.mem.eql(u8, mime_type, "image/png")) return getPngDimensions(bytes);
    if (std.mem.eql(u8, mime_type, "image/jpeg")) return getJpegDimensions(bytes);
    if (std.mem.eql(u8, mime_type, "image/gif")) return getGifDimensions(bytes);
    if (std.mem.eql(u8, mime_type, "image/webp")) return getWebpDimensions(bytes);
    return null;
}

pub fn getImageDimensionsBase64(gpa: std.mem.Allocator, base64_data: []const u8, mime_type: []const u8) !?ImageDimensions {
    const size = try decodedBase64Size(base64_data);
    const decoded = try gpa.alloc(u8, size);
    defer gpa.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, base64_data);
    return getImageDimensions(decoded, mime_type);
}

pub const ImageRenderOptions = struct {
    max_width_cells: u32 = 80,
    max_height_cells: ?u32 = null,
    preserve_aspect_ratio: bool = true,
    image_id: ?u32 = null,
    move_cursor: bool = true,
};

pub const RenderedImage = struct {
    sequence: []u8,
    columns: u32,
    rows: u32,
    image_id: ?u32,

    pub fn deinit(self: *RenderedImage, gpa: std.mem.Allocator) void {
        gpa.free(self.sequence);
        self.* = undefined;
    }
};

pub fn renderImage(
    gpa: std.mem.Allocator,
    capabilities: TerminalCapabilities,
    cell_dimensions: CellDimensions,
    registry: ?*KittyRegistry,
    base64_data: []const u8,
    image_dimensions: ImageDimensions,
    options: ImageRenderOptions,
) !?RenderedImage {
    const protocol = capabilities.images orelse return null;
    const size = calculateImageCellSize(image_dimensions, options.max_width_cells, options.max_height_cells, cell_dimensions);
    switch (protocol) {
        .kitty => {
            if (options.image_id) |image_id| {
                if (registry) |active_registry| try active_registry.register(.{
                    .image_id = image_id,
                    .columns = size.columns,
                    .rows = size.rows,
                    .width_px = image_dimensions.width_px,
                    .height_px = image_dimensions.height_px,
                });
            }
            return .{
                .sequence = try encodeKitty(gpa, base64_data, .{
                    .columns = size.columns,
                    .rows = size.rows,
                    .image_id = options.image_id,
                    .move_cursor = options.move_cursor,
                }),
                .columns = size.columns,
                .rows = size.rows,
                .image_id = options.image_id,
            };
        },
        .iterm2 => return .{
            .sequence = try encodeITerm2(gpa, base64_data, .{
                .width = .{ .cells = size.columns },
                .height = .{ .value = "auto" },
                .preserve_aspect_ratio = options.preserve_aspect_ratio,
            }),
            .columns = size.columns,
            .rows = size.rows,
            .image_id = null,
        },
    }
}

pub fn hyperlink(gpa: std.mem.Allocator, text: []const u8, url: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "\x1b]8;;{s}\x1b\\{s}\x1b]8;;\x1b\\", .{ url, text });
}

pub fn isAbsolutePath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '\\') return true;
    return path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and (path[2] == '/' or path[2] == '\\');
}

pub fn shortenImagePath(path: []const u8, home: ?[]const u8) []const u8 {
    const home_path = home orelse return path;
    if (std.mem.eql(u8, path, home_path)) return path[path.len..];
    if (path.len > home_path.len and std.mem.startsWith(u8, path, home_path) and (path[home_path.len] == '/' or path[home_path.len] == '\\')) {
        return path[home_path.len..];
    }
    return path;
}

fn isUrlUnreserved(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~' or byte == '/' or byte == ':';
}

pub fn pathToFileUrl(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!isAbsolutePath(path)) return error.PathNotAbsolute;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    if (path.len >= 3 and path[1] == ':') try out.appendSlice(gpa, "file:///") else try out.appendSlice(gpa, "file://");
    const hex = "0123456789ABCDEF";
    for (path) |raw_byte| {
        const byte = if (raw_byte == '\\') '/' else raw_byte;
        if (isUrlUnreserved(byte)) {
            try out.append(gpa, byte);
        } else {
            try out.append(gpa, '%');
            try out.append(gpa, hex[byte >> 4]);
            try out.append(gpa, hex[byte & 0x0f]);
        }
    }
    return try out.toOwnedSlice(gpa);
}

pub fn imageFallback(
    gpa: std.mem.Allocator,
    capabilities: TerminalCapabilities,
    mime_type: []const u8,
    dimensions: ?ImageDimensions,
    filename: ?[]const u8,
    home: ?[]const u8,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "[Image:");
    if (filename) |path| {
        try out.append(gpa, ' ');
        const shortened_tail = shortenImagePath(path, home);
        var display_owned: ?[]u8 = null;
        defer if (display_owned) |owned| gpa.free(owned);
        const display: []const u8 = if (shortened_tail.ptr == path.ptr and shortened_tail.len == path.len)
            path
        else if (shortened_tail.len == 0) blk: {
            display_owned = try gpa.dupe(u8, "~");
            break :blk display_owned.?;
        } else blk: {
            display_owned = try std.fmt.allocPrint(gpa, "~{s}", .{shortened_tail});
            break :blk display_owned.?;
        };
        if (capabilities.hyperlinks and isAbsolutePath(path)) {
            const url = try pathToFileUrl(gpa, path);
            defer gpa.free(url);
            const linked = try hyperlink(gpa, display, url);
            defer gpa.free(linked);
            try out.appendSlice(gpa, linked);
        } else {
            try out.appendSlice(gpa, display);
        }
    }
    try out.appendSlice(gpa, " [");
    try out.appendSlice(gpa, mime_type);
    try out.append(gpa, ']');
    if (dimensions) |dims| {
        const suffix = try std.fmt.allocPrint(gpa, " {d}x{d}", .{ dims.width_px, dims.height_px });
        defer gpa.free(suffix);
        try out.appendSlice(gpa, suffix);
    }
    try out.append(gpa, ']');
    return try out.toOwnedSlice(gpa);
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "terminal environment snapshot maps emulator variables" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("TERM_PROGRAM", "kitty");
    try env.put("COLORTERM", "truecolor");
    const snapshot = environmentFromMap(&env);
    try std.testing.expectEqualStrings("kitty", snapshot.term_program.?);
    try std.testing.expectEqualStrings("truecolor", snapshot.color_term.?);
    try std.testing.expect(snapshot.tmux == null);
}

test "terminal capability detection keeps tmux conservative" {
    const caps = detectCapabilities(.{
        .term = "tmux-256color",
        .color_term = "truecolor",
        .kitty_window_id = "42",
    }, false, true);
    try std.testing.expect(caps.images == null);
    try std.testing.expect(caps.true_color);
    try std.testing.expect(caps.hyperlinks);
}

test "terminal capability detection identifies supported emulators" {
    const kitty = detectCapabilities(.{ .term_program = "kitty" }, false, false);
    try std.testing.expectEqual(ImageProtocol.kitty, kitty.images.?);
    const iterm = detectCapabilities(.{ .iterm_session_id = "w0t0p0" }, false, false);
    try std.testing.expectEqual(ImageProtocol.iterm2, iterm.images.?);
    const vscode = detectCapabilities(.{ .term_program = "vscode" }, false, false);
    try std.testing.expect(vscode.images == null and vscode.true_color and vscode.hyperlinks);
    const unknown = detectCapabilities(.{ .color_term = "24bit" }, false, false);
    try std.testing.expect(unknown.images == null and unknown.true_color and !unknown.hyperlinks);
}

test "capability and cell dimension state are overrideable" {
    var cache: CapabilityCache = .{};
    const first = cache.get(.{ .term_program = "kitty" }, false, false);
    try std.testing.expectEqual(ImageProtocol.kitty, first.images.?);
    const still_cached = cache.get(.{ .term_program = "iterm.app" }, false, false);
    try std.testing.expectEqual(ImageProtocol.kitty, still_cached.images.?);
    cache.reset();
    try std.testing.expectEqual(ImageProtocol.iterm2, cache.get(.{ .term_program = "iterm.app" }, false, false).images.?);
    cache.set(.{});
    try std.testing.expect(cache.value.?.images == null);

    var cells: CellDimensionState = .{};
    cells.set(.{ .width_px = 0, .height_px = 0 });
    try std.testing.expectEqual(@as(u32, 1), cells.get().width_px);
    try std.testing.expectEqual(@as(u32, 1), cells.get().height_px);
}

test "environment and programmatic terminal capability overrides are layered" {
    const env_caps = detectCapabilities(.{
        .term_program = "kitty",
        .pi_hyperlinks = "0",
        .pi_image_protocol = "none",
        .pi_true_color = "0",
    }, false, false);
    try std.testing.expect(env_caps.images == null);
    try std.testing.expect(!env_caps.true_color);
    try std.testing.expect(!env_caps.hyperlinks);

    var cache: CapabilityCache = .{};
    cache.setOverrides(.{ .images = @as(?ImageProtocol, .iterm2), .hyperlinks = true });
    const overridden = cache.get(.{ .term_program = "kitty" }, false, false);
    try std.testing.expect(overridden.images.? == .iterm2);
    try std.testing.expect(overridden.hyperlinks);
}

test "Kitty encoding uses direct and chunked transmission forms" {
    const gpa = std.testing.allocator;
    const direct = try encodeKitty(gpa, "aGVsbG8=", .{ .columns = 20, .rows = 4, .image_id = 7, .move_cursor = false });
    defer gpa.free(direct);
    try std.testing.expectEqualStrings("\x1b_Ga=T,f=100,q=2,C=1,c=20,r=4,i=7;aGVsbG8=\x1b\\", direct);

    const large = try gpa.alloc(u8, 9000);
    defer gpa.free(large);
    @memset(large, 'A');
    const chunked = try encodeKitty(gpa, large, .{});
    defer gpa.free(chunked);
    try std.testing.expect(std.mem.indexOf(u8, chunked, "a=T,f=100,q=2,m=1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, chunked, "\x1b_Gm=1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, chunked, "\x1b_Gm=0;") != null);
    try std.testing.expect(isImageLine("prefix\x1b_Ga=T;payload\x1b\\"));
}

test "Kitty delete commands free image data or placements" {
    const command = try deleteKittyImage(std.testing.allocator, 44);
    defer std.testing.allocator.free(command);
    try std.testing.expectEqualStrings("\x1b_Ga=d,d=I,i=44,q=2\x1b\\", command);
    try std.testing.expect(std.mem.indexOf(u8, delete_all_kitty_images, "d=A") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_all_kitty_placements, "d=a") != null);
}

test "iTerm2 encoding reports decoded size and name" {
    const encoded = try encodeITerm2(std.testing.allocator, "aGVsbG8=", .{
        .width = .{ .cells = 12 },
        .height = .{ .value = "auto" },
        .name = "hello.png",
        .preserve_aspect_ratio = false,
    });
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.startsWith(u8, encoded, "\x1b]1337;File=inline=1;size=5;width=12;height=auto;name="));
    try std.testing.expect(std.mem.indexOf(u8, encoded, "aGVsbG8ucG5n") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, ";preserveAspectRatio=0:aGVsbG8=\x07") != null);
}

test "Kitty registry produces placement-only redraw and crop" {
    const gpa = std.testing.allocator;
    var registry = KittyRegistry.init(gpa);
    defer registry.deinit();
    try registry.register(.{ .image_id = 9, .columns = 20, .rows = 10, .width_px = 200, .height_px = 100 });
    const line = "left\x1b_Ga=T,f=100,q=2,c=20,r=10,i=9,m=1;AAAA\x1b\\\x1b_Gm=0;BBBB\x1b\\right";
    var placement = (try registry.getPlacement(gpa, line)).?;
    defer placement.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 9), placement.image_id);
    try std.testing.expectEqual(@as(u64, 80_000), placement.estimated_decoded_bytes);
    try std.testing.expectEqualStrings("\x1b_Ga=p,q=2,c=20,r=10,i=9\x1b\\", placement.sequence);
    try std.testing.expectEqualStrings("left\x1b_Ga=p,q=2,c=20,r=10,i=9\x1b\\right", placement.replacement_line);

    const cropped = try registry.cropLine(gpa, line, 2, 3);
    defer gpa.free(cropped);
    try std.testing.expect(std.mem.indexOf(u8, cropped, "y=20,h=30,r=3;") != null);
    try std.testing.expect(std.mem.endsWith(u8, cropped, "right"));
}

test "Kitty registry refreshes generations and evicts oldest metadata" {
    var registry = KittyRegistry.init(std.testing.allocator);
    defer registry.deinit();
    registry.max_entries = 2;
    try registry.register(.{ .image_id = 1, .columns = 1, .rows = 1, .width_px = 1, .height_px = 1 });
    try registry.register(.{ .image_id = 2, .columns = 1, .rows = 1, .width_px = 1, .height_px = 1 });
    try registry.register(.{ .image_id = 1, .columns = 2, .rows = 2, .width_px = 2, .height_px = 2 });
    try registry.register(.{ .image_id = 3, .columns = 1, .rows = 1, .width_px = 1, .height_px = 1 });
    try std.testing.expect(registry.entries.contains(1));
    try std.testing.expect(!registry.entries.contains(2));
    try std.testing.expect(registry.entries.contains(3));
}

test "image cell sizing preserves pixel aspect ratio" {
    const size = calculateImageCellSize(.{ .width_px = 1600, .height_px = 900 }, 80, 20, .{ .width_px = 10, .height_px = 20 });
    try std.testing.expectEqual(@as(u32, 72), size.columns);
    try std.testing.expectEqual(@as(u32, 20), size.rows);
    try std.testing.expectEqual(@as(u32, 23), calculateImageRows(.{ .width_px = 1600, .height_px = 900 }, 80, .{ .width_px = 10, .height_px = 20 }));
}

test "PNG GIF JPEG and WebP dimensions are parsed without decoders" {
    var png = [_]u8{0} ** 24;
    @memcpy(png[0..8], "\x89PNG\r\n\x1a\n");
    png[16] = 0;
    png[17] = 0;
    png[18] = 2;
    png[19] = 128;
    png[20] = 0;
    png[21] = 0;
    png[22] = 1;
    png[23] = 224;
    try std.testing.expectEqual(ImageDimensions{ .width_px = 640, .height_px = 480 }, getPngDimensions(&png).?);

    var gif = [_]u8{0} ** 10;
    @memcpy(gif[0..6], "GIF89a");
    gif[6] = 64;
    gif[7] = 1;
    gif[8] = 200;
    gif[9] = 0;
    try std.testing.expectEqual(ImageDimensions{ .width_px = 320, .height_px = 200 }, getGifDimensions(&gif).?);

    const jpeg = [_]u8{ 0xff, 0xd8, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x01, 0xe0, 0x02, 0x80, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00, 0xff, 0xd9 };
    try std.testing.expectEqual(ImageDimensions{ .width_px = 640, .height_px = 480 }, getJpegDimensions(&jpeg).?);

    var webp = [_]u8{0} ** 30;
    @memcpy(webp[0..4], "RIFF");
    @memcpy(webp[8..12], "WEBP");
    @memcpy(webp[12..16], "VP8X");
    // VP8X stores width-1 and height-1 as little-endian 24-bit integers.
    webp[24] = 0x7f;
    webp[25] = 0x02; // 639
    webp[27] = 0xdf;
    webp[28] = 0x01; // 479
    try std.testing.expectEqual(ImageDimensions{ .width_px = 640, .height_px = 480 }, getWebpDimensions(&webp).?);
}

test "base64 image dimensions dispatch by MIME type" {
    var gif = [_]u8{0} ** 10;
    @memcpy(gif[0..6], "GIF87a");
    gif[6] = 2;
    gif[8] = 3;
    var encoded: [std.base64.standard.Encoder.calcSize(gif.len)]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&encoded, &gif);
    const dimensions = (try getImageDimensionsBase64(std.testing.allocator, &encoded, "image/gif")).?;
    try std.testing.expectEqual(ImageDimensions{ .width_px = 2, .height_px = 3 }, dimensions);
    try std.testing.expect((try getImageDimensionsBase64(std.testing.allocator, &encoded, "image/bmp")) == null);
}

test "render image uses active protocol and registers Kitty metadata" {
    const gpa = std.testing.allocator;
    var registry = KittyRegistry.init(gpa);
    defer registry.deinit();
    var kitty_render = (try renderImage(gpa, .{ .images = .kitty, .true_color = true, .hyperlinks = true }, .{}, &registry, "aGVsbG8=", .{ .width_px = 100, .height_px = 50 }, .{ .max_width_cells = 20, .image_id = 77 })).?;
    defer kitty_render.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 77), kitty_render.image_id.?);
    try std.testing.expect(registry.getMetadata(kitty_render.sequence) != null);

    var iterm_render = (try renderImage(gpa, .{ .images = .iterm2, .true_color = true, .hyperlinks = true }, .{}, null, "aGVsbG8=", .{ .width_px = 100, .height_px = 50 }, .{})).?;
    defer iterm_render.deinit(gpa);
    try std.testing.expect(std.mem.startsWith(u8, iterm_render.sequence, iterm2_prefix));
    try std.testing.expect((try renderImage(gpa, .{}, .{}, null, "aGVsbG8=", .{ .width_px = 1, .height_px = 1 }, .{})) == null);
}

test "hyperlink and image fallback shorten and encode absolute paths" {
    const gpa = std.testing.allocator;
    const url = try pathToFileUrl(gpa, "/home/alice/My Image.png");
    defer gpa.free(url);
    try std.testing.expectEqualStrings("file:///home/alice/My%20Image.png", url);

    const fallback = try imageFallback(gpa, .{ .hyperlinks = true }, "image/png", .{ .width_px = 640, .height_px = 480 }, "/home/alice/My Image.png", "/home/alice");
    defer gpa.free(fallback);
    try std.testing.expect(std.mem.indexOf(u8, fallback, "~/My Image.png") != null);
    try std.testing.expect(std.mem.indexOf(u8, fallback, "file:///home/alice/My%20Image.png") != null);
    try std.testing.expect(std.mem.indexOf(u8, fallback, "[image/png] 640x480") != null);
}

test "allocated image IDs are never zero" {
    var index: usize = 0;
    while (index < 128) : (index += 1) try std.testing.expect(allocateImageId(std.testing.io) != 0);
}
