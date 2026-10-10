//! VM-owner autocomplete requests, selection and synchronous completion.
//! Promise adoption uses C-created capabilities; no JS host code is evaluated.
const std = @import("std");
const engine_mod = @import("engine.zig");
const components = @import("native_components.zig");
const abort_signal = @import("abort_signal.zig");
const Editor = @import("../tui/editor.zig").Editor;
const keys = @import("../tui/keys.zig");
const text = @import("../tui/terminal_text.zig");
const c = engine_mod.c;
pub const Disposition = enum { pass, handled, submit };
const maximum_items = 4096;
const maximum_text = 1024 * 1024;
pub const Position = struct { lines: c.JSValue, line: usize, col: usize };

pub fn utf16Length(bytes: []const u8) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        const length = std.unicode.utf8ByteSequenceLength(bytes[index]) catch 1;
        const end = @min(bytes.len, index + length);
        const scalar = std.unicode.utf8Decode(bytes[index..end]) catch bytes[index];
        count += if (scalar > 0xffff) 2 else 1;
        index = end;
    }
    return count;
}
pub fn byteColumn(bytes: []const u8, col: usize) !usize {
    var units: usize = 0;
    var index: usize = 0;
    while (index < bytes.len and units < col) {
        const length = std.unicode.utf8ByteSequenceLength(bytes[index]) catch 1;
        const end = @min(bytes.len, index + length);
        const scalar = std.unicode.utf8Decode(bytes[index..end]) catch bytes[index];
        units += if (scalar > 0xffff) 2 else 1;
        index = end;
    }
    if (units != col) return error.InvalidAutocompleteCursor;
    return index;
}
pub fn position(engine: *engine_mod.Engine, editor: *const Editor) !Position {
    const array = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(array);
    var result: Position = .{ .lines = array, .line = 0, .col = 0 };
    var begin: usize = 0;
    var index: usize = 0;
    var found = false;
    var iterator = std.mem.splitScalar(u8, editor.slice(), '\n');
    while (iterator.next()) |line| : (index += 1) {
        if (index >= maximum_items) return error.AutocompleteLineLimit;
        if (c.JS_SetPropertyUint32(engine.context, array, @intCast(index), try engine.checked(c.JS_NewStringLen(engine.context, line.ptr, line.len))) < 0) return error.JavaScriptException;
        if (!found and editor.cursor <= begin + line.len) {
            result.line = index;
            result.col = utf16Length(line[0..editor.cursor -| begin]);
            found = true;
        }
        begin += line.len + 1;
    }
    return result;
}
fn field(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
fn put(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn integer(engine: *engine_mod.Engine, value: c.JSValue, limit: usize) !usize {
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(number) or number < 0 or number != @floor(number) or number > @as(f64, @floatFromInt(limit))) return error.InvalidAutocompleteDimension;
    return @intFromFloat(number);
}

pub const State = struct {
    engine: *engine_mod.Engine,
    editor: *Editor,
    /// Borrowed from the node that owns this State; never stored in callbacks.
    object: c.JSValue,
    tui: c.JSValue,
    provider: ?c.JSValue = null,
    pending: ?c.JSValue = null,
    signal: ?c.JSValue = null,
    items: ?c.JSValue = null,
    prefix: ?c.JSValue = null,
    last_error: ?c.JSValue = null,
    snapshot_text: ?[]u8 = null,
    snapshot_cursor: usize = 0,
    generation: u64 = 0,
    pending_generation: u64 = 0,
    explicit_tab: bool = false,
    forced: bool = false,
    queued: bool = false,
    queued_explicit: bool = false,
    selected: usize = 0,
    item_count: usize = 0,
    max_visible: usize = 5,
    polling: bool = false,

    pub fn init(engine: *engine_mod.Engine, editor: *Editor, object: c.JSValue, tui: c.JSValue) State {
        return .{ .engine = engine, .editor = editor, .object = object, .tui = tui };
    }
    pub fn mark(self: *State, runtime: ?*c.JSRuntime, mark_fn: ?*const c.JS_MarkFunc) void {
        for ([_]?c.JSValue{ self.provider, self.pending, self.signal, self.items, self.prefix, self.last_error }) |value| if (value) |owned| c.JS_MarkValue(runtime, owned, mark_fn);
    }
    pub fn deinit(self: *State, runtime: ?*c.JSRuntime) void {
        for ([_]?c.JSValue{ self.provider, self.pending, self.signal, self.items, self.prefix, self.last_error }) |value| if (value) |owned| c.JS_FreeValueRT(runtime, owned);
        if (self.snapshot_text) |contents| self.engine.gpa.free(contents);
    }
    fn freeOptional(self: *State, value: *?c.JSValue) void {
        if (value.*) |owned| self.engine.freeValue(owned);
        value.* = null;
    }
    fn clearMenu(self: *State) void {
        self.freeOptional(&self.items);
        self.freeOptional(&self.prefix);
        self.item_count = 0;
        self.selected = 0;
    }
    pub fn cancel(self: *State) !void {
        self.generation += 1;
        self.queued = false;
        self.clearMenu();
        if (self.signal) |signal| try abort_signal.abort(self.engine, signal, c.pi_js_undefined());
    }
    /// Owner retirement drops pending host roots even if input ignores abort.
    pub fn retire(self: *State) void {
        self.cancel() catch {};
        self.freeOptional(&self.pending);
        self.freeOptional(&self.signal);
        if (self.snapshot_text) |contents| self.engine.gpa.free(contents);
        self.snapshot_text = null;
    }
    pub fn setProvider(self: *State, provider: c.JSValue) !void {
        if (!c.JS_IsNull(provider) and !c.JS_IsUndefined(provider)) {
            if (!c.JS_IsObject(provider)) return error.InvalidAutocompleteProvider;
            inline for (.{ "getSuggestions", "applyCompletion" }) |name| {
                const method = try field(self.engine, provider, name);
                defer self.engine.freeValue(method);
                if (!c.JS_IsFunction(self.engine.context, method)) return error.InvalidAutocompleteProvider;
            }
        }
        self.retire();
        self.freeOptional(&self.provider);
        if (!c.JS_IsNull(provider) and !c.JS_IsUndefined(provider)) self.provider = c.JS_DupValue(self.engine.context, provider);
        try self.redraw();
    }
    pub fn showing(self: *const State) bool {
        return self.items != null and self.item_count > 0;
    }
    fn callback(self: *State, name: [*:0]const u8, args: []c.JSValue) !void {
        if (try components.callMethod(self.engine, self.object, name, args, true)) |value| self.engine.freeValue(value);
    }
    fn redraw(self: *State) !void {
        if (c.JS_IsObject(self.tui)) if (try components.callMethod(self.engine, self.tui, "requestRender", &.{}, true)) |value| self.engine.freeValue(value);
    }
    fn changed(self: *State) !void {
        const contents = try self.engine.checked(c.JS_NewStringLen(self.engine.context, self.editor.slice().ptr, self.editor.slice().len));
        defer self.engine.freeValue(contents);
        var args = [_]c.JSValue{contents};
        try self.callback("onChange", &args);
        try self.redraw();
    }
    fn slashContext(self: *State) bool {
        const contents = self.editor.slice()[0..@min(self.editor.cursor, self.editor.slice().len)];
        const start = if (std.mem.lastIndexOfScalar(u8, contents, '\n')) |index| index + 1 else 0;
        const before = std.mem.trimStart(u8, contents[start..], " \t");
        return std.mem.startsWith(u8, before, "/") and std.mem.indexOfAny(u8, before, " \t") == null;
    }
    pub fn request(self: *State, explicit: bool) !bool {
        if (self.provider == null) return false;
        try self.cancel();
        self.queued = true;
        self.queued_explicit = explicit;
        if (self.pending == null) try self.beginQueued();
        return true;
    }
    pub fn automatic(self: *State) !void {
        const provider = self.provider orelse return;
        const before = self.editor.slice()[0..@min(self.editor.cursor, self.editor.slice().len)];
        var start = before.len;
        while (start > 0 and !std.ascii.isWhitespace(before[start - 1])) start -= 1;
        const token = before[start..];
        if (token.len == 0) return;
        if (self.slashContext() or token[0] == '@' or token[0] == '#') {
            _ = try self.request(false);
            return;
        }
        const triggers = try field(self.engine, provider, "triggerCharacters");
        defer self.engine.freeValue(triggers);
        if (!c.JS_IsArray(triggers)) return;
        const length_value = try field(self.engine, triggers, "length");
        defer self.engine.freeValue(length_value);
        const length = try integer(self.engine, length_value, maximum_items);
        for (0..length) |index| {
            const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, triggers, @intCast(index)));
            defer self.engine.freeValue(value);
            if (!c.JS_IsString(value)) continue;
            const character = try self.engine.toString(value);
            defer self.engine.gpa.free(character);
            if (utf16Length(character) != 1 or character.len == 0 or character[0] == '/' or std.ascii.isWhitespace(character[0])) continue;
            if (std.mem.startsWith(u8, token, character)) {
                _ = try self.request(false);
                return;
            }
        }
    }
    fn beginQueued(self: *State) !void {
        if (!self.queued) return;
        const provider = self.provider orelse return;
        self.queued = false;
        self.explicit_tab = self.queued_explicit;
        self.forced = self.explicit_tab and !self.slashContext();
        const query = try position(self.engine, self.editor);
        defer self.engine.freeValue(query.lines);
        var positions = [_]c.JSValue{ query.lines, c.JS_NewInt64(self.engine.context, @intCast(query.line)), c.JS_NewInt64(self.engine.context, @intCast(query.col)) };
        defer self.engine.freeValue(positions[1]);
        defer self.engine.freeValue(positions[2]);
        if (self.forced) if (try components.callMethod(self.engine, provider, "shouldTriggerFileCompletion", &positions, true)) |value| {
            defer self.engine.freeValue(value);
            if (c.JS_ToBool(self.engine.context, value) == 0) return;
        };
        if (self.snapshot_text) |contents| self.engine.gpa.free(contents);
        self.snapshot_text = null;
        self.snapshot_text = try self.engine.gpa.dupe(u8, self.editor.slice());
        self.snapshot_cursor = self.editor.cursor;
        self.pending_generation = self.generation;
        self.freeOptional(&self.signal);
        self.signal = try abort_signal.create(self.engine);
        const options = try self.engine.checked(c.JS_NewObject(self.engine.context));
        defer self.engine.freeValue(options);
        try put(self.engine, options, "signal", c.JS_DupValue(self.engine.context, self.signal.?));
        try put(self.engine, options, "force", c.pi_js_bool(self.engine.context, @intFromBool(self.forced)));
        var args = [_]c.JSValue{ positions[0], positions[1], positions[2], options };
        const value = (try components.callMethod(self.engine, provider, "getSuggestions", &args, false)).?;
        defer self.engine.freeValue(value);
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        errdefer self.engine.freeValue(promise);
        defer self.engine.freeValue(capabilities[0]);
        defer self.engine.freeValue(capabilities[1]);
        var resolved = [_]c.JSValue{value};
        const resolution = try self.engine.checked(c.JS_Call(self.engine.context, capabilities[0], c.pi_js_undefined(), 1, &resolved));
        self.engine.freeValue(resolution);
        self.pending = promise;
        self.freeOptional(&self.last_error);
    }
    pub fn poll(self: *State) !bool {
        if (self.polling) return false;
        const promise = self.pending orelse return false;
        const status = c.JS_PromiseState(self.engine.context, promise);
        if (status == c.JS_PROMISE_PENDING) return false;
        self.polling = true;
        defer self.polling = false;
        self.pending = null;
        defer self.engine.freeValue(promise);
        const result = c.JS_PromiseResult(self.engine.context, promise);
        defer self.engine.freeValue(result);
        const current = self.pending_generation == self.generation and self.snapshot_cursor == self.editor.cursor and std.mem.eql(u8, self.snapshot_text orelse "", self.editor.slice());
        self.freeOptional(&self.signal);
        if (current) {
            if (status == c.JS_PROMISE_REJECTED) {
                self.last_error = c.JS_DupValue(self.engine.context, result);
                var args = [_]c.JSValue{result};
                try self.callback("_nativeAutocompleteError", &args);
            } else try self.accept(result);
        }
        if (self.queued) try self.beginQueued();
        try self.redraw();
        return true;
    }
    fn accept(self: *State, result: c.JSValue) !void {
        if (c.JS_IsNull(result) or c.JS_IsUndefined(result)) {
            self.clearMenu();
            if (self.explicit_tab) try self.callback("_nativeAutocomplete", &.{});
            return;
        }
        if (!c.JS_IsObject(result)) return error.InvalidAutocompleteSuggestions;
        const items = try field(self.engine, result, "items");
        defer self.engine.freeValue(items);
        if (!c.JS_IsArray(items)) return error.InvalidAutocompleteSuggestions;
        const length_value = try field(self.engine, items, "length");
        defer self.engine.freeValue(length_value);
        const length = try integer(self.engine, length_value, maximum_items);
        if (length == 0) {
            self.clearMenu();
            if (self.explicit_tab) try self.callback("_nativeAutocomplete", &.{});
            return;
        }
        const prefix = try field(self.engine, result, "prefix");
        defer self.engine.freeValue(prefix);
        if (!c.JS_IsString(prefix)) return error.InvalidAutocompletePrefix;
        for (0..length) |index| {
            const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, items, @intCast(index)));
            defer self.engine.freeValue(item);
            inline for (.{ "value", "label" }) |name| {
                const string = try field(self.engine, item, name);
                defer self.engine.freeValue(string);
                if (!c.JS_IsString(string)) return error.InvalidAutocompleteItem;
            }
        }
        self.clearMenu();
        self.items = c.JS_DupValue(self.engine.context, items);
        self.prefix = c.JS_DupValue(self.engine.context, prefix);
        self.item_count = length;
        if (self.forced and self.explicit_tab and length == 1) try self.applySelected();
    }
    fn applySelected(self: *State) !void {
        const provider = c.JS_DupValue(self.engine.context, self.provider orelse return);
        defer self.engine.freeValue(provider);
        const items = c.JS_DupValue(self.engine.context, self.items orelse return);
        defer self.engine.freeValue(items);
        const prefix = c.JS_DupValue(self.engine.context, self.prefix.?);
        defer self.engine.freeValue(prefix);
        const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, items, @intCast(self.selected)));
        defer self.engine.freeValue(item);
        const query = try position(self.engine, self.editor);
        defer self.engine.freeValue(query.lines);
        var args = [_]c.JSValue{ query.lines, c.JS_NewInt64(self.engine.context, @intCast(query.line)), c.JS_NewInt64(self.engine.context, @intCast(query.col)), item, prefix };
        defer self.engine.freeValue(args[1]);
        defer self.engine.freeValue(args[2]);
        const generation = self.generation;
        const result = (try components.callMethod(self.engine, provider, "applyCompletion", &args, false)).?;
        defer self.engine.freeValue(result);
        const lines = try field(self.engine, result, "lines");
        defer self.engine.freeValue(lines);
        if (!c.JS_IsArray(lines)) return error.InvalidAutocompleteCompletion;
        const length_value = try field(self.engine, lines, "length");
        defer self.engine.freeValue(length_value);
        const length = try integer(self.engine, length_value, maximum_items);
        const row_value = try field(self.engine, result, "cursorLine");
        defer self.engine.freeValue(row_value);
        const row = try integer(self.engine, row_value, maximum_items);
        if (row >= length) return error.InvalidAutocompleteCursor;
        const col_value = try field(self.engine, result, "cursorCol");
        defer self.engine.freeValue(col_value);
        const col = try integer(self.engine, col_value, maximum_text);
        var contents: std.ArrayList(u8) = .empty;
        defer contents.deinit(self.engine.gpa);
        var cursor: usize = 0;
        for (0..length) |index| {
            const line = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, lines, @intCast(index)));
            defer self.engine.freeValue(line);
            if (!c.JS_IsString(line)) return error.InvalidAutocompleteCompletion;
            const bytes = try self.engine.toString(line);
            defer self.engine.gpa.free(bytes);
            if (bytes.len > maximum_text - contents.items.len) return error.AutocompleteTextLimit;
            if (index == row) cursor = contents.items.len + try byteColumn(bytes, col);
            try contents.appendSlice(self.engine.gpa, bytes);
            if (index + 1 != length) try contents.append(self.engine.gpa, '\n');
        }
        if (generation != self.generation) return;
        try self.editor.replaceWithUndo(contents.items, cursor);
        try self.cancel();
        try self.changed();
    }
    pub fn input(self: *State, data: []const u8) !Disposition {
        _ = try self.poll();
        if (self.showing()) {
            if (keys.matchesKey(data, "escape")) {
                try self.cancel();
                try self.redraw();
                return .handled;
            }
            if (keys.matchesKey(data, "up") or keys.matchesKey(data, "down")) {
                self.selected = if (keys.matchesKey(data, "up")) (self.selected + self.item_count - 1) % self.item_count else (self.selected + 1) % self.item_count;
                try self.redraw();
                return .handled;
            }
            if (keys.matchesKey(data, "tab") or keys.matchesKey(data, "enter")) {
                const prefix = try self.engine.toString(self.prefix.?);
                defer self.engine.gpa.free(prefix);
                const submit = keys.matchesKey(data, "enter") and std.mem.startsWith(u8, prefix, "/");
                try self.applySelected();
                return if (submit) .submit else .handled;
            }
        }
        if (keys.matchesKey(data, "tab") and try self.request(true)) return .handled;
        return .pass;
    }
    pub fn appendRows(self: *State, array: c.JSValue, start: usize, width: usize) !void {
        if (!self.showing()) return;
        const count = @min(@max(1, self.max_visible), self.item_count);
        const begin = if (self.selected >= count) self.selected + 1 - count else 0;
        for (begin..@min(begin + count, self.item_count), 0..) |index, output_index| {
            const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, self.items.?, @intCast(index)));
            defer self.engine.freeValue(item);
            const label_value = try field(self.engine, item, "label");
            defer self.engine.freeValue(label_value);
            const label = try self.engine.toString(label_value);
            defer self.engine.gpa.free(label);
            const description_value = try field(self.engine, item, "description");
            defer self.engine.freeValue(description_value);
            const description = if (c.JS_IsString(description_value)) try self.engine.toString(description_value) else try self.engine.gpa.dupe(u8, "");
            defer self.engine.gpa.free(description);
            const line = try std.fmt.allocPrint(self.engine.gpa, "{s}{s}{s}{s}", .{ if (index == self.selected) "→ " else "  ", label, if (description.len != 0) "  " else "", description });
            defer self.engine.gpa.free(line);
            const clipped = try text.truncateAlloc(self.engine.gpa, line, width, .{ .ellipsis = "..." });
            defer self.engine.gpa.free(clipped);
            if (c.JS_SetPropertyUint32(self.engine.context, array, @intCast(start + output_index), try self.engine.checked(c.JS_NewStringLen(self.engine.context, clipped.ptr, clipped.len))) < 0) return error.JavaScriptException;
        }
    }
};
