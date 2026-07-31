//! Auth package root: OAuth helpers + generated provider flow surface.
const std = @import("std");

pub const oauth = @import("oauth.zig");
pub const generated = @import("generated_root.zig");
pub const product = @import("product.zig");

pub const parseDeviceCodeResponse = oauth.parseDeviceCodeResponse;
pub const parseTokenResponse = oauth.parseTokenResponse;
pub const saveTokens = oauth.saveTokens;
pub const loadAccessToken = oauth.loadAccessToken;

test {
    std.testing.refAllDecls(@This());
}
