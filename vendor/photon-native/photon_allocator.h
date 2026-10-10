/* Public allocator ABI; all trap/runtime internals remain private to C. */
#ifndef PI_PHOTON_ALLOCATOR_H
#define PI_PHOTON_ALLOCATOR_H
#include <stddef.h>
#include <stdint.h>
typedef struct {
  void *context;
  void *(*allocate)(void *, size_t, size_t);
  void (*release)(void *, void *, size_t, size_t);
} PiImageAllocator;
#endif
