# Request Response BodyMixin source phase

Separate continuation from immutable Headers checkpoint `2d2c5af90a300a08ec1edafeaeaf28804c5f8357`. The new observer program uses actual Node24 global Request/Response/ReadableStream/Blob/File/FormData/AbortSignal constructors. No expected values are authored. Capture and native comparison are pending resource grants.

The observer records genuine constructor/prototype descriptors, coercion/errors, headers ownership, SDK-used status/ok/statusText/body/text/json/arrayBuffer/clone behavior, bytes/blob/formData, body locking/disturbance/cancellation, signal following, stream chunk/error identity and actual GC. Descriptor object values are observed as actual object type/tag to avoid invoking enumerable prototype getters during JSON serialization. FormData's random generated boundary is observed through the actual multipart prefix and parsed original fields/files; no fabricated boundary is substituted.

Env owns the shared public ReadableStream implementation (constructor/getReader/cancel/tee). Native Request/Response must depend on that provider contract rather than implement another stream. Native Blob/File/FormData dependencies are absent at the baseline and remain explicit work. Codecs owns transport and the separate internal raw header pair export; the real worker retains duplicate wire pairs, so set-cookie boundaries must not be recovered by splitting comma-combined ready records.

No native Request/Response, BodyMixin, global fetch, stream dependency, full allocation ownership or profile matrix is qualified by this source-only phase. Actual QuickJS/OS runtime diagnostic identity must stay visible when it differs from Node diagnostics; this observer preserves complete genuine Node errors for later explicit assessment.
