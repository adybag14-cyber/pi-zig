/* Research only. Each operation's setjmp remains in this C stack frame. */
#include <stdint.h>
#include <string.h>
#include "session_api.h"
#include "codec_alloc_guard.h"
#include "photon.h"
int pi_image_guard_resume(PiImageGuard *);
void pi_image_guard_suspend(PiImageGuard *);
void *pi_image_guard_thread_cookie(void);
struct w2c_0x5F__wbindgen__placeholder__0x5F { w2c_pi__photon *module; };
struct PiPhotonSession {
  PiImageGuard guard;
  PiImageAllocator allocator;
  void *owner;
  w2c_pi__photon *module;
  struct w2c_0x5F__wbindgen__placeholder__0x5F imports;
  unsigned char *message;
  size_t message_length;
  unsigned char *pending;
  size_t pending_length;
  int poisoned;
  uint32_t flavor;
};
static WASM_RT_THREAD_LOCAL PiPhotonSession *report_session;
void pi_photon_report_throw(w2c_pi__photon *, u32, u32);
void pi_photon_set_throw_reporter(void (*reporter)(w2c_pi__photon *, u32, u32));
void pi_photon_report_throw(w2c_pi__photon *module, u32 pointer, u32 length) {
  PiPhotonSession *session = report_session;
  wasm_rt_memory_t *memory = w2c_pi__photon_memory(module);
  if (!session || session->module != module || pointer > memory->size || length > memory->size - pointer)
    pi_image_trap(WASM_RT_TRAP_OOB);
  session->message = pi_image_malloc(length ? length : 1);
  memcpy(session->message, memory->data + pointer, length);
  session->message_length = length;
}
static void copy_input(PiPhotonSession *session, u32 pointer, const unsigned char *input, size_t length) {
  wasm_rt_memory_t *memory = w2c_pi__photon_memory(session->module);
  if (pointer > memory->size || length > memory->size - pointer) pi_image_trap(WASM_RT_TRAP_OOB);
  memcpy(memory->data + pointer, input, length);
}
PiSessionCreated pi_session_create(PiImageAllocator allocator, size_t memory_limit) {
  PiSessionCreated result = {0};
  if (!allocator.allocate || !allocator.release) { result.status = 3; return result; }
  PiPhotonSession *session = allocator.allocate(allocator.context, sizeof *session, _Alignof(PiPhotonSession));
  if (!session) { result.status = 1; return result; }
  memset(session,0,sizeof *session);
  session->allocator = allocator;
  session->flavor = 34;
  session->owner = pi_image_guard_thread_cookie();
  if (!pi_image_guard_enter(&session->guard, allocator, memory_limit)) {
    allocator.release(allocator.context,session,sizeof *session,_Alignof(PiPhotonSession));
    result.status = 4; return result;
  }
  pi_photon_set_throw_reporter(pi_photon_report_throw);
  report_session = session;
  if (setjmp(session->guard.target) == 0) {
    wasm_rt_init();
    session->module = pi_image_calloc(1,sizeof *session->module);
    session->imports.module = session->module;
    wasm2c_pi__photon_instantiate(session->module,&session->imports);
    w2c_pi__photon_0x5F_wbindgen_start(session->module);
  } else result.status = session->guard.allocation_failed ? 1 : 2;
  report_session = NULL;
  pi_photon_set_throw_reporter(NULL);
  if (result.status) {
    pi_image_guard_leave(&session->guard);
    wasm_rt_free();
    allocator.release(allocator.context,session,sizeof *session,_Alignof(PiPhotonSession));
  } else {
    pi_image_guard_suspend(&session->guard);
    result.session = session;
  }
  return result;
}
PiSessionReply pi_session_call(PiPhotonSession *session, enum PiSessionOperation operation,
  uint32_t image, const unsigned char *input, size_t input_length,
  uint32_t width, uint32_t height, uint32_t quality, size_t output_limit) {
  PiSessionReply result = {0};
  if (!session || session->flavor != 34 || session->owner != pi_image_guard_thread_cookie()) { result.status = 5; return result; }
  if (session->poisoned && operation != PI_SESSION_FREE) { result.status = 6; return result; }
  if (operation < PI_SESSION_RGBA || operation > PI_SESSION_FLIP_V ||
      ((operation == PI_SESSION_RGBA || operation == PI_SESSION_DECODE) && (!input || !input_length || input_length > UINT32_MAX)) ||
      (operation == PI_SESSION_RGBA && (!width || !height || (uint64_t)width * height > UINT32_MAX / 4 ||
          (uint64_t)width * height * 4 != input_length))) { result.status = 3; return result; }
  if (!pi_image_guard_resume(&session->guard)) { result.status = 4; return result; }
  pi_photon_set_throw_reporter(pi_photon_report_throw);
  report_session = session;
  if (session->message) pi_image_free(session->message);
  session->message = NULL; session->message_length = 0;
  if (setjmp(session->guard.target) == 0) {
    u32 handle = image;
    u32 actual_width = 0, actual_height = 0;
    struct wasm_multi_ii bytes = {0};
    if (operation == PI_SESSION_RGBA || operation == PI_SESSION_DECODE) {
      u32 pointer = w2c_pi__photon_0x5F_wbindgen_malloc(session->module,(u32)input_length,1);
      copy_input(session,pointer,input,input_length);
      handle = operation == PI_SESSION_RGBA
        ? w2c_pi__photon_photonimage_new(session->module,pointer,(u32)input_length,width,height)
        : w2c_pi__photon_photonimage_new_from_byteslice(session->module,pointer,(u32)input_length);
    } else if (operation == PI_SESSION_RESIZE)
      handle = w2c_pi__photon_resize(session->module,image,width,height,5);
    else if (operation == PI_SESSION_FREE)
      w2c_pi__photon_0x5F_wbg_photonimage_free(session->module,image,0);
    else if (operation == PI_SESSION_FLIP_H)
      w2c_pi__photon_fliph(session->module,image);
    else if (operation == PI_SESSION_FLIP_V)
      w2c_pi__photon_flipv(session->module,image);
    if (operation != PI_SESSION_FREE) {
      actual_width = w2c_pi__photon_photonimage_get_width(session->module,handle);
      actual_height = w2c_pi__photon_photonimage_get_height(session->module,handle);
    }
    if (operation == PI_SESSION_PIXELS) bytes = w2c_pi__photon_photonimage_get_raw_pixels(session->module,handle);
    else if (operation == PI_SESSION_PNG) bytes = w2c_pi__photon_photonimage_get_bytes(session->module,handle);
    else if (operation == PI_SESSION_JPEG) bytes = w2c_pi__photon_photonimage_get_bytes_jpeg(session->module,handle,quality);
    if (operation == PI_SESSION_PIXELS || operation == PI_SESSION_PNG || operation == PI_SESSION_JPEG) {
      wasm_rt_memory_t *memory = w2c_pi__photon_memory(session->module);
      if (bytes.i0 > memory->size || bytes.i1 > memory->size - bytes.i0 || bytes.i1 > output_limit)
        pi_image_trap(WASM_RT_TRAP_OOB);
      if (bytes.i1) {
        session->pending = session->allocator.allocate(session->allocator.context,bytes.i1,1);
        if (!session->pending) pi_image_abort();
        session->pending_length = bytes.i1;
        memcpy(session->pending,memory->data + bytes.i0,bytes.i1);
      }
      w2c_pi__photon_0x5F_wbindgen_free(session->module,bytes.i0,bytes.i1,1);
      result.bytes = session->pending; result.length = bytes.i1;
      session->pending = NULL; session->pending_length = 0;
    }
    result.image = handle; result.width = actual_width; result.height = actual_height;
  } else {
    session->poisoned = 1;
    result.status = session->guard.allocation_failed ? 1 : 2;
    if (session->pending) {
      session->allocator.release(session->allocator.context,session->pending,session->pending_length,1);
      session->pending = NULL; session->pending_length = 0;
    }
    if (result.status == 2 && session->message_length) {
      result.message = session->allocator.allocate(session->allocator.context,session->message_length,1);
      if (!result.message) result.status = 1;
      else {
        memcpy(result.message,session->message,session->message_length);
        result.message_length = session->message_length;
      }
    }
  }
  report_session = NULL;
  pi_photon_set_throw_reporter(NULL);
  pi_image_guard_suspend(&session->guard);
  return result;
}
int pi_session_destroy(PiPhotonSession *session) {
  if (!session || session->flavor != 34 || session->owner != pi_image_guard_thread_cookie()) return 5;
  if (!pi_image_guard_resume(&session->guard)) return 4;
  PiImageAllocator allocator = session->allocator;
  pi_image_guard_leave(&session->guard);
  wasm_rt_free();
  allocator.release(allocator.context,session,sizeof *session,_Alignof(PiPhotonSession));
  return 0;
}
