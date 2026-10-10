/* External unqualified research; not yet a repository dependency. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "codec_alloc_guard.h"
#include "wasm-rt-impl.h"

struct PiImageAllocation {
  PiImageAllocation *previous;
  PiImageAllocation *next;
  PiImageGuard *guard;
  PiImageAllocator owner;
  size_t length;
  max_align_t alignment;
};

static WASM_RT_THREAD_LOCAL PiImageGuard *pi_image_active_guard;

int pi_image_guard_enter(PiImageGuard *guard, PiImageAllocator allocator,
                         size_t max_bytes) {
  if (pi_image_active_guard || !allocator.allocate || !allocator.release)
    return 0;
  memset(guard, 0, sizeof *guard);
  guard->allocator = allocator;
  guard->max_bytes = max_bytes;
#if WASM_RT_STACK_DEPTH_COUNT
  guard->saved_call_depth = wasm_rt_call_stack_depth;
  wasm_rt_saved_call_stack_depth = wasm_rt_call_stack_depth;
#endif
  pi_image_active_guard = guard;
  return 1;
}

_Noreturn void pi_image_trap(wasm_rt_trap_t trap) {
  PiImageGuard *guard = pi_image_active_guard;
  /* This private entry is reachable only during a protected codec operation.
   * A call without its C guard is an embedding programming error. */
  if (!guard) abort();
  guard->trap = trap;
#if WASM_RT_STACK_DEPTH_COUNT
  wasm_rt_call_stack_depth = guard->saved_call_depth;
#endif
  longjmp(guard->target, 1);
}

_Noreturn void pi_image_abort(void) {
  PiImageGuard *guard = pi_image_active_guard;
  if (guard) guard->allocation_failed = 1;
  pi_image_trap(WASM_RT_TRAP_UNREACHABLE);
}

void *pi_image_malloc(size_t length) {
  PiImageGuard *guard = pi_image_active_guard;
  if (!guard) return NULL;
  if (length > SIZE_MAX - sizeof(PiImageAllocation)) pi_image_abort();
  size_t total = sizeof(PiImageAllocation) + length;
  if (total > SIZE_MAX - guard->live_bytes) pi_image_abort();
  if (guard->max_bytes && (guard->live_bytes > guard->max_bytes ||
                          total > guard->max_bytes - guard->live_bytes))
    pi_image_abort();
  /* No trap crosses the callback: first obtain its result, then act on it. */
  PiImageAllocation *block = guard->allocator.allocate(
      guard->allocator.context, total, _Alignof(PiImageAllocation));
  if (!block) pi_image_abort();
  block->previous = NULL;
  block->next = guard->allocations;
  block->guard = guard;
  block->owner = guard->allocator;
  block->length = length;
  if (block->next) block->next->previous = block;
  guard->allocations = block;
  guard->live_bytes += total;
  return block + 1;
}

void *pi_image_calloc(size_t count, size_t length) {
  if (length && count > SIZE_MAX / length) pi_image_abort();
  size_t bytes = count * length;
  void *pointer = pi_image_malloc(bytes);
  memset(pointer, 0, bytes);
  return pointer;
}

void pi_image_free(void *pointer) {
  if (!pointer) return;
  PiImageAllocation *block = (PiImageAllocation *)pointer - 1;
  PiImageGuard *guard = block->guard;
  size_t total = sizeof *block + block->length;
  if (block->previous) block->previous->next = block->next;
  else guard->allocations = block->next;
  if (block->next) block->next->previous = block->previous;
  guard->live_bytes -= total;
  PiImageAllocator owner = block->owner;
  owner.release(owner.context, block, total, _Alignof(PiImageAllocation));
}

void *pi_image_realloc(void *pointer, size_t length) {
  if (!pointer) return pi_image_malloc(length);
  if (!length) {
    pi_image_free(pointer);
    return NULL;
  }
  PiImageAllocation *old = (PiImageAllocation *)pointer - 1;
  void *replacement = pi_image_malloc(length);
  memcpy(replacement, pointer, old->length < length ? old->length : length);
  pi_image_free(pointer);
  return replacement;
}

void pi_image_guard_leave(PiImageGuard *guard) {
  if (pi_image_active_guard != guard) abort();
  while (guard->allocations) pi_image_free(guard->allocations + 1);
#if WASM_RT_STACK_DEPTH_COUNT
  wasm_rt_call_stack_depth = guard->saved_call_depth;
#endif
  pi_image_active_guard = NULL;
}
