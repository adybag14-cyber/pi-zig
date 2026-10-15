//! Actual public pi-ai streams and acknowledged provider iteration. No host JS.
const std = @import("std");
const typebox = @import("typebox.zig");
const native_models = @import("native_models.zig");
const engine_mod = @import("engine.zig");
const providers_mod = @import("native_providers.zig");
const core = @import("native_event_stream_core.zig");
const c = engine_mod.c;
pub const maximum_event_bytes = 512 * 1024;
pub const maximum_total_bytes = 16 * 1024 * 1024;
/// Native host-fatal retirement uses the actual live Source resolvers and real
/// Promise assimilation. Stream instances no longer contain the old opaque queue.
pub fn reject(engine: *engine_mod.Engine, value: c.JSValue, failure: c.JSValue) !void {
    return core.reject(engine, value, failure);
}
fn property(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn callOne(engine: *engine_mod.Engine, function: c.JSValue, value: c.JSValue) !void {
    var args = [_]c.JSValue{value};
    const result = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &args));
    engine.freeValue(result);
}
pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.event_stream_class != 0) return;
    const module = try @import("native_event_stream_assistant.zig").create(engine);
    defer engine.freeValue(module);
    const async_symbol = try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context));
    defer engine.freeValue(async_symbol);
    const async_atom = c.JS_ValueToAtom(engine.context, async_symbol);
    if (async_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    errdefer c.JS_FreeAtom(engine.context, async_atom);
    try typebox.install(engine);
    const schema_exports = c.JS_DupValue(engine.context, engine.native_module_values.get("typebox").?);
    defer engine.freeValue(schema_exports);
    try property(engine, module, "Type", try engine.checked(c.JS_GetPropertyStr(engine.context, schema_exports, "Type")));
    try native_models.populateExports(engine, module);
    try @import("native_tool_arguments.zig").install(engine, module);
    try engine.registerValueModule("@earendil-works/pi-ai", module);
    try engine.registerValueModule("@mariozechner/pi-ai", module);
    try engine.registerValueModule("pi-ai", module);
    // Keep the existing installation sentinel without applying its old opaque
    // class to public ordinary-field stream instances or actual generators.
    var installed: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &installed);
    const definition: c.JSClassDef = .{ .class_name = "Native EventStream Installation" };
    if (c.JS_NewClass(engine.runtime, installed, &definition) < 0) return error.OutOfMemory;
    engine.event_stream_async_atom = async_atom;
    engine.event_stream_class = installed;
}
const BlockKind = enum { text, thinking, toolcall };
const Block = struct { kind: BlockKind, bytes: std.ArrayList(u8) = .empty, high: ?u16 = null, saw_delta: bool = false };
const Validator = struct {
    engine: *engine_mod.Engine,
    started: bool = false,
    terminal: ?enum { done, err } = null,
    reason: []u8 = &.{},
    blocks: std.AutoHashMapUnmanaged(u64, Block) = .empty,
    total_bytes: usize = 0,

    fn deinit(self: *@This()) void {
        var blocks = self.blocks.valueIterator();
        while (blocks.next()) |block| block.bytes.deinit(self.engine.gpa);
        self.blocks.deinit(self.engine.gpa);
        if (self.reason.len > 0) self.engine.gpa.free(self.reason);
    }

    fn text(self: *@This(), object: c.JSValue, key: [*:0]const u8) ![]u8 {
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, object, key));
        defer self.engine.freeValue(value);
        if (!c.JS_IsString(value)) return error.InvalidNativeProviderEvent;
        return self.engine.toString(value);
    }

    fn assistant(self: *@This(), value: c.JSValue) !void {
        if (!c.JS_IsObject(value) or c.JS_IsArray(value)) return error.InvalidNativeAssistantMessage;
        const role = try self.text(value, "role");
        defer self.engine.gpa.free(role);
        if (!std.mem.eql(u8, role, "assistant")) return error.InvalidNativeAssistantMessage;
        const content = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "content"));
        defer self.engine.freeValue(content);
        if (!c.JS_IsArray(content)) return error.InvalidNativeAssistantMessage;
    }

    fn index(self: *@This(), value: c.JSValue) !u64 {
        const field = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "contentIndex"));
        defer self.engine.freeValue(field);
        if (!c.JS_IsNumber(field)) return error.InvalidNativeProviderContentIndex;
        var number: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &number, field) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number) or number < 0 or number > 9_007_199_254_740_991 or number != @trunc(number)) return error.InvalidNativeProviderContentIndex;
        return @intFromFloat(number);
    }

    fn appendFragment(self: *@This(), block: *Block, source: []const u8) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.engine.gpa);
        var iterator = (try std.unicode.Wtf8View.init(source)).iterator();
        var buffer: [4]u8 = undefined;
        while (iterator.nextCodepoint()) |point| {
            if (block.high) |high| {
                if (point < 0xdc00 or point > 0xdfff) return error.InvalidNativeProviderUnicode;
                const scalar: u21 = 0x10000 + (@as(u21, high - 0xd800) << 10) + point - 0xdc00;
                const length = try std.unicode.utf8Encode(scalar, &buffer);
                try output.appendSlice(self.engine.gpa, buffer[0..length]);
                block.high = null;
            } else if (point >= 0xd800 and point <= 0xdbff) {
                block.high = @intCast(point);
            } else if (point >= 0xdc00 and point <= 0xdfff) return error.InvalidNativeProviderUnicode else {
                const length = try std.unicode.utf8Encode(point, &buffer);
                try output.appendSlice(self.engine.gpa, buffer[0..length]);
            }
        }
        try block.bytes.appendSlice(self.engine.gpa, output.items);
        return output.toOwnedSlice(self.engine.gpa);
    }

    fn normalize(self: *@This(), raw: c.JSValue) ![]u8 {
        const encoded = try self.engine.stringify(raw);
        defer self.engine.gpa.free(encoded);
        const terminated = try self.engine.gpa.dupeZ(u8, encoded);
        defer self.engine.gpa.free(terminated);
        const event = try self.engine.checked(c.JS_ParseJSON(self.engine.context, terminated.ptr, encoded.len, "native-provider-event"));
        defer self.engine.freeValue(event);
        if (!c.JS_IsObject(event) or c.JS_IsArray(event)) return error.InvalidNativeProviderEvent;
        const kind = try self.text(event, "type");
        defer self.engine.gpa.free(kind);
        if (self.terminal != null) return error.NativeProviderEventAfterTerminal;
        if (std.mem.eql(u8, kind, "start")) {
            if (self.started) return error.DuplicateNativeProviderStart;
            const partial = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "partial"));
            defer self.engine.freeValue(partial);
            try self.assistant(partial);
            self.started = true;
        } else {
            if (!self.started) return error.NativeProviderEventBeforeStart;
            const terminal = std.mem.eql(u8, kind, "done") or std.mem.eql(u8, kind, "error");
            if (terminal) {
                if (self.blocks.count() != 0) return error.NativeProviderUnclosedContent;
                const reason = try self.text(event, "reason");
                errdefer self.engine.gpa.free(reason);
                const success = std.mem.eql(u8, kind, "done");
                const allowed = if (success) std.mem.eql(u8, reason, "stop") or std.mem.eql(u8, reason, "length") or std.mem.eql(u8, reason, "toolUse") or std.mem.eql(u8, reason, "deferred") else std.mem.eql(u8, reason, "error") or std.mem.eql(u8, reason, "aborted");
                if (!allowed) return error.InvalidNativeProviderTerminalReason;
                const message = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, if (success) "message" else "error"));
                defer self.engine.freeValue(message);
                try self.assistant(message);
                self.terminal = if (success) .done else .err;
                self.reason = reason;
            } else {
                const partial = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "partial"));
                defer self.engine.freeValue(partial);
                try self.assistant(partial);
                const block_kind: BlockKind = if (std.mem.eql(u8, kind, "text_start") or std.mem.eql(u8, kind, "text_delta") or std.mem.eql(u8, kind, "text_end")) .text else if (std.mem.eql(u8, kind, "thinking_start") or std.mem.eql(u8, kind, "thinking_delta") or std.mem.eql(u8, kind, "thinking_end")) .thinking else if (std.mem.eql(u8, kind, "toolcall_start") or std.mem.eql(u8, kind, "toolcall_delta") or std.mem.eql(u8, kind, "toolcall_end")) .toolcall else return error.InvalidNativeProviderEvent;
                const key = try self.index(event);
                if (std.mem.endsWith(u8, kind, "_start")) {
                    if (self.blocks.contains(key)) return error.DuplicateNativeProviderContent;
                    if (self.blocks.count() >= 4096) return error.NativeProviderContentLimit;
                    try self.blocks.put(self.engine.gpa, key, .{ .kind = block_kind });
                } else {
                    const block = self.blocks.getPtr(key) orelse return error.NativeProviderContentNotStarted;
                    if (block.kind != block_kind) return error.NativeProviderContentKindMismatch;
                    if (std.mem.endsWith(u8, kind, "_delta")) {
                        const delta = try self.text(event, "delta");
                        defer self.engine.gpa.free(delta);
                        const normalized = try self.appendFragment(block, delta);
                        defer self.engine.gpa.free(normalized);
                        block.saw_delta = true;
                        try property(self.engine, event, "delta", try self.engine.checked(c.JS_NewStringLen(self.engine.context, normalized.ptr, normalized.len)));
                    } else if (std.mem.endsWith(u8, kind, "_end")) {
                        if (block.high != null) return error.InvalidNativeProviderUnicode;
                        if (block_kind != .toolcall) {
                            const content = try self.text(event, "content");
                            defer self.engine.gpa.free(content);
                            if (block.saw_delta and !std.mem.eql(u8, content, block.bytes.items)) return error.NativeProviderContentMismatch;
                        } else {
                            const call = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "toolCall"));
                            defer self.engine.freeValue(call);
                            if (!c.JS_IsObject(call) or c.JS_IsArray(call)) return error.InvalidNativeProviderToolCall;
                            const call_type = try self.text(call, "type");
                            defer self.engine.gpa.free(call_type);
                            const id = try self.text(call, "id");
                            defer self.engine.gpa.free(id);
                            const name = try self.text(call, "name");
                            defer self.engine.gpa.free(name);
                            if (!std.mem.eql(u8, call_type, "toolCall") or id.len == 0 or name.len == 0) return error.InvalidNativeProviderToolCall;
                            const arguments = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, call, "arguments"));
                            defer self.engine.freeValue(arguments);
                            if (!c.JS_IsObject(arguments) or c.JS_IsArray(arguments)) return error.InvalidNativeProviderToolCall;
                            if (block.saw_delta) {
                                var expected = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, block.bytes.items, .{});
                                defer expected.deinit();
                                const source = try self.engine.stringify(arguments);
                                defer self.engine.gpa.free(source);
                                var actual = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, source, .{});
                                defer actual.deinit();
                                if (!jsonEqual(expected.value, actual.value)) return error.NativeProviderToolArgumentsMismatch;
                            }
                        }
                        var removed = self.blocks.fetchRemove(key).?.value;
                        removed.bytes.deinit(self.engine.gpa);
                    } else return error.InvalidNativeProviderEvent;
                }
            }
        }
        const result = try self.engine.stringify(event);
        errdefer self.engine.gpa.free(result);
        if (result.len > maximum_event_bytes or result.len > maximum_total_bytes - self.total_bytes) return error.NativeProviderStreamSizeLimit;
        self.total_bytes += result.len;
        return result;
    }
};

fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    if ((a == .integer or a == .float) and (b == .integer or b == .float)) {
        // JSON parsed by the extension follows ECMAScript Number semantics,
        // including equivalent 1/1.0 spellings and integer rounding above 2^53.
        const left: f64 = if (a == .integer) @floatFromInt(a.integer) else a.float;
        const right: f64 = if (b == .integer) @floatFromInt(b.integer) else b.float;
        return left == right;
    }
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => a.bool == b.bool,
        .integer => a.integer == b.integer,
        .float => a.float == b.float,
        .number_string, .string => std.mem.eql(u8, if (a == .string) a.string else a.number_string, if (b == .string) b.string else b.number_string),
        .array => blk: {
            if (a.array.items.len != b.array.items.len) break :blk false;
            for (a.array.items, b.array.items) |left, right| if (!jsonEqual(left, right)) break :blk false;
            break :blk true;
        },
        .object => blk: {
            if (a.object.count() != b.object.count()) break :blk false;
            var entries = a.object.iterator();
            while (entries.next()) |entry| if (!jsonEqual(entry.value_ptr.*, b.object.get(entry.key_ptr.*) orelse break :blk false)) break :blk false;
            break :blk true;
        },
    };
}

pub const Bridge = struct { context: ?*anyopaque, event: *const fn (?*anyopaque, u64, []const u8) anyerror!void };

pub fn freezeJson(engine: *engine_mod.Engine, value: c.JSValue, depth: usize) !void {
    if (!c.JS_IsObject(value)) return;
    if (depth > 256) return error.NativeProviderInputDepth;
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, value, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (properties[0..count]) |field| {
        const child = try engine.checked(c.JS_GetProperty(engine.context, value, field.atom));
        defer engine.freeValue(child);
        // Only the actual invocation signal is excluded; JSON input may not
        // carry runtime objects. Its mutable native abort state stays live.
        if (c.JS_GetOpaque(child, engine.abort_signal_class) == null) try freezeJson(engine, child, depth + 1);
        if (c.JS_DefineProperty(engine.context, value, field.atom, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
    if (c.JS_PreventExtensions(engine.context, value) < 0) return error.JavaScriptException;
}

pub const Runner = struct {
    engine: *engine_mod.Engine,
    active: bool = false,
    cleaning: bool = false,
    providers: ?*providers_mod.Providers = null,
    provider: []const u8 = "",
    callback: []const u8 = "",
    generation: u64 = 0,
    signal: ?c.JSValue = null,
    ack: ?struct { sequence: u64, resolve: c.JSValue, reject: c.JSValue } = null,

    pub fn poll(self: *Runner) !void {
        if (!self.active or self.cleaning) return;
        const aborted = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, self.signal.?, "aborted"));
        defer self.engine.freeValue(aborted);
        if (c.JS_ToBool(self.engine.context, aborted) != 0) {
            const reason = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, self.signal.?, "reason"));
            defer self.engine.freeValue(reason);
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason)));
            return error.JavaScriptException;
        }
        if (!self.providers.?.live(self.callback, self.provider, self.generation)) return error.NativeProviderStreamRetired;
    }

    pub fn acknowledge(self: *Runner, sequence: u64, ok: bool, accepted: bool, message: c.JSValue) !void {
        const pending = self.ack orelse return;
        if (sequence != pending.sequence) return;
        self.ack = null;
        defer self.engine.freeValue(pending.resolve);
        defer self.engine.freeValue(pending.reject);
        if (ok and accepted) try callOne(self.engine, pending.resolve, c.pi_js_bool(self.engine.context, 1)) else {
            const failure = try self.engine.checked(c.JS_NewError(self.engine.context));
            defer self.engine.freeValue(failure);
            try property(self.engine, failure, "message", c.JS_DupValue(self.engine.context, message));
            try callOne(self.engine, pending.reject, failure);
        }
    }

    fn clearAck(self: *Runner) void {
        if (self.ack) |pending| {
            self.engine.freeValue(pending.resolve);
            self.engine.freeValue(pending.reject);
        }
        self.ack = null;
    }

    fn awaitAck(self: *Runner, bridge: Bridge, sequence: u64, event: []const u8) !void {
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        defer self.engine.freeValue(promise);
        self.ack = .{ .sequence = sequence, .resolve = capabilities[0], .reject = capabilities[1] };
        defer self.clearAck();
        try bridge.event(bridge.context, sequence, event);
        const result = try self.engine.awaitValue(promise);
        self.engine.freeValue(result);
    }

    fn retire(self: *Runner, iterator: c.JSValue) bool {
        self.cleaning = true;
        defer self.cleaning = false;
        const previous = self.engine.options.host_await_timeout_ms;
        self.engine.options.host_await_timeout_ms = 250;
        defer self.engine.options.host_await_timeout_ms = previous;
        const function = self.engine.checked(c.JS_GetPropertyStr(self.engine.context, iterator, "return")) catch return true;
        defer self.engine.freeValue(function);
        if (!c.JS_IsFunction(self.engine.context, function)) return true;
        const pending = self.engine.checked(c.JS_Call(self.engine.context, function, iterator, 0, null)) catch return true;
        defer self.engine.freeValue(pending);
        const result = self.engine.awaitValue(pending) catch |err| return err != error.NativeHostPromiseTimeout;
        self.engine.freeValue(result);
        return true;
    }

    pub fn consume(self: *Runner, providers: *providers_mod.Providers, callback: []const u8, provider: []const u8, generation: u64, args: c.JSValue, signal: c.JSValue, bridge: Bridge, invocation_id: []const u8, cancel_only: bool) !c.JSValue {
        if (self.active) return error.NativeProviderStreamBusy;
        try providers.validate(callback, provider, generation);
        self.active = true;
        self.providers = providers;
        self.callback = callback;
        self.provider = provider;
        self.generation = generation;
        self.signal = signal;
        defer {
            self.clearAck();
            self.active = false;
            self.signal = null;
            self.providers = null;
        }
        const previous_timeout = self.engine.options.host_await_timeout_ms;
        self.engine.options.host_await_timeout_ms = 0;
        defer self.engine.options.host_await_timeout_ms = previous_timeout;
        const returned = try providers.invokeUnsettled(callback, args);
        defer self.engine.freeValue(returned);
        const stream = try self.engine.awaitValue(returned);
        defer self.engine.freeValue(stream);
        if (cancel_only) return self.engine.checked(c.JS_NewObject(self.engine.context));
        const get_iterator = try self.engine.checked(c.JS_GetProperty(self.engine.context, stream, self.engine.event_stream_async_atom));
        defer self.engine.freeValue(get_iterator);
        if (!c.JS_IsFunction(self.engine.context, get_iterator)) return error.NativeProviderStreamNotAsyncIterable;
        const iterator = try self.engine.checked(c.JS_Call(self.engine.context, get_iterator, stream, 0, null));
        defer self.engine.freeValue(iterator);
        var validator: Validator = .{ .engine = self.engine };
        defer validator.deinit();
        var sequence: u64 = 0;
        self.iterate(iterator, bridge, &validator, &sequence) catch |err| {
            var original: ?c.JSValue = null;
            if (err == error.JavaScriptException) {
                if (self.engine.captured_exception) |value| original = c.JS_DupValue(self.engine.context, value);
            }
            defer if (original) |value| self.engine.freeValue(value);
            if (!self.retire(iterator)) {
                const failure = try self.engine.checked(c.JS_NewError(self.engine.context));
                defer self.engine.freeValue(failure);
                const text = if (original) |value| self.engine.toString(value) catch null else null;
                defer if (text) |value| self.engine.gpa.free(value);
                const message = try std.fmt.allocPrint(self.engine.gpa, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT: {s}", .{text orelse "native iterator did not settle return()"});
                defer self.engine.gpa.free(message);
                try property(self.engine, failure, "message", try self.engine.checked(c.JS_NewStringLen(self.engine.context, message.ptr, message.len)));
                if (original) |value| try property(self.engine, failure, "cause", c.JS_DupValue(self.engine.context, value));
                _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, failure))) catch {};
                return error.JavaScriptException;
            }
            if (original) |value| _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, value))) catch {};
            return err;
        };
        if (validator.terminal == null) return error.NativeProviderStreamMissingTerminal;
        const summary = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(summary);
        try property(self.engine, summary, "invocationId", try self.engine.fromJsonValue(.{ .string = invocation_id }));
        try property(self.engine, summary, "events", c.JS_NewInt64(self.engine.context, @intCast(sequence)));
        try property(self.engine, summary, "terminal", c.JS_NewString(self.engine.context, if (validator.terminal.? == .done) "done" else "error"));
        try property(self.engine, summary, "reason", try self.engine.fromJsonValue(.{ .string = validator.reason }));
        try property(self.engine, summary, "bytes", c.JS_NewInt64(self.engine.context, @intCast(validator.total_bytes)));
        return summary;
    }

    fn iterate(self: *Runner, iterator: c.JSValue, bridge: Bridge, validator: *Validator, sequence: *u64) !void {
        while (true) {
            try self.poll();
            const next = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, iterator, "next"));
            defer self.engine.freeValue(next);
            const pending = try self.engine.checked(c.JS_Call(self.engine.context, next, iterator, 0, null));
            defer self.engine.freeValue(pending);
            const step = try self.engine.awaitValue(pending);
            defer self.engine.freeValue(step);
            try self.poll();
            if (!c.JS_IsObject(step)) return error.InvalidNativeProviderIteratorResult;
            const done = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, step, "done"));
            defer self.engine.freeValue(done);
            if (c.JS_ToBool(self.engine.context, done) != 0) return;
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, step, "value"));
            defer self.engine.freeValue(value);
            const event = try validator.normalize(value);
            defer self.engine.gpa.free(event);
            sequence.* = std.math.add(u64, sequence.*, 1) catch return error.NativeProviderSequenceExhausted;
            try self.awaitAck(bridge, sequence.*, event);
        }
    }
};

test "native pi-ai EventStream exports preserve queue terminal result receiver and iterator cleanup" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule(
        "import {EventStream,AssistantMessageEventStream,createAssistantMessageEventStream} from '@earendil-works/pi-ai';import {EventStream as alias} from '@mariozechner/pi-ai';if(alias!==EventStream)throw Error('alias');const s=new EventStream(function(e){if(this!==s)throw Error('predicate receiver');return e.final},function(e){if(this!==s)throw Error('extract receiver');return e.value});s.push({value:1});s.push({final:true,value:2});s.push({value:3});let values=[];for await(const item of s)values.push(item.value);if(values.join(',')!=='1,2'||await s.result()!==2)throw Error('generic stream');const a=createAssistantMessageEventStream();if(!(a instanceof EventStream)||!(a instanceof AssistantMessageEventStream))throw Error('stream brand');const message={role:'assistant',content:[]};a.push({type:'done',message});if(await a.result()!==message)throw Error('result identity');const iterator=a[Symbol.asyncIterator]();if((await iterator.next()).value.message!==message||!(await iterator.next()).done)throw Error('terminal iteration');const open=new EventStream(()=>false,x=>x),waiting=open[Symbol.asyncIterator](),pending=waiting.next(),returned=waiting.return();open.end(7);if(!(await pending).done||!(await returned).done||await open.result()!==7)throw Error('Source pending return queues behind next');",
        "native-event-stream.mjs",
    );
    defer engine.freeValue(module);
}

fn streamAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    install(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const module = engine.evalModule("import {AssistantMessageEventStream} from 'pi-ai';const stream=new AssistantMessageEventStream(),message={role:'assistant',content:[],timestamp:5000000000000},iterator=stream[Symbol.asyncIterator](),pending=iterator.next();stream.push({type:'start',partial:message});if((await pending).value.partial!==message)throw Error('waiter identity');const waiting=iterator.next();stream.end(message);if(!(await waiting).done||await stream.result()!==message)throw Error('retirement');export const done=true;", "native-stream-allocation-public.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}
test "native EventStream allocation failures release queued values pending capabilities and iterator cycles" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, streamAllocationProbe, .{});
}
test "native terminal admission host-fatal rejection retains original result and pending iterator" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule("import {AssistantMessageEventStream} from 'pi-ai';globalThis.fatalReason={};globalThis.fatalStream=new AssistantMessageEventStream();globalThis.fatalResult=fatalStream.result().catch(error=>error);globalThis.fatalNext=fatalStream[Symbol.asyncIterator]().next().catch(error=>error);export const done=true;", "native-stream-fatal-prepare.mjs");
    engine.freeValue(prepared);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const stream = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "fatalStream"));
    defer engine.freeValue(stream);
    const reason = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "fatalReason"));
    defer engine.freeValue(reason);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    engine.gpa = failing.allocator();
    const retired = reject(engine, stream, reason);
    engine.gpa = std.testing.allocator;
    try retired;
    const checked = try engine.evalModule("if(await fatalResult!==fatalReason||await fatalNext!==fatalReason)throw Error('fatal raw identity');if(!fatalStream.done)throw Error('fatal closure');delete globalThis.fatalStream;delete globalThis.fatalResult;delete globalThis.fatalNext;delete globalThis.fatalReason;export const done=true;", "native-stream-fatal-check.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native AssistantMessageEventStream genuine Source result-only producer retains more than64 events" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule("import {AssistantMessageEventStream} from 'pi-ai';const stream=new AssistantMessageEventStream(),message={role:'assistant',content:[],timestamp:5000000000000};const result=stream.result();for(let i=0;i<128;i++)stream.push({type:'text_delta',delta:String(i),partial:message});stream.push({type:'done',message});if(await result!==message||stream.queue.length!==129)throw Error('Source result-only queue');let count=0;for await(const event of stream){if((event.partial??event.message)!==message)throw Error('shared identity');count++}if(count!==129||stream.queue.length!==0)throw Error('complete Source drain');export const done=true;", "native-stream-long-source27.mjs");
    engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}
test "native provider validation accepts only exact event names numeric indices and JavaScript JSON number equality" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var validator: Validator = .{ .engine = engine, .started = true };
    defer validator.deinit();
    for ([_][]const u8{
        "{\"type\":\"text_extra_start\",\"contentIndex\":0,\"partial\":{\"role\":\"assistant\",\"content\":[]}}",
        "{\"type\":\"text_start\",\"contentIndex\":\"0\",\"partial\":{\"role\":\"assistant\",\"content\":[]}}",
    }, 0..) |source, index_value| {
        const event = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "event-validation"));
        defer engine.freeValue(event);
        try std.testing.expectError(if (index_value == 0) error.InvalidNativeProviderEvent else error.InvalidNativeProviderContentIndex, validator.normalize(event));
    }
    var left = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"one\":1.0,\"large\":9007199254740993}", .{});
    defer left.deinit();
    var right = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"large\":9007199254740992,\"one\":1}", .{});
    defer right.deinit();
    try std.testing.expect(jsonEqual(left.value, right.value));
}

test "native provider cancellation retains supplied reason identity through throwing and hostile iterator cleanup" {
    const abort_signal = @import("abort_signal.zig");
    const Control = struct {
        fn pump(_: *engine_mod.Engine) !bool {
            return false;
        }
        fn event(_: ?*anyopaque, _: u64, _: []const u8) !void {
            return error.UnexpectedCancelledStreamEvent;
        }
    };
    for ([_]bool{ false, true }) |hostile| {
        const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        engine.native_io = std.testing.io;
        engine.host_control_pump = Control.pump;
        try abort_signal.install(engine);
        try install(engine);
        var providers = providers_mod.Providers.init(engine);
        defer providers.deinit();
        const source = if (hostile)
            "export const original={supplied:'cancelled-by-native-185'};export const config={callback(){return {[Symbol.asyncIterator](){return this},next(){return new Promise(()=>{})},return(){return new Promise(()=>{})}}}}"
        else
            "export const original={supplied:'cancelled-by-native-185'};export const config={callback(){return {[Symbol.asyncIterator](){return this},next(){return new Promise(()=>{})},return(){throw Error('secondary-cleanup-must-not-replace')}}}}";
        const module = try engine.evalModule(source, "native-stream-cancel-reason.mjs");
        defer engine.freeValue(module);
        const original = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "original"));
        defer engine.freeValue(original);
        const config = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "config"));
        defer engine.freeValue(config);
        const encoded = try providers.register("owned", config, false);
        defer engine.freeValue(encoded);
        const descriptor = try engine.checked(c.JS_GetPropertyStr(engine.context, encoded, "callback"));
        defer engine.freeValue(descriptor);
        const id_value = try engine.checked(c.JS_GetPropertyStr(engine.context, descriptor, "__pi_callback_id"));
        defer engine.freeValue(id_value);
        const id = try engine.toString(id_value);
        defer engine.gpa.free(id);
        const arguments = try engine.checked(c.JS_NewArray(engine.context));
        defer engine.freeValue(arguments);
        const signal = try abort_signal.create(engine);
        defer engine.freeValue(signal);
        try abort_signal.abort(engine, signal, original);
        var runner: Runner = .{ .engine = engine };
        try std.testing.expectError(error.JavaScriptException, runner.consume(&providers, id, "owned", 1, arguments, signal, .{ .context = null, .event = Control.event }, "1", false));
        if (hostile) {
            const failure = engine.captured_exception.?;
            const cause = try engine.checked(c.JS_GetPropertyStr(engine.context, failure, "cause"));
            defer engine.freeValue(cause);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, cause));
            try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT") != null);
        } else try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
        try std.testing.expect(!runner.active and !runner.cleaning);
    }
}
