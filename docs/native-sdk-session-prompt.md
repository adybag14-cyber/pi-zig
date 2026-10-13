# Native ordinary session prompt preflight and queues

Implementation c85e1b5e345052020c636bf36c70b5da8bfe26ce ports the public
prompt body and ordinary session queue methods. It retains live input and
command interception, skill/template expansion, streaming behavior, preflight
callbacks, deferred settlement dispatch and fresh model-runtime authentication
reads. Successful _startRun execution still requires the remaining complete
runtime bindings; no fallback or public factory activation is installed.

The qualified e6220e1 fixture uses 27 genuine upstream factory sessions and
checks actual queued Agent messages, queue events, transformed input, forbidden
queued commands, deferred actions, authentication errors and live callbacks.
An earlier fixture mistakenly set the low-level Agent streaming flag and used
an unsupported setModel method. Its results did not prove the intended queue
paths and are retained as negatives. The corrected capture sets the ordinary
session active-run flag and actual model state, and rejects every unexpected
TypeError. Only the deliberately malformed image iterable compares the engine's
TypeError category instead of engine-specific diagnostic prose.

Windows Debug and ReleaseSafe each passed all 11 selected tests, including
explicit deferred/input-owner collection and all native allocation failures in
the real queue/input/deferred graph. Both use the same 4787 committed input
blobs, verified against the ReleaseSafe snapshot with zero byte drift.
Native source and 19546 compiler file posthashes show zero drift. Runtime guards
remain 120 seconds per test, 10000 ms per host await and 300 seconds outer;
cold compilation has its separate 1320 second bound.

Original source/runtime/Node full posthashes show zero drift over 1945/31064/1774
files. The complete qualification packet is under
verification/sdk-session-prompt-e6220e1-20261013. The private six-platform/mode
candidate checks the same 27 cases and complete test artifact; hosted results
remain pending. This is preflight and queue qualification; successful complete
session runtime and Pi parity still require integration and validation.
