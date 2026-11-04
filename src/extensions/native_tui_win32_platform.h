/* Source-bound Win32 TUI platform owner. No engine objects cross this ABI. */
#ifndef PI_TUI_WIN32_PLATFORM_H
#define PI_TUI_WIN32_PLATFORM_H
#include <stddef.h>
#include <stdint.h>
typedef struct PiTuiClipboardJob PiTuiClipboardJob;
enum { PI_TUI_WORKER_STACK_RESERVATION = 1024 * 1024 };
enum PiTuiClipboardCreateFailure {
    PI_TUI_CREATE_OK = 0,
    PI_TUI_CREATE_NATIVE_BUDGET = 1,
    PI_TUI_CREATE_OS_JOB = 2,
    PI_TUI_CREATE_OS_TEXT = 3,
    PI_TUI_CREATE_INVALID = 4
};
enum PiTuiClipboardOperation {
    PI_TUI_CLIPBOARD_TEXT = 0,
    PI_TUI_CLIPBOARD_IMAGE = 1,
    PI_TUI_CLIPBOARD_WRITE = 2
};
enum PiTuiClipboardFormat {
    PI_TUI_CLIPBOARD_UNAVAILABLE = 0,
    PI_TUI_CLIPBOARD_EMPTY = 1,
    PI_TUI_CLIPBOARD_UTF8 = 2,
    PI_TUI_CLIPBOARD_LATIN1 = 3,
    PI_TUI_CLIPBOARD_UTF16 = 4,
    PI_TUI_CLIPBOARD_BUFFER = 5,
    PI_TUI_CLIPBOARD_PATHS = 6
};
int pi_tui_win32_enable_virtual_terminal_input(void);
int pi_tui_win32_is_modifier_pressed(const char *name);
/* Creation copies all input and retains the real aggregate allocation owner.
   execute runs once on its owned worker; observation/destruction follows join. */
PiTuiClipboardJob *pi_tui_win32_clipboard_create(
    void *memory_owner, int operation, const uint16_t *text, size_t length,
    int *failure);
int pi_tui_win32_clipboard_start(PiTuiClipboardJob *job);
int pi_tui_win32_clipboard_done(const PiTuiClipboardJob *job);
void pi_tui_win32_clipboard_join(PiTuiClipboardJob *job);
int pi_tui_win32_clipboard_format(const PiTuiClipboardJob *job);
const void *pi_tui_win32_clipboard_data(const PiTuiClipboardJob *job);
size_t pi_tui_win32_clipboard_length(const PiTuiClipboardJob *job);
const char *pi_tui_win32_clipboard_error(const PiTuiClipboardJob *job);
int pi_tui_win32_clipboard_allocation_failed(const PiTuiClipboardJob *job);
void pi_tui_win32_clipboard_destroy(PiTuiClipboardJob *job);
#endif
