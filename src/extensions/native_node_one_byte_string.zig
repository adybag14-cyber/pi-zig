// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Selected node::OneByteString / NewFromOneByte(kNormal) operation over the
//! real VM Latin-1 primitive. Bytes are never interpreted as UTF-8.
//! Native V8 heap layout, its single-character cache and GC/retry machinery are
//! not implemented by this raw VM primitive; allocation remains the real VM's.
const a = @import("native_node_argument_values.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
extern fn pi_node_one_byte_string_cstring_length(?*c.JSContext, [*c]const u8) c_int;
extern fn pi_node_one_byte_string_empty_maybe_handle(?*c.JSContext) void;

// v8::String::kMaxLength in the pinned v8-primitive.h, for the target pointer.
pub const max_length: c_int = if (@sizeOf(usize) == 4)
    (1 << 28) - 16 else (1 << 29) - 24;

pub fn fromCString(s: *a.Scope, data: [*:0]const u8,
    diagnostics: ?*const check.Diagnostics) anyerror!c.JSValue
{
    return fromOneByte(s, data, -1, diagnostics);
}

/// length is the original signed API argument. Negative values use strlen;
/// zero needs no readable input byte; positive lengths preserve embedded NUL.
pub fn fromOneByte(s: *a.Scope, data: [*c]const u8, length: c_int,
    diagnostics: ?*const check.Diagnostics) anyerror!c.JSValue
{
    try s.pending();
    if (length > max_length)
        check.fatal(s.engine, "v8::ToLocalChecked", "Empty MaybeLocal", diagnostics);

    const actual_length = if (length < 0)
        pi_node_one_byte_string_cstring_length(s.engine.context, data) else length;
    if (actual_length > max_length) {
        // Only an inferred C-string length can reach this factory branch.
        // FactoryBase::NewRawStringWithMap first produces the invalid-length
        // RangeError; the empty MaybeHandle then fails its real V8 CHECK.
        const occurrence = c.JS_PiOutOfMemoryOccurrence(s.engine.runtime);
        _ = c.JS_ThrowRangeError(s.engine.context, "Invalid string length");
        if (c.JS_PiOutOfMemoryOccurrence(s.engine.runtime) != occurrence)
            check.heapOutOfMemory(s.engine, diagnostics);
        pi_node_one_byte_string_empty_maybe_handle(s.engine.context);
        unreachable;
    }
    const generation = try s.beforeAllocation();
    const occurrence = c.JS_PiOutOfMemoryOccurrence(s.engine.runtime);
    const raw = c.JS_PiNewStringLatin1(s.engine.context, data,
        @as(usize, @intCast(actual_length)));
    if (c.JS_IsException(raw) and
        c.JS_PiOutOfMemoryOccurrence(s.engine.runtime) != occurrence)
        check.heapOutOfMemory(s.engine, diagnostics);
    return s.checkedAllocation(raw, generation);
}
