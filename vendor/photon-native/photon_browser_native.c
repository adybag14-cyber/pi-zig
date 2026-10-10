/* Protected C call: no setjmp or longjmp frame ever belongs to Zig. */
#include <string.h>
#include <stdint.h>
#include "photon_browser_native.h"
#include "codec_alloc_guard.h"
#include "photon_browser.h"
struct w2c_wbg { w2c_pi__photon__browser *module; };

PiPhotonResult pi_photon_browser_transform(PiImageAllocator allocator,
  const unsigned char *input, size_t input_length, int input_is_rgba,
  uint32_t width, uint32_t height, uint32_t target_width, uint32_t target_height,
  enum PiPhotonFormat format, uint32_t quality, size_t memory_limit,
  size_t output_limit) {
  PiPhotonResult result = {0};
  if (!allocator.allocate || !allocator.release || !input || !input_length ||
      input_length > UINT32_MAX || format > PI_PHOTON_JPEG || format < PI_PHOTON_RGBA ||
      (!!target_width != !!target_height) ||
      (input_is_rgba && (!width || !height || (uint64_t)width * height > UINT32_MAX / 4 ||
                        (uint64_t)width * height * 4 != input_length))) {
    result.status = 3;
    return result;
  }
  PiImageGuard *guard = allocator.allocate(allocator.context, sizeof *guard,
                                           _Alignof(PiImageGuard));
  if (!guard) { result.status = 1; return result; }
  if (!pi_image_guard_enter(guard, allocator, memory_limit)) {
    allocator.release(allocator.context, guard, sizeof *guard, _Alignof(PiImageGuard));
    result.status = 4;
    return result;
  }
  if (setjmp(guard->target) == 0) {
    wasm_rt_init();
    w2c_pi__photon__browser *module = pi_image_calloc(1, sizeof *module);
    struct w2c_wbg imports = {module};
    wasm2c_pi__photon__browser_instantiate(module, &imports);
    w2c_pi__photon__browser_0x5F_wbindgen_start(module);
    u32 pointer = w2c_pi__photon__browser_0x5F_wbindgen_malloc(module, (u32)input_length, 1);
    wasm_rt_memory_t *memory = w2c_pi__photon__browser_memory(module);
    if (pointer > memory->size || input_length > memory->size - pointer)
      pi_image_trap(WASM_RT_TRAP_OOB);
    memcpy(memory->data + pointer, input, input_length);
    u32 image = input_is_rgba
      ? w2c_pi__photon__browser_photonimage_new(module, pointer, (u32)input_length, width, height)
      : w2c_pi__photon__browser_photonimage_new_from_byteslice(module, pointer, (u32)input_length);
    if (target_width) image = w2c_pi__photon__browser_resize(module, image, target_width, target_height, 5);
    u32 out_width = w2c_pi__photon__browser_photonimage_get_width(module, image);
    u32 out_height = w2c_pi__photon__browser_photonimage_get_height(module, image);
    struct wasm_multi_ii bytes = format == PI_PHOTON_RGBA
      ? w2c_pi__photon__browser_photonimage_get_raw_pixels(module, image)
      : format == PI_PHOTON_PNG ? w2c_pi__photon__browser_photonimage_get_bytes(module, image)
      : w2c_pi__photon__browser_photonimage_get_bytes_jpeg(module, image, quality);
    memory = w2c_pi__photon__browser_memory(module);
    if (!bytes.i1 || bytes.i0 > memory->size || bytes.i1 > memory->size - bytes.i0 ||
        bytes.i1 > output_limit) pi_image_trap(WASM_RT_TRAP_OOB);
    unsigned char *owned = allocator.allocate(allocator.context, bytes.i1, 1);
    if (!owned) pi_image_abort();
    memcpy(owned, memory->data + bytes.i0, bytes.i1);
    /* No trapping operation follows these writes. The module's entire tracked
       allocation graph is reclaimed below; only the copied output escapes. */
    result.data = owned;
    result.length = bytes.i1;
    result.width = out_width;
    result.height = out_height;
  } else result.status = guard->allocation_failed ? 1 : 2;
  pi_image_guard_leave(guard);
  wasm_rt_free();
  allocator.release(allocator.context, guard, sizeof *guard, _Alignof(PiImageGuard));
  return result;
}
