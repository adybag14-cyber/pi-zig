//! Streaming TextDecoder implemented in Zig over the linked C runtime.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Encoding = enum { utf8, utf16le, utf16be };
const State = struct {
    engine: *engine_mod.Engine,
    encoding: Encoding = .utf8,
    fatal: bool = false,
    ignore_bom: bool = false,
    streaming: bool = false,
    bom_seen: bool = false,
    point: u21 = 0,
    needed: u3 = 0,
    seen: u3 = 0,
    lower: u8 = 0x80,
    upper: u8 = 0xbf,
    pending_byte: ?u8 = null,
    lead: ?u16 = null,

    fn reset(self: *State) void {
        self.bom_seen = false;
        self.resetScalar();
        self.pending_byte = null;
        self.lead = null;
    }

    fn resetScalar(self: *State) void {
        self.point = 0;
        self.needed = 0;
        self.seen = 0;
        self.lower = 0x80;
        self.upper = 0xbf;
    }

    fn emit(self: *State, output: *std.ArrayList(u8), point: u21) !void {
        if (!self.bom_seen) {
            self.bom_seen = true;
            if (!self.ignore_bom and point == 0xfeff) return;
        }
        var encoded: [4]u8 = undefined;
        const length = try std.unicode.utf8Encode(point, &encoded);
        try output.appendSlice(self.engine.gpa, encoded[0..length]);
    }

    fn invalid(self: *State, output: *std.ArrayList(u8)) !void {
        if (self.fatal) return error.InvalidEncodedData;
        try self.emit(output, 0xfffd);
    }

    fn utf8(self: *State, output: *std.ArrayList(u8), bytes: []const u8, stream: bool) !void {
        var index: usize = 0;
        while (index < bytes.len) {
            const byte = bytes[index];
            if (self.needed == 0) {
                index += 1;
                if (byte <= 0x7f) {
                    try self.emit(output, byte);
                } else if (byte >= 0xc2 and byte <= 0xdf) {
                    self.needed = 1;
                    self.point = byte & 0x1f;
                } else if (byte >= 0xe0 and byte <= 0xef) {
                    self.needed = 2;
                    self.point = byte & 0x0f;
                    if (byte == 0xe0) self.lower = 0xa0;
                    if (byte == 0xed) self.upper = 0x9f;
                } else if (byte >= 0xf0 and byte <= 0xf4) {
                    self.needed = 3;
                    self.point = byte & 0x07;
                    if (byte == 0xf0) self.lower = 0x90;
                    if (byte == 0xf4) self.upper = 0x8f;
                } else try self.invalid(output);
            } else if (byte < self.lower or byte > self.upper) {
                // The offending byte belongs to the next scalar, not this one.
                self.resetScalar();
                try self.invalid(output);
            } else {
                index += 1;
                self.lower = 0x80;
                self.upper = 0xbf;
                self.point = (self.point << 6) | (byte & 0x3f);
                self.seen += 1;
                if (self.seen == self.needed) {
                    const point = self.point;
                    self.resetScalar();
                    try self.emit(output, point);
                }
            }
        }
        if (!stream and self.needed != 0) {
            self.resetScalar();
            try self.invalid(output);
        }
    }

    fn utf16Unit(self: *State, output: *std.ArrayList(u8), unit: u16) !void {
        if (self.lead) |lead| {
            self.lead = null;
            if (unit >= 0xdc00 and unit <= 0xdfff) {
                return self.emit(output, 0x10000 + (@as(u21, lead - 0xd800) << 10) + unit - 0xdc00);
            }
            try self.invalid(output);
            // A non-trailing unit must be processed again after the error.
        }
        if (unit >= 0xd800 and unit <= 0xdbff) {
            self.lead = unit;
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            try self.invalid(output);
        } else try self.emit(output, unit);
    }

    fn utf16(self: *State, output: *std.ArrayList(u8), bytes: []const u8, stream: bool) !void {
        var carried_lead = self.lead != null;
        var carried_byte = self.pending_byte != null;
        for (bytes) |byte| {
            if (self.pending_byte) |first| {
                self.pending_byte = null;
                const unit = if (self.encoding == .utf16le) @as(u16, first) | (@as(u16, byte) << 8) else (@as(u16, first) << 8) | byte;
                self.utf16Unit(output, unit) catch |err| {
                    // Node's fatal UTF-16 converter retains the first byte of
                    // a rejected unit when any bytes of its leading surrogate
                    // came from a preceding call. Preserve that observable
                    // streaming state; same-call failures discard the unit.
                    if (err == error.InvalidEncodedData and carried_lead) self.pending_byte = first;
                    return err;
                };
                carried_lead = carried_byte and self.lead != null;
                carried_byte = false;
            } else self.pending_byte = byte;
        }
        if (!stream and (self.pending_byte != null or self.lead != null)) {
            self.pending_byte = null;
            self.lead = null;
            try self.invalid(output);
        }
    }

    fn decode(self: *State, bytes: []const u8, stream: bool) ![]u8 {
        if (!self.streaming) self.reset();
        self.streaming = stream;
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.engine.gpa);
        switch (self.encoding) {
            .utf8 => try self.utf8(&output, bytes, stream),
            .utf16le, .utf16be => try self.utf16(&output, bytes, stream),
        }
        return output.toOwnedSlice(self.engine.gpa);
    }
};

fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    if (err == error.UnsupportedEncoding) return c.JS_ThrowRangeError(engine.context, "Unsupported TextDecoder encoding");
    return c.JS_ThrowTypeError(engine.context, "Native TextDecoder: %s", @as([*:0]const u8, @errorName(err)));
}

fn stateFor(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.text_decoder_class) orelse return error.IllegalTextDecoderReceiver));
    if (state.engine != engine) return error.IllegalTextDecoderReceiver;
    return state;
}

fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.text_decoder_class) orelse return));
    engine.gpa.destroy(state);
}

fn option(engine: *engine_mod.Engine, options: c.JSValue, name: [*:0]const u8) !bool {
    if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) return false;
    if (!c.JS_IsObject(options)) return error.InvalidTextDecoderOptions;
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, options, name));
    defer engine.freeValue(value);
    const boolean = c.JS_ToBool(engine.context, value);
    if (boolean < 0) return error.JavaScriptException;
    return boolean != 0;
}

fn parseLabel(label: []const u8) !Encoding {
    const trimmed = std.mem.trim(u8, label, "\x09\x0a\x0c\x0d\x20");
    for ([_][]const u8{ "utf-8", "utf8", "unicode-1-1-utf-8", "unicode11utf8", "unicode20utf8", "x-unicode20utf8" }) |alias| {
        if (std.ascii.eqlIgnoreCase(trimmed, alias)) return .utf8;
    }
    for ([_][]const u8{ "utf-16", "utf-16le", "ucs-2", "unicode", "unicodefeff", "csunicode", "iso-10646-ucs-2" }) |alias| {
        if (std.ascii.eqlIgnoreCase(trimmed, alias)) return .utf16le;
    }
    for ([_][]const u8{ "utf-16be", "unicodefffe" }) |alias| {
        if (std.ascii.eqlIgnoreCase(trimmed, alias)) return .utf16be;
    }
    return error.UnsupportedEncoding;
}

fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return constructValue(engine, target, argc, argv) catch |err| fail(engine, err);
}

fn constructValue(engine: *engine_mod.Engine, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    const label = if (argc == 0 or c.JS_IsUndefined(argv[0])) try engine.gpa.dupe(u8, "utf-8") else try engine.toString(argv[0]);
    defer engine.gpa.free(label);
    const encoding = try parseLabel(label);
    const options = if (argc > 1) argv[1] else c.pi_js_undefined();
    const fatal = try option(engine, options, "fatal");
    const ignore_bom = try option(engine, options, "ignoreBOM");
    var prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, target, "prototype"));
    if (!c.JS_IsObject(prototype)) {
        engine.freeValue(prototype);
        prototype = try engine.checked(c.JS_GetClassProto(engine.context, engine.text_decoder_class));
    }
    defer engine.freeValue(prototype);
    const state = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(state);
    state.* = .{ .engine = engine, .encoding = encoding, .fatal = fatal, .ignore_bom = ignore_bom };
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.text_decoder_class));
    _ = c.JS_SetOpaque(object, state);
    return object;
}

fn callGetter(engine: *engine_mod.Engine, getter: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, getter, receiver, 0, null));
}

fn indexGetter(engine: *engine_mod.Engine, getter: c.JSValue, receiver: c.JSValue, type_error_prototype: c.JSValue) !?usize {
    const value = c.JS_Call(engine.context, getter, receiver, 0, null);
    if (c.JS_IsException(value)) {
        const exception = c.JS_GetException(engine.context);
        if (c.JS_IsDataView(receiver) and c.JS_IsError(exception)) {
            const prototype = c.JS_GetPrototype(engine.context, exception);
            const out_of_bounds = !c.JS_IsException(prototype) and c.JS_IsStrictEqual(engine.context, prototype, type_error_prototype);
            engine.freeValue(prototype);
            if (out_of_bounds) {
                // This captured C getter can throw TypeError only for the
                // branded view's bounds. Other exceptions, including OOM,
                // retain their original value and propagate.
                engine.freeValue(exception);
                return null;
            }
        }
        _ = c.JS_Throw(engine.context, exception);
        return error.JavaScriptException;
    }
    defer engine.freeValue(value);
    var index: u64 = 0;
    if (c.JS_ToIndex(engine.context, &index, value) < 0) return error.JavaScriptException;
    return std.math.cast(usize, index) orelse error.InvalidTextDecoderInput;
}

// Intrinsic C getters are captured when installing the function. User-owned
// .buffer/.byteOffset/.byteLength properties cannot impersonate a real view.
fn inputBytes(engine: *engine_mod.Engine, value: c.JSValue, getters: [*c]c.JSValue) ![]const u8 {
    if (c.JS_IsUndefined(value)) return &.{};
    const view = c.JS_GetTypedArrayType(value) >= 0 or c.JS_IsDataView(value);
    const base: usize = if (c.JS_IsDataView(value)) 0 else 3;
    const buffer = if (view) try callGetter(engine, getters[base], value) else c.JS_DupValue(engine.context, value);
    defer engine.freeValue(buffer);
    if (c.JS_IsArrayBuffer(buffer)) {
        const detached = try callGetter(engine, getters[6], buffer);
        defer engine.freeValue(detached);
        if (c.JS_ToBool(engine.context, detached) != 0) return &.{};
    }
    const offset = if (view) (try indexGetter(engine, getters[base + 1], value, getters[7])) orelse return &.{} else 0;
    const length = if (view) (try indexGetter(engine, getters[base + 2], value, getters[7])) orelse return &.{} else null;
    var total: usize = 0;
    const bytes = c.JS_GetArrayBuffer(engine.context, &total, buffer);
    if (c.JS_HasException(engine.context)) return error.JavaScriptException;
    const count = length orelse total;
    if (offset > total or count > total - offset or (bytes == null and count != 0)) return error.InvalidTextDecoderInput;
    return if (count == 0) &.{} else bytes[offset .. offset + count];
}

fn decode(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, getters: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return decodeValue(engine, this, argc, argv, getters) catch |err| fail(engine, err);
}

fn decodeValue(engine: *engine_mod.Engine, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, getters: [*c]c.JSValue) !c.JSValue {
    const state = try stateFor(engine, this);
    // Complete observable option access before obtaining any memory pointer.
    const stream = try option(engine, if (argc > 1) argv[1] else c.pi_js_undefined(), "stream");
    const bytes = try inputBytes(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), getters);
    const output = try state.decode(bytes, stream);
    defer engine.gpa.free(output);
    return engine.checked(c.JS_NewStringLen(engine.context, output.ptr, output.len));
}

fn attribute(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const state = stateFor(engine, this) catch |err| return fail(engine, err);
    return switch (magic) {
        0 => c.JS_NewString(context, switch (state.encoding) {
            .utf8 => "utf-8",
            .utf16le => "utf-16le",
            .utf16be => "utf-16be",
        }),
        1 => c.pi_js_bool(context, @intFromBool(state.fatal)),
        2 => c.pi_js_bool(context, @intFromBool(state.ignore_bom)),
        else => unreachable,
    };
}

fn intrinsicGetter(engine: *engine_mod.Engine, prototype: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(engine.context, &descriptor, prototype, atom);
    if (found < 0) return error.JavaScriptException;
    if (found == 0) return error.MissingTextDecoderIntrinsic;
    engine.freeValue(descriptor.value);
    engine.freeValue(descriptor.setter);
    return descriptor.getter;
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.text_decoder_class != 0) return error.TextDecoderAlreadyInstalled;
    _ = c.JS_NewClassID(engine.runtime, &engine.text_decoder_class);
    const definition: c.JSClassDef = .{ .class_name = "TextDecoder", .finalizer = finalizer, .gc_mark = null, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.text_decoder_class, &definition) < 0) return error.TextDecoderClassFailed;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const data_view = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "DataView"));
    defer engine.freeValue(data_view);
    const dv_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, data_view, "prototype"));
    defer engine.freeValue(dv_prototype);
    const uint8 = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Uint8Array"));
    defer engine.freeValue(uint8);
    const uint8_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, uint8, "prototype"));
    defer engine.freeValue(uint8_prototype);
    const ta_prototype = try engine.checked(c.JS_GetPrototype(engine.context, uint8_prototype));
    defer engine.freeValue(ta_prototype);
    const array_buffer = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "ArrayBuffer"));
    defer engine.freeValue(array_buffer);
    const ab_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, array_buffer, "prototype"));
    defer engine.freeValue(ab_prototype);
    var getters: [8]c.JSValue = undefined;
    var initialized: usize = 0;
    defer for (getters[0..initialized]) |getter| engine.freeValue(getter);
    for ([_]c.JSValue{ dv_prototype, ta_prototype }, 0..) |proto, group| {
        for ([_][*:0]const u8{ "buffer", "byteOffset", "byteLength" }, 0..) |name, index| {
            getters[group * 3 + index] = try intrinsicGetter(engine, proto, name);
            initialized += 1;
        }
    }
    getters[6] = try intrinsicGetter(engine, ab_prototype, "detached");
    initialized += 1;
    const type_error = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "TypeError"));
    defer engine.freeValue(type_error);
    getters[7] = try engine.checked(c.JS_GetPropertyStr(engine.context, type_error, "prototype"));
    initialized += 1;
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "TextDecoder", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, engine.text_decoder_class, c.JS_DupValue(engine.context, prototype));
    const method = try engine.checked(c.JS_NewCFunctionData(engine.context, decode, 0, 0, getters.len, &getters));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "decode", method, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    for ([_][*:0]const u8{ "encoding", "fatal", "ignoreBOM" }, 0..) |name, index| {
        const atom = c.JS_NewAtom(engine.context, name);
        defer c.JS_FreeAtom(engine.context, atom);
        const getter = c.pi_js_function_magic(engine.context, attribute, name, 0, @intCast(index));
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
    if (c.JS_DefinePropertyValueStr(engine.context, global, "TextDecoder", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn fixture(source: []const u8, expected: []const u8) !void {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.eval(source, "decoder-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings(expected, text);
}

test "native TextDecoder UTF-8 malformed maximal subparts and streaming scalar boundaries" {
    try fixture(
        \\const d=new TextDecoder(); const arrays=[[0xc0,0xaf],[0xe0,0x80,0x80],[0xed,0xa0,0x80],[0xf4,0x90,0x80,0x80],[0xe2,0x82],[0xe2,0x82,65],[0xf0,0x9f,0x8c,0x8d]];
        \\const malformed=arrays.map(x=>d.decode(Uint8Array.from(x)));
        \\const streaming=[d.decode(new Uint8Array([0xf0]),{stream:true}),d.decode(new Uint8Array([0x9f,0x8c]),{stream:true}),d.decode(new Uint8Array([0x8d,65]),{stream:true}),d.decode()];
        \\JSON.stringify({malformed,streaming});
    , "{\"malformed\":[\"��\",\"���\",\"���\",\"����\",\"�\",\"�A\",\"🌍\"],\"streaming\":[\"\",\"\",\"🌍A\",\"\"]}");
}

test "native TextDecoder BOM options empty views fatal reset and exception identity" {
    try fixture(
        \\const d=new TextDecoder(' UTF8 '); const bom=new Uint8Array([239,187,191,65]);
        \\const outputs=[d.decode(bom),d.decode(bom),new TextDecoder('utf8',{ignoreBOM:true}).decode(bom),d.decode(bom.subarray(0,0)),d.decode(new ArrayBuffer(0))];
        \\outputs.push(d.decode(new Uint8Array([239]),{stream:true}),d.decode(new Uint8Array([187]),{stream:true}),d.decode(new Uint8Array([191,66]),{stream:true}),d.decode());
        \\const f=new TextDecoder('utf8',{fatal:true}); let fatal=false;try{f.decode(new Uint8Array([0xff]))}catch(e){fatal=e instanceof TypeError}outputs.push(f.decode(bom));
        \\const reason={}; let identities=[];try{new TextDecoder({toString(){throw reason}})}catch(e){identities.push(e===reason)}try{new TextDecoder('utf8',{get fatal(){throw reason}})}catch(e){identities.push(e===reason)}try{d.decode(bom,{get stream(){throw reason}})}catch(e){identities.push(e===reason)}
        \\JSON.stringify({outputs,fatal,identities,encoding:d.encoding,ignoreBOM:d.ignoreBOM});
    , "{\"outputs\":[\"A\",\"A\",\"﻿A\",\"\",\"\",\"\",\"\",\"B\",\"\",\"A\"],\"fatal\":true,\"identities\":[true,true,true],\"encoding\":\"utf-8\",\"ignoreBOM\":false}");
}

test "native TextDecoder UTF-16 endian surrogate and odd-byte streaming" {
    try fixture(
        \\const le=new TextDecoder('utf-16');const be=new TextDecoder('utf-16be');
        \\JSON.stringify([le.encoding,le.decode(new Uint8Array([255,254,65,0,60,216,13,223])),be.decode(new Uint8Array([254,255,0,65,216,60,223,13])),le.decode(new Uint8Array([0,216,65,0,0,220])),le.decode(new Uint8Array([65])),le.decode(new Uint8Array([60]),{stream:true}),le.decode(new Uint8Array([216,13]),{stream:true}),le.decode(new Uint8Array([223])),le.decode()]);
    , "[\"utf-16le\",\"A🌍\",\"A🌍\",\"�A�\",\"�\",\"\",\"\",\"🌍\",\"\"]");
}

test "native TextDecoder genuine BufferSource views captured intrinsics detachment and brands" {
    try fixture(
        \\const data=new Uint8Array([88,65,66,89]);const dv=new DataView(data.buffer,1,2);Object.defineProperty(dv,'buffer',{get(){throw 1}});Object.defineProperty(dv,'byteOffset',{value:0});
        \\const ta=data.subarray(1,3);Object.defineProperty(ta,'buffer',{get(){throw 2}});const d=new TextDecoder();const out=[d.decode(dv),d.decode(ta),d.decode(new Uint16Array(new Uint8Array([65,66]).buffer))];
        \\const buffer=new ArrayBuffer(2),view=new Uint8Array(buffer),dataview=new DataView(buffer);buffer.transfer();out.push(d.decode(buffer),d.decode(view),d.decode(dataview));
        \\const input=new Uint8Array([65]);out.push(d.decode(input,{get stream(){input.buffer.transfer();return false}}));
        \\let brands=[];for(const fn of [()=>TextDecoder.prototype.decode.call({}),()=>Object.getOwnPropertyDescriptor(TextDecoder.prototype,'fatal').get.call({}),()=>d.decode({buffer:data.buffer})]){try{fn();brands.push(false)}catch(e){brands.push(e instanceof TypeError)}}JSON.stringify({out,brands});
    , "{\"out\":[\"AB\",\"AB\",\"AB\",\"\",\"\",\"\",\"\"],\"brands\":[true,true,true]}");
}

test "native TextDecoder streaming flush errors retain BOM state only while streaming" {
    try fixture(
        \\let out=[];for(const stream of [false,true]){const d=new TextDecoder('utf8',{fatal:true});for(const [bytes,options]of [[[239,187,191,65],{stream:true}],[[255],{stream}],[[239,187,191,66],{stream:true}],[[],{}]]){try{out.push(d.decode(Uint8Array.from(bytes),options))}catch(e){out.push(e.name)}}}
        \\const d=new TextDecoder('utf8',{fatal:true});out.push(d.decode(new Uint8Array([226]),{stream:true}));try{d.decode()}catch(e){out.push(e.name)}out.push(d.decode(new Uint8Array([65])));
        \\const regular=new TextDecoder();out.push(regular.decode(new Uint8Array([226]),{stream:true}),regular.decode(),regular.decode(new Uint8Array([65])));
        \\JSON.stringify(out);
    , "[\"A\",\"TypeError\",\"B\",\"\",\"A\",\"TypeError\",\"﻿B\",\"\",\"\",\"TypeError\",\"A\",\"\",\"�\",\"A\"]");
}

test "native TextDecoder scalar boundaries for every split in UTF-8 and both UTF-16 byte orders" {
    try fixture(
        \\let ok=0;for(const [encoding,bytes]of [['utf8',[239,187,191,65,194,162,226,130,172,240,159,140,141]],['utf-16le',[255,254,65,0,162,0,172,32,60,216,13,223]],['utf-16be',[254,255,0,65,0,162,32,172,216,60,223,13]]]){for(let i=0;i<=bytes.length;i++){for(let j=i;j<=bytes.length;j++){const d=new TextDecoder(encoding);const a=Uint8Array.from(bytes);let text=d.decode(a.subarray(0,i),{stream:true})+d.decode(a.subarray(i,j),{stream:true})+d.decode(a.subarray(j),{stream:true})+d.decode();if(text!=='A¢€🌍')throw Error(encoding+':'+i+':'+j);ok++}}}JSON.stringify(ok);
    , "287");
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "TextDecoder"));
    defer engine.freeValue(constructor);
    const object = try constructValue(engine, constructor, 0, null);
    defer engine.freeValue(object);
    const state = try stateFor(engine, object);
    const split = try state.decode(&.{ 0xef, 0xbb }, true);
    defer gpa.free(split);
    const text = try state.decode(&.{ 0xbf, 'A', 0xf0, 0x9f, 0x8c, 0x8d }, false);
    defer gpa.free(text);
    try std.testing.expectEqualStrings("A🌍", text);
    const long = try state.decode(&(@as([1024]u8, @splat('x'))), false);
    defer gpa.free(long);
    try std.testing.expectEqual(@as(usize, 1024), long.len);
}

test "native TextDecoder allocations and state ownership clean up every failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

test "native TextDecoder 4096 deterministic malformed streaming calls match the Node oracle" {
    try fixture(
        \\const decoders=['utf8','utf-16le','utf-16be'].flatMap(e=>[new TextDecoder(e),new TextDecoder(e,{fatal:true})]);let seed=0x156731ff,hash=2166136261,errors=0,units=0;
        \\function next(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed}function record(text){for(let i=0;i<text.length;i++){hash=Math.imul(hash^text.charCodeAt(i),16777619)>>>0;units++}hash=Math.imul(hash^65535,16777619)>>>0}
        \\for(let n=0;n<4096;n++){const d=decoders[next()%6],length=next()%17,bytes=new Uint8Array(length);for(let i=0;i<length;i++)bytes[i]=next()>>>24;try{record(d.decode(bytes,{stream:(next()%4)!==0}))}catch(e){errors++;record(e.name)}}for(const d of decoders){try{record(d.decode())}catch(e){errors++;record(e.name)}}JSON.stringify({hash,errors,units});
    , "{\"hash\":4213816811,\"errors\":1001,\"units\":23121}");
}

test "native TextDecoder fatal UTF-16 split-surrogate recovery matches Node byte state" {
    try fixture(
        \\let out=[];for(const encoding of ['utf-16le','utf-16be']){for(const split of [1,2,4]){const d=new TextDecoder(encoding,{fatal:true});const bytes=encoding==='utf-16le'?[0,216,65,0]:[216,0,0,65];for(const b of [bytes.slice(0,split),bytes.slice(split),encoding==='utf-16le'?[66,0]:[0,66],[]]){try{out.push(d.decode(Uint8Array.from(b),{stream:b.length>0}))}catch(e){out.push(e.name)}}}}JSON.stringify(out);
    , "[\"\",\"TypeError\",\"䉁\",\"TypeError\",\"\",\"TypeError\",\"䉁\",\"TypeError\",\"TypeError\",\"\",\"B\",\"\",\"\",\"TypeError\",\"\\u0000\",\"TypeError\",\"\",\"TypeError\",\"\\u0000\",\"TypeError\",\"TypeError\",\"\",\"B\",\"\"]");
}

test "native TextDecoder resizable out-of-bounds DataViews are empty and recover after growth" {
    try fixture(
        \\const a=new ArrayBuffer(8,{maxByteLength:16}),dv=new DataView(a,4,4),d=new TextDecoder();new Uint8Array(a).set([65,66,67,68],4);const out=[d.decode(dv)];a.resize(2);out.push(d.decode(dv));a.resize(8);new Uint8Array(a).set([69,70,71,72],4);out.push(d.decode(dv));JSON.stringify(out);
    , "[\"ABCD\",\"\",\"EFGH\"]");
}
