/*
 * Source-bound Win32 TUI platform implementation.
 *
 * Authority: packages/tui/native/win32/src/win32-platform.c and clipboard.h.
 * The Win32 transfer/keyboard/console algorithms are retained. N-API transport
 * is replaced by an opaque, copied-data C owner consumed by the same-engine
 * Zig adapter. Allocation charges use the actual linked runtime memory owner.
 */
#include "native_tui_win32_platform.h"
#include "engine_abi.h"
#include <stdbool.h>
#include <stdatomic.h>
#include <stdlib.h>
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

typedef enum { CLIPBOARD_TEXT, CLIPBOARD_IMAGE, CLIPBOARD_WRITE, CLIPBOARD_FILES } clipboard_operation;
typedef enum {
    CLIPBOARD_UNAVAILABLE,
    CLIPBOARD_EMPTY,
    CLIPBOARD_UTF8,
    CLIPBOARD_LATIN1,
    CLIPBOARD_UTF16,
    CLIPBOARD_BUFFER,
    CLIPBOARD_PATHS
} clipboard_format;
struct PiTuiClipboardJob {
    void *memory_owner;
    size_t reserved;
    int allocation_failed;
    HANDLE thread;
    _Atomic int done;
    clipboard_operation operation;
    clipboard_format format;
    void *data;
    size_t length;
    const char *error;
};
typedef struct PiTuiClipboardJob clipboard_job;

static void *clipboard_alloc(clipboard_job *job, size_t size) {
    if (!pi_js_native_memory_reserve(job->memory_owner, size)) {
        job->allocation_failed = 1;
        return 0;
    }
    void *result = GlobalAlloc(GPTR, size);
    if (!result) {
        pi_js_native_memory_release(job->memory_owner, size);
        // Original OS transfer allocation failures retain their original job
        // error. Only a real aggregate reservation failure is native fatal.
        return 0;
    }
    job->reserved += size;
    return result;
}
static void clipboard_copy(clipboard_job *job, const void *data, size_t length, clipboard_format format) {
    job->data = clipboard_alloc(job, length ? length : 1);
    if (!job->data) {
        job->error = "Out of memory";
        return;
    }
    volatile uint8_t *target = job->data;
    const volatile uint8_t *source = data;
    for (size_t index = 0; index < length; index++) target[index] = source[index];
    job->length = format == CLIPBOARD_UTF16 ? length / sizeof(uint16_t) : length;
    job->format = format;
}

#ifndef BI_ALPHABITFIELDS
#define BI_ALPHABITFIELDS 6
#endif
#define KEY_PRESSED_MASK 0x8000
#define OPEN_CLIPBOARD_ATTEMPTS 10
#define OPEN_CLIPBOARD_RETRY_MS 5
#define BITMAP_FILE_HEADER_SIZE 14

static int string_equals(const char* left, const char* right) {
    while (*left && *right && *left == *right) {
        left++;
        right++;
    }
    return *left == 0 && *right == 0;
}

static int is_key_pressed(int virtual_key) {
    return ((unsigned short)GetAsyncKeyState(virtual_key) & KEY_PRESSED_MASK) != 0;
}

static int is_modifier_name_pressed(const char* name) {
    if (string_equals(name, "shift")) return is_key_pressed(VK_SHIFT) || is_key_pressed(VK_LSHIFT) || is_key_pressed(VK_RSHIFT);
    if (string_equals(name, "control")) return is_key_pressed(VK_CONTROL) || is_key_pressed(VK_LCONTROL) || is_key_pressed(VK_RCONTROL);
    if (string_equals(name, "option") || string_equals(name, "alt")) return is_key_pressed(VK_MENU) || is_key_pressed(VK_LMENU) || is_key_pressed(VK_RMENU);
    if (string_equals(name, "command") || string_equals(name, "super") || string_equals(name, "win")) return is_key_pressed(VK_LWIN) || is_key_pressed(VK_RWIN);
    return 0;
}

int pi_tui_win32_enable_virtual_terminal_input(void) {
    HANDLE handle = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode = 0;
    bool enabled = handle != INVALID_HANDLE_VALUE &&
        GetConsoleMode(handle, &mode) &&
        SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_INPUT);
    return enabled;
}
int pi_tui_win32_is_modifier_pressed(const char *name) {
    return is_modifier_name_pressed(name);
}

static bool open_clipboard(HWND owner) {
    for (int attempt = 0; attempt < OPEN_CLIPBOARD_ATTEMPTS; attempt++) {
        if (OpenClipboard(owner)) return true;
        Sleep(OPEN_CLIPBOARD_RETRY_MS);
    }
    return false;
}

static uint16_t read_u16(const uint8_t* data) {
    return (uint16_t)data[0] | ((uint16_t)data[1] << 8);
}

static uint32_t read_u32(const uint8_t* data) {
    return (uint32_t)data[0] |
        ((uint32_t)data[1] << 8) |
        ((uint32_t)data[2] << 16) |
        ((uint32_t)data[3] << 24);
}

static void write_u32(uint8_t* data, uint32_t value) {
    data[0] = (uint8_t)value;
    data[1] = (uint8_t)(value >> 8);
    data[2] = (uint8_t)(value >> 16);
    data[3] = (uint8_t)(value >> 24);
}

static void copy_bytes(uint8_t* destination, const uint8_t* source, size_t length) {
    volatile uint8_t* target = destination;
    const volatile uint8_t* input = source;
    for (size_t index = 0; index < length; index++) target[index] = input[index];
}

static size_t dib_pixel_offset(const uint8_t* dib, size_t size) {
    if (size < 12) return 0;
    uint32_t header_size = read_u32(dib);

    if (header_size == 12) {
        uint16_t bits_per_pixel = read_u16(dib + 10);
        uint32_t color_count = bits_per_pixel <= 8 ? 1u << bits_per_pixel : 0;
        size_t offset = header_size + (size_t)color_count * 3;
        return offset <= size ? offset : 0;
    }

    if (header_size < 40 || header_size > size) return 0;
    uint16_t bits_per_pixel = read_u16(dib + 14);
    uint32_t compression = read_u32(dib + 16);
    uint32_t color_count = read_u32(dib + 32);
    if (!color_count && bits_per_pixel <= 8) color_count = 1u << bits_per_pixel;

    size_t offset = header_size + (size_t)color_count * 4;
    if (header_size == 40 && compression == BI_BITFIELDS) offset += 3 * sizeof(uint32_t);
    if (header_size == 40 && compression == BI_ALPHABITFIELDS) offset += 4 * sizeof(uint32_t);
    return offset <= size ? offset : 0;
}

static void read_clipboard_image(clipboard_job* job) {
    UINT png_format = RegisterClipboardFormatW(L"PNG");
    if (!(png_format && IsClipboardFormatAvailable(png_format)) &&
        !IsClipboardFormatAvailable(CF_DIBV5) && !IsClipboardFormatAvailable(CF_DIB)) {
        job->format = CLIPBOARD_EMPTY;
        return;
    }
    HGLOBAL handle = png_format && IsClipboardFormatAvailable(png_format)
        ? (HGLOBAL)GetClipboardData(png_format) : 0;
    bool is_png = handle != 0;
    if (!handle && IsClipboardFormatAvailable(CF_DIBV5)) handle = (HGLOBAL)GetClipboardData(CF_DIBV5);
    if (!handle && IsClipboardFormatAvailable(CF_DIB)) handle = (HGLOBAL)GetClipboardData(CF_DIB);

    const uint8_t* source = handle ? (const uint8_t*)GlobalLock(handle) : 0;
    size_t size = handle ? GlobalSize(handle) : 0;
    if (!source || !size) {
        if (source) GlobalUnlock(handle);
        job->error = "Clipboard does not contain an image";
        return;
    }
    if (is_png) {
        clipboard_copy(job, source, size, CLIPBOARD_BUFFER);
    } else {
        size_t offset = dib_pixel_offset(source, size);
        uint8_t* bitmap = offset && size <= UINT32_MAX - BITMAP_FILE_HEADER_SIZE
            ? clipboard_alloc(job, size + BITMAP_FILE_HEADER_SIZE) : 0;
        if (bitmap) {
            bitmap[0] = 'B';
            bitmap[1] = 'M';
            write_u32(bitmap + 2, (uint32_t)(size + BITMAP_FILE_HEADER_SIZE));
            write_u32(bitmap + 10, (uint32_t)(BITMAP_FILE_HEADER_SIZE + offset));
            copy_bytes(bitmap + BITMAP_FILE_HEADER_SIZE, source, size);
            job->data = bitmap;
            job->length = size + BITMAP_FILE_HEADER_SIZE;
            job->format = CLIPBOARD_BUFFER;
        } else {
            job->error = "Could not create clipboard image buffer";
        }
    }
    GlobalUnlock(handle);
}

static void clipboard_execute(clipboard_job* job) {
    // A real clipboard owner is required for text writes, including under Node
    // without a console. Create and destroy it on the same worker thread.
    HWND owner = 0;
    if (job->operation == CLIPBOARD_WRITE) {
        owner = CreateWindowExW(0, L"STATIC", 0, 0, 0, 0, 0, 0,
            HWND_MESSAGE, 0, GetModuleHandleA(0), 0);
        if (!owner) {
            job->error = "Could not create clipboard owner window";
            return;
        }
    }
    if (!open_clipboard(owner)) {
        if (owner) DestroyWindow(owner);
        job->error = "Could not open clipboard";
        return;
    }
    if (job->operation == CLIPBOARD_WRITE) {
        size_t size = (job->length + 1) * sizeof(uint16_t);
        const bool charged = pi_js_native_memory_reserve(job->memory_owner, size) != 0;
        HGLOBAL handle = charged ? GlobalAlloc(GMEM_MOVEABLE, size) : 0;
        if (!charged) job->allocation_failed = 1;
        void* text = handle ? GlobalLock(handle) : 0;
        bool success = false;
        if (text) {
            copy_bytes(text, job->data, size);
            GlobalUnlock(handle);
            success = EmptyClipboard() && SetClipboardData(CF_UNICODETEXT, handle) != 0;
        }
        if (!success) {
            if (handle) GlobalFree(handle);
            job->error = "Could not set clipboard text";
        }
        // A successful SetClipboardData transfers the allocation to Windows;
        // a failed transfer frees it above. Neither remains this job's memory.
        if (charged) pi_js_native_memory_release(job->memory_owner, size);
    } else if (job->operation == CLIPBOARD_TEXT) {
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) {
            job->format = CLIPBOARD_EMPTY;
        } else {
            HGLOBAL handle = (HGLOBAL)GetClipboardData(CF_UNICODETEXT);
            const uint16_t* text = handle ? GlobalLock(handle) : 0;
            if (text) {
                size_t capacity = GlobalSize(handle) / sizeof(uint16_t);
                size_t length = 0;
                while (length < capacity && text[length]) length++;
                clipboard_copy(job, text, length * sizeof(uint16_t), CLIPBOARD_UTF16);
                GlobalUnlock(handle);
            } else {
                job->error = "Clipboard does not contain text";
            }
        }
    } else {
        read_clipboard_image(job);
    }
    CloseClipboard();
    if (owner) DestroyWindow(owner);
}

PiTuiClipboardJob *pi_tui_win32_clipboard_create(
    void *memory_owner, int operation, const uint16_t *text, size_t length,
    int *failure) {
    if (!failure) return 0;
    *failure = PI_TUI_CREATE_INVALID;
    if (!memory_owner || operation < CLIPBOARD_TEXT || operation > CLIPBOARD_WRITE) return 0;
    if (operation == CLIPBOARD_WRITE && ((!text && length) || length >= SIZE_MAX / sizeof(uint16_t))) {
        *failure = PI_TUI_CREATE_OS_TEXT;
        return 0;
    }
    if (!pi_js_native_memory_reserve(memory_owner, sizeof(clipboard_job))) {
        *failure = PI_TUI_CREATE_NATIVE_BUDGET;
        return 0;
    }
    clipboard_job *job = GlobalAlloc(GPTR, sizeof(*job));
    if (!job) {
        pi_js_native_memory_release(memory_owner, sizeof(*job));
        *failure = PI_TUI_CREATE_OS_JOB;
        return 0;
    }
    pi_js_retain_memory_owner(memory_owner);
    job->memory_owner = memory_owner;
    job->reserved = sizeof(*job);
    atomic_init(&job->done, 0);
    job->operation = (clipboard_operation)operation;
    if (operation == CLIPBOARD_WRITE) {
        job->length = length;
        job->data = clipboard_alloc(job, (length + 1) * sizeof(uint16_t));
        if (!job->data) {
            *failure = job->allocation_failed ? PI_TUI_CREATE_NATIVE_BUDGET : PI_TUI_CREATE_OS_TEXT;
            pi_tui_win32_clipboard_destroy(job);
            return 0;
        }
        // GPTR leaves the trailing UTF16 terminator zero, including empty input.
        copy_bytes(job->data, (const uint8_t *)text, length * sizeof(uint16_t));
    }
    *failure = PI_TUI_CREATE_OK;
    return job;
}
static DWORD WINAPI clipboard_thread(void *data) {
    clipboard_job *job = data;
    clipboard_execute(job);
    atomic_store_explicit(&job->done, 1, memory_order_release);
    return 0;
}
int pi_tui_win32_clipboard_start(PiTuiClipboardJob *job) {
    if (job->thread || atomic_load_explicit(&job->done, memory_order_relaxed)) return 1;
    if (!pi_js_native_memory_reserve(job->memory_owner, PI_TUI_WORKER_STACK_RESERVATION)) {
        job->allocation_failed = 1;
        return -1;
    }
    // Publish the stack charge before CreateThread can execute clipboard_alloc
    // on the worker. Only the worker writes reserved until the owner's join.
    job->reserved += PI_TUI_WORKER_STACK_RESERVATION;
    HANDLE thread = CreateThread(0, PI_TUI_WORKER_STACK_RESERVATION, clipboard_thread,
        job, STACK_SIZE_PARAM_IS_A_RESERVATION, 0);
    if (!thread) {
        job->reserved -= PI_TUI_WORKER_STACK_RESERVATION;
        pi_js_native_memory_release(job->memory_owner, PI_TUI_WORKER_STACK_RESERVATION);
        // The original async queue API reports an ordinary queue failure.
        // This is distinct from the real aggregate stack reservation above.
        return 1;
    }
    job->thread = thread;
    return 0;
}
int pi_tui_win32_clipboard_done(const PiTuiClipboardJob *job) {
    return atomic_load_explicit(&job->done, memory_order_acquire);
}
void pi_tui_win32_clipboard_join(PiTuiClipboardJob *job) {
    if (!job->thread) return;
    if (WaitForSingleObject(job->thread, INFINITE) != WAIT_OBJECT_0) abort();
    if (!CloseHandle(job->thread)) abort();
    job->thread = 0;
    job->reserved -= PI_TUI_WORKER_STACK_RESERVATION;
    pi_js_native_memory_release(job->memory_owner, PI_TUI_WORKER_STACK_RESERVATION);
}
int pi_tui_win32_clipboard_format(const PiTuiClipboardJob *job) { return (int)job->format; }
const void *pi_tui_win32_clipboard_data(const PiTuiClipboardJob *job) { return job->data; }
size_t pi_tui_win32_clipboard_length(const PiTuiClipboardJob *job) { return job->length; }
const char *pi_tui_win32_clipboard_error(const PiTuiClipboardJob *job) { return job->error; }
int pi_tui_win32_clipboard_allocation_failed(const PiTuiClipboardJob *job) { return job->allocation_failed; }
void pi_tui_win32_clipboard_destroy(PiTuiClipboardJob *job) {
    if (!job) return;
    pi_tui_win32_clipboard_join(job);
    void *memory_owner = job->memory_owner;
    size_t reserved = job->reserved;
    if (job->data) GlobalFree(job->data);
    GlobalFree(job);
    pi_js_native_memory_release(memory_owner, reserved);
    pi_js_release_memory_owner(memory_owner);
}
