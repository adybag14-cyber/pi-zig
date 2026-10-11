#ifndef PI_PHOTON_BROWSER_SESSION_RESEARCH_H
#define PI_PHOTON_BROWSER_SESSION_RESEARCH_H
#include "session_api.h"
PiSessionCreated pi_browser_session_create(PiImageAllocator, size_t memory_limit);
PiSessionReply pi_browser_session_call(PiPhotonSession *, enum PiSessionOperation,
  uint32_t image, const unsigned char *input, size_t input_length,
  uint32_t width, uint32_t height, uint32_t quality, size_t output_limit);
int pi_browser_session_destroy(PiPhotonSession *);
#endif
