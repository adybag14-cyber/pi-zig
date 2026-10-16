//! Combined shared scheduling regression cohort; original provider tests retain
//! their exact Source fixtures and strict intermediate snapshot assertions.
comptime {
    _ = @import("native_ai_google_mistral_test.zig");
    _ = @import("native_ai_http_test.zig");
    _ = @import("native_immediates_test.zig");
    _ = @import("native_event_stream_live_test.zig");
}
