//! Exact C ABI of the source-bound Win32 platform implementation.
pub const Job = opaque {};
pub const CreateFailure = enum(c_int) { none = 0, native_budget = 1, os_job = 2, os_text = 3, invalid = 4 };
pub const Operation = enum(c_int) { text = 0, image = 1, write = 2 };
pub const Format = enum(c_int) { unavailable = 0, empty = 1, utf8 = 2, latin1 = 3, utf16 = 4, buffer = 5, paths = 6 };
pub extern fn pi_tui_win32_enable_virtual_terminal_input() c_int;
pub extern fn pi_tui_win32_is_modifier_pressed(name: [*:0]const u8) c_int;
pub extern fn pi_tui_win32_clipboard_create(memory_owner: *anyopaque, operation: c_int, text: ?[*]const u16, length: usize, failure: *c_int) ?*Job;
pub extern fn pi_tui_win32_clipboard_start(job: *Job) c_int;
pub extern fn pi_tui_win32_clipboard_done(job: *const Job) c_int;
pub extern fn pi_tui_win32_clipboard_join(job: *Job) void;
pub extern fn pi_tui_win32_clipboard_format(job: *const Job) c_int;
pub extern fn pi_tui_win32_clipboard_data(job: *const Job) ?*const anyopaque;
pub extern fn pi_tui_win32_clipboard_length(job: *const Job) usize;
pub extern fn pi_tui_win32_clipboard_error(job: *const Job) ?[*:0]const u8;
pub extern fn pi_tui_win32_clipboard_allocation_failed(job: *const Job) c_int;
pub extern fn pi_tui_win32_clipboard_destroy(job: *Job) void;
