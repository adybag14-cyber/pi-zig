const std = @import("std");
const p = @import("photon_session.zig");
const c = p.operations;
/// Returns a new handle only for quarter turns, matching the original caller's
/// responsibility to release the old image when the returned object differs.
pub fn apply(session: *p.Session, handle: u32, orientation: u8) !u32 {
    switch (orientation) {
        2, 3, 4 => {
            if (orientation != 4) _ = try session.checked(session.call(c.PI_SESSION_FLIP_H, handle, null, 0, 0, 0));
            if (orientation != 2) _ = try session.checked(session.call(c.PI_SESSION_FLIP_V, handle, null, 0, 0, 0));
            return handle;
        },
        5...8 => {
            const pixels = try session.checked(session.call(c.PI_SESSION_PIXELS, handle, null, 0, 0, 0));
            defer session.freeReply(pixels);
            const output = try session.gpa.alloc(u8, pixels.length);
            defer session.gpa.free(output);
            const width: usize = pixels.width;
            const height: usize = pixels.height;
            for (0..height) |y| for (0..width) |x| {
                const source = (y * width + x) * 4;
                const destination = (if (orientation <= 6) x * height + height - 1 - y else (width - 1 - x) * height + y) * 4;
                @memcpy(output[destination..][0..4], pixels.bytes[source..][0..4]);
            };
            const rotated = try session.checked(session.call(c.PI_SESSION_RGBA, 0, output, pixels.height, pixels.width, 0));
            if (orientation == 5 or orientation == 7) _ = try session.checked(session.call(c.PI_SESSION_FLIP_H, rotated.image, null, 0, 0, 0));
            return rotated.image;
        },
        else => return handle,
    }
}
