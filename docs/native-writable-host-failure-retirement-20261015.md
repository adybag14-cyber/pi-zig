# Writable host-failure retirement seam

This source-only successor starts at the unchanged qualified WritableStream checkpoint `6fce4363495bc56b7b1c1fc572aab7c318456f73`. It adds only `retireAfterHostFailureNative(engine, actual_stream, reason)!void` over the existing genuine native brand check and `failAll` retirement primitive. Closed streams are left closed.

For a valid actual stream, retirement retains the stream and the original reason by direct VM reference duplication, then uses the existing direct capability-settling implementation. It creates no host Scope roots, replacement reason, signal, writer, or class. Queued/in-flight writes, closes, aborts, readiness, and closed capabilities are retired using their already-retained VM resolving functions. The supplied error object and any error tags retain identity. The explicit reason root also protects against cleanup dropping the error's previous owning edge.

The qualified Source56 proof remains unchanged and does not qualify this new wrapper. A meaningful pending-pipe/GPA failure gate must exercise the new seam, actual retained promises, and lock cleanup before it can be accepted as qualified. No Source or native jobs were launched for this successor. Pinned Zig 0.16.0 formatting and AST checks pass.
