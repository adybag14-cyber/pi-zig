//! Source link classes: shared close/receive lifecycle and actual memory, IPC and structural WebSocket transports.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { closed, send, receive, on_close, close, deliver, deliver_later, ended, sever, memory_transmit, memory_shutdown, ipc_transmit, ipc_shutdown, socket_transmit, socket_shutdown, pair, ipc, socket };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn state(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const id = c.JS_GetClassID(receiver);
    inline for (.{ h.Kind.BaseLink, h.Kind.MemoryLink, h.Kind.IpcLink, h.Kind.WebSocketLink }) |kind| {
        if (id == try h.identifier(s, bindings, kind)) return (try h.actor(s, receiver, bindings, kind)).data;
    }
    return (try h.actor(s, receiver, bindings, .BaseLink)).data;
}
fn notifyClosed(s: *Scope, data: c.JSValue, reason: c.JSValue) !void {
    const handlers = try s.get(data, "closeHandlers");
    var iterator = try js.Iterator.init(s.engine, handlers, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |handler| {
        defer s.engine.freeValue(handler);
        _ = try s.keep(try js.call(s.engine, handler, c.pi_js_undefined(), &.{reason}));
    }
    _ = try h.invoke(s, handlers, "clear", &.{});
}
fn ended(s: *Scope, receiver: c.JSValue, data: c.JSValue, reason: c.JSValue) !c.JSValue {
    if (try h.flag(s, data, "closed")) return c.pi_js_undefined();
    try h.field(s, data, "closed", c.pi_js_bool(s.engine.context, 1));
    try h.field(s, data, "queue", try s.list());
    const shutdown = js.invoke(s.engine, receiver, "shutdown", &.{}) catch |err| {
        if (err != error.JavaScriptException) return err;
        const original = try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception orelse return err));
        try notifyClosed(s, data, reason);
        return h.throwValue(s, original);
    };
    s.engine.freeValue(shutdown);
    try notifyClosed(s, data, reason);
    return c.pi_js_undefined();
}
fn parse(s: *Scope, bindings: c.JSValue, text: c.JSValue) !c.JSValue {
    const frame = try @import("native_chord_packing.zig").unpackObject(s, bindings, try s.builtin("JSON", "parse", &.{text}));
    if (!c.JS_IsObject(frame) or c.JS_IsFunction(s.engine.context, frame) or !c.JS_IsString(try s.get(frame, "t"))) return h.typeError(s, &.{try s.text("not a frame")});
    return frame;
}
fn memoryDelivery(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return memoryDelivered(engine, magic, captures) catch |err| {
        if (err == error.OutOfMemory) {
            const thrown = engine.throwNativeOutOfMemory();
            // This private delivery promise has no application waiter. A real
            // native OOM must reach its owned host boundary instead of stranding
            // every later FIFO frame behind an unobserved rejection.
            if (engine.native_allocation_exception) |value| c.JS_SetUncatchableError(engine.context, value);
            return thrown;
        }
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) {
            if (engine.captured_exception) |value| c.JS_SetUncatchableError(engine.context, value);
            return engine.throwCaptured();
        }
        return @import("native_durable.zig").reject(engine, err);
    };
}
fn memoryDelivered(engine: *h.Engine, magic: c_int, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const peer = captures[1];
    if (magic == 1) return if (h.nullish(peer)) c.pi_js_undefined() else js.invoke(engine, peer, "ended", &.{try s.text("peer closed")});
    const data = (try h.actor(&s, captures[0], captures[3], .MemoryLink)).data;
    if (!try h.flag(&s, data, "severed") and !c.JS_IsUndefined(peer)) {
        const deliver = try s.get(peer, "deliver");
        const frame = try parse(&s, captures[3], captures[2]);
        _ = try s.keep(try js.call(engine, deliver, peer, &.{frame}));
    }
    return c.pi_js_undefined();
}
fn ipcEvent(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return ipcReceived(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, captures[0], captures[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn ipcReceived(engine: *h.Engine, message: c.JSValue, magic: c_int, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (magic == 1) return js.invoke(engine, receiver, "ended", &.{try s.text("ipc disconnected")});
    if (magic == 2) {
        if (c.JS_IsNull(message)) return c.pi_js_undefined();
        const code = try s.get(message, "code");
        const reason = try @import("native_chord_reload_values.zig").concat(&s, &.{ try s.text("ipc send failed: "), if (h.nullish(code)) try s.get(message, "message") else code });
        return js.invoke(engine, receiver, "ended", &.{reason});
    }
    const frame = if (h.nullish(message)) c.pi_js_undefined() else try s.get(message, "chord2");
    if (!c.JS_IsUndefined(frame)) {
        ipcDeliver(&s, bindings, receiver, frame) catch |err| {
            if (err != error.JavaScriptException) return err;
            _ = try h.invoke(&s, receiver, "close", &.{try s.text("protocol error")});
        };
    }
    return c.pi_js_undefined();
}
fn ipcDeliver(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue) !void {
    _ = try h.invoke(s, receiver, "deliver", &.{try @import("native_chord_packing.zig").unpackObject(s, bindings, frame)});
}
fn socketEvent(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return socketReceived(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, captures[0], captures[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn socketMessage(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, event: c.JSValue) !c.JSValue {
    const data = try s.get(event, "data");
    if (c.JS_IsString(data)) {
        _ = try h.invoke(s, receiver, "deliver", &.{try parse(s, bindings, data)});
        return c.pi_js_undefined();
    }
    const owned = try state(s, receiver, bindings);
    if (!try h.flag(s, owned, "acceptPacked")) return h.typeError(s, &.{try s.text("packed frames are not accepted")});
    if (!c.JS_IsArrayBuffer(data) and c.JS_GetTypedArrayType(data) < 0 and !c.JS_IsDataView(data)) return h.typeError(s, &.{try s.text("unknown message type")});
    const split = try @import("native_chord_packing.zig").splitMessage(s, data);
    const frame = try s.record();
    try js.spreadInto(s.engine, frame, try s.get(split, "envelope"));
    try js.setKey(s.engine, frame, try s.get(split, "field"), try h.construct(s, bindings, "Packed", &.{try s.get(split, "bytes")}));
    _ = try h.invoke(s, receiver, "deliver", &.{frame});
    return c.pi_js_undefined();
}
fn socketReceived(engine: *h.Engine, event: c.JSValue, magic: c_int, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (magic == 2) return js.invoke(engine, receiver, "ended", &.{try s.text("socket closed")});
    if (magic == 1) return socketMessage(&s, bindings, receiver, event) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try h.invoke(&s, receiver, "close", &.{try s.text("protocol error")});
        return c.pi_js_undefined();
    };
    const data = (try h.actor(&s, receiver, bindings, .WebSocketLink)).data;
    const socket = try s.get(data, "socket");
    const outbox = try h.invoke(&s, try s.get(data, "outbox"), "splice", &.{c.JS_NewInt32(engine.context, 0)});
    var iterator = try js.Iterator.init(engine, outbox, try h.iteratorSymbol(&s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |text| {
        defer engine.freeValue(text);
        _ = try h.invoke(&s, socket, "send", &.{text});
    }
    return c.pi_js_undefined();
}
fn deliverNow(s: *Scope, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue) !void {
    if (try h.flag(s, data, "closed")) return;
    if (try s.equal(try s.get(frame, "t"), "bye")) {
        const reason = try s.get(frame, "reason");
        _ = try h.invoke(s, receiver, "ended", &.{if (h.nullish(reason)) try s.text("peer closed") else reason});
        return;
    }
    const handler = try s.get(data, "handler");
    if (c.JS_IsUndefined(handler)) {
        try js.push(s.engine, try s.get(data, "queue"), frame);
    } else _ = try s.keep(try js.call(s.engine, handler, receiver, &.{frame}));
}
fn decoded(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return decodeStep(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn decodeStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 0) return js.get(engine, work, "frame");
    const receiver = try s.get(work, "receiver");
    const data = try s.get(work, "data");
    if (mode == 1) {
        try deliverNow(&s, receiver, data, value);
    } else if (mode == 2) {
        _ = try h.invoke(&s, receiver, "close", &.{try s.text("protocol error")});
    } else if (c.JS_IsStrictEqual(engine.context, try s.get(data, "decoding"), try s.get(work, "next"))) try h.field(&s, data, "decoding", c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn deliverLater(s: *Scope, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue) !void {
    const work = try s.record();
    inline for (.{ "receiver", "data", "frame" }, .{ receiver, data, frame }) |name, value| try h.field(s, work, name, value);
    var captures = [_]c.JSValue{work};
    const callbacks = try s.list();
    inline for (0..4) |mode| try js.push(s.engine, callbacks, try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, decoded, "", if (mode == 1) 1 else 0, @intCast(mode), 1, &captures))));
    const previous = try s.get(data, "decoding");
    const ready = if (h.nullish(previous)) try h.invoke(s, try s.keep(try js.global(s.engine, "Promise")), "resolve", &.{}) else previous;
    const selected = try h.invoke(s, ready, "then", &.{try s.at(callbacks, 0)});
    const dispatched = try h.invoke(s, selected, "then", &.{ try s.at(callbacks, 1), try s.at(callbacks, 2) });
    const next = try h.invoke(s, dispatched, "finally", &.{try s.at(callbacks, 3)});
    try h.field(s, work, "next", next);
    try h.field(s, data, "decoding", next);
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .pair) {
        const first = try h.construct(&s, bindings, "MemoryLink", &.{});
        const second = try h.construct(&s, bindings, "MemoryLink", &.{});
        try js.setKey(engine, first, try s.text("peer"), second);
        try js.setKey(engine, second, try s.text("peer"), first);
        const result = try s.list();
        try js.push(engine, result, first);
        try js.push(engine, result, second);
        return s.result(result);
    }
    if (method == .ipc or method == .socket) return s.result(try h.construct(&s, bindings, if (method == .ipc) "IpcLink" else "WebSocketLink", &.{ h.arg(args, 0), h.arg(args, 1) }));
    const data = try state(&s, receiver, bindings);
    if (method == .closed) return js.get(engine, data, "closed");
    if (method == .send) {
        return if (try h.flag(&s, data, "closed")) c.pi_js_undefined() else js.invoke(engine, receiver, "transmit", &.{h.arg(args, 0)});
    }
    if (method == .on_close) {
        if (try h.flag(&s, data, "closed")) _ = try s.keep(try js.call(engine, h.arg(args, 0), c.pi_js_undefined(), &.{try s.text("closed")})) else _ = try h.invoke(&s, try s.get(data, "closeHandlers"), "add", &.{h.arg(args, 0)});
        return c.pi_js_undefined();
    }
    if (method == .receive) {
        try h.field(&s, data, "handler", h.arg(args, 0));
        const queue = try h.invoke(&s, try s.get(data, "queue"), "splice", &.{c.JS_NewInt32(engine.context, 0)});
        var iterator = try js.Iterator.init(engine, queue, try h.iteratorSymbol(&s));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |frame| {
            defer engine.freeValue(frame);
            _ = try s.keep(try js.call(engine, h.arg(args, 0), c.pi_js_undefined(), &.{frame}));
        }
        return c.pi_js_undefined();
    }
    if (method == .ended) return ended(&s, receiver, data, h.arg(args, 0));
    if (method == .close) {
        if (try h.flag(&s, data, "closed")) return c.pi_js_undefined();
        const reason = if (c.JS_IsUndefined(h.arg(args, 0))) try s.text("closed") else args[0];
        const bye = try s.record();
        try h.field(&s, bye, "t", try s.text("bye"));
        try h.field(&s, bye, "reason", reason);
        _ = h.invoke(&s, receiver, "transmit", &.{bye}) catch |err| if (err == error.JavaScriptException) c.pi_js_undefined() else return err;
        _ = try h.invoke(&s, receiver, "ended", &.{reason});
        return c.pi_js_undefined();
    }
    if (method == .deliver_later) {
        try deliverLater(&s, receiver, data, h.arg(args, 0));
        return c.pi_js_undefined();
    }
    if (method == .deliver) {
        const frame = h.arg(args, 0);
        if (!c.JS_IsUndefined(try s.get(data, "decoding"))) {
            const promise = try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "resolve", &.{frame});
            _ = try h.invoke(&s, receiver, "deliverLater", &.{promise});
        } else try deliverNow(&s, receiver, data, frame);
        return c.pi_js_undefined();
    }
    if (method == .sever or method == .memory_transmit or method == .memory_shutdown) {
        const memory = (try h.actor(&s, receiver, bindings, .MemoryLink)).data;
        if (method == .sever) {
            try h.field(&s, memory, "severed", c.pi_js_bool(engine.context, 1));
            const peer = try s.get(receiver, "peer");
            if (c.JS_ToBool(engine.context, peer) != 0) try h.field(&s, (try h.actor(&s, peer, bindings, .MemoryLink)).data, "severed", c.pi_js_bool(engine.context, 1));
            return c.pi_js_undefined();
        }
        if (method == .memory_transmit and try h.flag(&s, memory, "severed")) return c.pi_js_undefined();
        const text = if (method == .memory_transmit) try s.builtin("JSON", "stringify", &.{try @import("native_chord_packing.zig").packObject(&s, bindings, h.arg(args, 0), true)}) else c.pi_js_undefined();
        var captures = [_]c.JSValue{ receiver, try s.get(receiver, "peer"), text, bindings };
        const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, memoryDelivery, "", 0, if (method == .memory_shutdown) 1 else 0, 4, &captures)));
        try h.field(&s, memory, "pending", try h.invoke(&s, try s.get(memory, "pending"), "then", &.{task}));
        return if (method == .memory_transmit) s.result(try s.get(text, "length")) else c.pi_js_undefined();
    }
    if (method == .ipc_transmit or method == .ipc_shutdown) {
        const ipc = (try h.actor(&s, receiver, bindings, .IpcLink)).data;
        const channel = try s.get(ipc, "channel");
        if (method == .ipc_shutdown) {
            _ = try h.invoke(&s, channel, "off", &.{ try s.text("message"), try s.get(ipc, "onMessage") });
            _ = try h.invoke(&s, channel, "off", &.{ try s.text("disconnect"), try s.get(ipc, "onDisconnect") });
        } else if (try h.flag(&s, channel, "connected")) {
            const message_value = try s.record();
            try h.field(&s, message_value, "chord2", try @import("native_chord_packing.zig").packObject(&s, bindings, h.arg(args, 0), true));
            _ = try h.invoke(&s, channel, "send", &.{ message_value, try s.get(ipc, "onSent") });
        }
        return c.pi_js_undefined();
    }
    const socket_data = (try h.actor(&s, receiver, bindings, .WebSocketLink)).data;
    const socket = try s.get(socket_data, "socket");
    if (method == .socket_transmit) {
        const socket_text = try @import("native_chord_packing.zig").packMessage(&s, bindings, h.arg(args, 0), try h.flag(&s, socket_data, "compress"));
        if (c.JS_IsStrictEqual(engine.context, try s.get(socket, "readyState"), c.JS_NewInt32(engine.context, 1))) _ = try h.invoke(&s, socket, "send", &.{socket_text}) else _ = try h.invoke(&s, try s.get(socket_data, "outbox"), "push", &.{socket_text});
        return s.result(try s.get(socket_text, if (c.JS_IsString(socket_text)) "length" else "byteLength"));
    } else {
        try h.field(&s, socket_data, "outbox", try s.list());
        var ready: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &ready, try s.get(socket, "readyState")) < 0) return js.capture(engine);
        if (ready <= 1) _ = try h.invoke(&s, socket, "close", &.{c.JS_NewInt32(engine.context, 1000)});
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, captures[1]) < 0) return js.capture(engine);
    const kind: h.Kind = @enumFromInt(raw);
    const result = try s.keep(try h.allocate(engine, target, bindings, kind));
    const data = (try h.actor(&s, result, bindings, kind)).data;
    try h.field(&s, data, "handler", c.pi_js_undefined());
    try h.field(&s, data, "queue", try s.list());
    try h.field(&s, data, "closeHandlers", try h.set(&s));
    try h.field(&s, data, "closed", c.pi_js_bool(engine.context, 0));
    try h.field(&s, data, "decoding", c.pi_js_undefined());
    if (kind == .MemoryLink) {
        try h.field(&s, result, "peer", c.pi_js_undefined());
        try h.field(&s, data, "severed", c.pi_js_bool(engine.context, 0));
        try h.field(&s, data, "pending", try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "resolve", &.{}));
    } else if (kind == .IpcLink) {
        const channel = h.arg(args, 0);
        try h.field(&s, data, "channel", channel);
        var event_captures = [_]c.JSValue{ result, bindings };
        const on_message = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, ipcEvent, "", 1, 0, 2, &event_captures)));
        const on_disconnect = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, ipcEvent, "", 0, 1, 2, &event_captures)));
        const on_sent = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, ipcEvent, "", 1, 2, 2, &event_captures)));
        try h.field(&s, data, "onMessage", on_message);
        try h.field(&s, data, "onDisconnect", on_disconnect);
        try h.field(&s, data, "onSent", on_sent);
        _ = try h.invoke(&s, channel, "on", &.{ try s.text("message"), on_message });
        _ = try h.invoke(&s, channel, "on", &.{ try s.text("disconnect"), on_disconnect });
    } else if (kind == .WebSocketLink) {
        const socket = h.arg(args, 0);
        const options = if (c.JS_IsUndefined(h.arg(args, 1))) try s.record() else h.arg(args, 1);
        const compress = try s.get(options, "compress");
        const accept_packed = try s.get(options, "acceptPacked");
        try h.field(&s, data, "compress", if (h.nullish(compress)) c.pi_js_bool(engine.context, 0) else compress);
        try h.field(&s, data, "acceptPacked", if (h.nullish(accept_packed)) c.pi_js_bool(engine.context, 1) else accept_packed);
        try h.field(&s, data, "outbox", try s.list());
        try h.field(&s, data, "socket", socket);
        if (try js.hasKey(engine, socket, try s.text("binaryType"))) try js.setKey(engine, socket, try s.text("binaryType"), try s.text("arraybuffer"));
        inline for (.{ "open", "message", "close" }, 0..) |name, index| {
            var event_captures = [_]c.JSValue{ result, bindings };
            const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, socketEvent, "", if (index == 1) 1 else 0, index, 2, &event_captures)));
            _ = try h.invoke(&s, socket, "addEventListener", &.{ try s.text(name), listener });
        }
    }
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    inline for (.{ h.Kind.BaseLink, h.Kind.MemoryLink, h.Kind.IpcLink, h.Kind.WebSocketLink }) |kind| {
        try h.register(&s, bindings, kind);
        const base = if (kind == .BaseLink) c.pi_js_undefined() else try s.get(bindings, "BaseLink");
        const prototype = if (kind == .BaseLink) try s.record() else try s.keep(try engine.checked(c.JS_NewObjectProto(engine.context, try s.get(base, "prototype"))));
        const constructor = try s.keep(try @import("native_class.zig").constructor(engine, @tagName(kind), if (kind == .IpcLink or kind == .WebSocketLink) 1 else 0, prototype, construct, &.{ bindings, c.JS_NewInt32(engine.context, @intFromEnum(kind)) }));
        if (kind != .BaseLink and c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
        try h.field(&s, bindings, @tagName(kind), constructor);
        if (kind == .BaseLink) {
            try h.define(&s, prototype, bindings, "deliverLater", callback, @intFromEnum(Method.deliver_later), 1, false, false);
            inline for (.{ .{ "closed", Method.closed, 0, true }, .{ "send", Method.send, 1, false }, .{ "receive", Method.receive, 1, false }, .{ "onClose", Method.on_close, 1, false }, .{ "close", Method.close, 0, false }, .{ "deliver", Method.deliver, 1, false }, .{ "ended", Method.ended, 1, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
        } else {
            if (kind == .MemoryLink) try h.define(&s, prototype, bindings, "sever", callback, @intFromEnum(Method.sever), 0, false, false);
            try h.define(&s, prototype, bindings, "transmit", callback, @intFromEnum(if (kind == .MemoryLink) Method.memory_transmit else if (kind == .IpcLink) Method.ipc_transmit else Method.socket_transmit), 1, false, false);
            try h.define(&s, prototype, bindings, "shutdown", callback, @intFromEnum(if (kind == .MemoryLink) Method.memory_shutdown else if (kind == .IpcLink) Method.ipc_shutdown else Method.socket_shutdown), 0, false, false);
        }
    }
    inline for (.{ .{ "memoryLinkPair", Method.pair, 0 }, .{ "ipcLink", Method.ipc, 1 }, .{ "webSocketLink", Method.socket, 1 } }) |item| {
        var captures = [_]c.JSValue{bindings};
        try js.define(engine, bindings, item[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, item[0], item[2], @intFromEnum(item[1]), 1, &captures)));
    }
}
