// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
#ifndef PI_NODE_OPTIONS_ENVIRONMENT_H
#define PI_NODE_OPTIONS_ENVIRONMENT_H
#ifdef __cplusplus
extern "C" {
#endif
/* Actual current-process SafeGetenv admission. No environment value or VM owner
 * is read here; the caller then reads its original native environment store. */
int pi_node_options_environment_allowed(void);
#ifdef __cplusplus
}
#endif
#endif
