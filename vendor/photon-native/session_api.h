/* External session prototype. Public boundary excludes generated/runtime headers. */
#ifndef PI_PHOTON_SESSION_RESEARCH_H
#define PI_PHOTON_SESSION_RESEARCH_H
#include "photon_allocator.h"
typedef struct PiPhotonSession PiPhotonSession;
enum PiSessionOperation { PI_SESSION_RGBA, PI_SESSION_DECODE, PI_SESSION_RESIZE,
  PI_SESSION_PIXELS, PI_SESSION_PNG, PI_SESSION_JPEG, PI_SESSION_FREE,
  PI_SESSION_FLIP_H, PI_SESSION_FLIP_V };
typedef struct {
  int status;
  uint32_t image, width, height;
  unsigned char *bytes;
  size_t length;
  unsigned char *message;
  size_t message_length;
} PiSessionReply;
typedef struct { PiPhotonSession *session; int status; } PiSessionCreated;
PiSessionCreated pi_session_create(PiImageAllocator, size_t memory_limit);
PiSessionReply pi_session_call(PiPhotonSession *, enum PiSessionOperation,
  uint32_t image, const unsigned char *input, size_t input_length,
  uint32_t width, uint32_t height, uint32_t quality, size_t output_limit);
/* Returns invalid-state on cross-thread use; caller must close on its owner. */
int pi_session_destroy(PiPhotonSession *);
#endif
