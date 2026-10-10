/* External native codec boundary draft; not yet installed as a repository API. */
#ifndef PI_PHOTON_BROWSER_NATIVE_H
#define PI_PHOTON_BROWSER_NATIVE_H
#include "photon_native.h"

PiPhotonResult pi_photon_browser_transform(PiImageAllocator allocator,
  const unsigned char *input, size_t input_length, int input_is_rgba,
  uint32_t width, uint32_t height, uint32_t target_width, uint32_t target_height,
  enum PiPhotonFormat format, uint32_t quality, size_t memory_limit,
  size_t output_limit);
#endif
