/* External unqualified research: private allocation/trap boundary. */
#ifndef PI_IMAGE_ALLOC_GUARD_H
#define PI_IMAGE_ALLOC_GUARD_H
#include "photon_allocator.h"
#include <setjmp.h>
#include "wasm-rt.h"

typedef struct PiImageAllocation PiImageAllocation;
typedef struct {
  jmp_buf target;
  PiImageAllocator allocator;
  PiImageAllocation *allocations;
  size_t live_bytes;
  size_t max_bytes;
  int allocation_failed;
  wasm_rt_trap_t trap;
  uint32_t saved_call_depth;
} PiImageGuard;

/* One protected C operation per thread. No JavaScript callbacks occur inside
 * the boundary. Allocator callbacks return before any longjmp is performed. */
int pi_image_guard_enter(PiImageGuard *guard, PiImageAllocator allocator,
                         size_t max_bytes);
void pi_image_guard_leave(PiImageGuard *guard);
void *pi_image_malloc(size_t length);
void *pi_image_calloc(size_t count, size_t length);
void *pi_image_realloc(void *pointer, size_t length);
void pi_image_free(void *pointer);
_Noreturn void pi_image_abort(void);
_Noreturn void pi_image_trap(wasm_rt_trap_t trap);
#endif
