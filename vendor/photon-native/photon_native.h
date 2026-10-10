/* External native codec boundary draft; not yet installed as a repository API. */
#ifndef PI_PHOTON_NATIVE_H
#define PI_PHOTON_NATIVE_H
#include "codec_alloc_guard.h"
enum PiPhotonFormat { PI_PHOTON_RGBA = 0, PI_PHOTON_PNG = 1, PI_PHOTON_JPEG = 2 };
typedef struct {
  int status; /* 0 success, 1 allocation failure, 2 codec trap, 3 invalid input, 4 nested guard */
  unsigned char *data; /* Caller allocator owns length bytes, alignment 1. */
  size_t length;
  uint32_t width, height;
} PiPhotonResult;
PiPhotonResult pi_photon_transform(PiImageAllocator allocator,
  const unsigned char *input, size_t input_length, int input_is_rgba,
  uint32_t width, uint32_t height, uint32_t target_width, uint32_t target_height,
  enum PiPhotonFormat format, uint32_t quality, size_t memory_limit,
  size_t output_limit);
#endif
