//! Public provider method descriptor shared with the extension engine.
const implementation = @import("extensions/provider_method_ref.zig");
pub const callback_id_field = implementation.callback_id_field;
pub const callback_kind_field = implementation.callback_kind_field;
pub const callback_path_field = implementation.callback_path_field;
pub const callback_generation_field = implementation.callback_generation_field;
pub const provider_method_kind = implementation.provider_method_kind;
pub const ProviderMethodRef = implementation.ProviderMethodRef;
pub const isProviderMethodRef = implementation.isProviderMethodRef;
test {
    _ = implementation;
}
