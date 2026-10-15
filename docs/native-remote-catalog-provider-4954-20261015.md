# Actual SDK catalog provider wrappers

`native_sdk_remote_catalog_provider.create(engine, dependencies)` returns an
owned namespace with ordinary constructible `withRemoteCatalog` (length1),
`withPersonalizedCatalog` (length2), the four-hour refresh interval and the shared
mutable `REMOTE_CATALOG_MODEL_TYPES` array. Create the namespace once in the
actual per-engine assembly, preserving the source module's array identity.

The required borrowed dependencies are actual `getModelType`, `isModelType`,
management `fetchWithRetry`, coding-agent `getPiUserAgent(version)`, and the
actual SDK `VERSION` string. Missing bindings fail explicitly. The distinct
AI user-agent helper is not substituted. The management dependency owner is
`native_management_http.create(engine)`; its current source checkpoint is
`d0547d0c32ca6cceb7ca011dfbeea9c2673caaf3`, and its native qualification is separate.

The wrappers copy the provider's enumerable own properties through actual VM
spread operations, retaining symbol/getter/proxy behavior and auth identity.
They retain the original provider for live method and ID reads. User-visible
array filters/maps, Map methods, iterator spreads, URL/searchParams methods,
Date/Number functions and context callbacks remain live VM calls. Model merge
keys retain source model type and NUL-delimited ID semantics and Map ordering.

State changes occur only inside each supplied `publish.update` callback. Stored
remote overlays obey generated timestamps, checked freshness and conditional
etag validation. Status304 moves only freshness;404/501 clear stored freshness
and etag; transient remote failure persists checkedAt before throwing. Personal
catalogs replace saved models, ignore etag/freshness throttling, fall back to
builtins for an empty list, and pass the actual context to the personalizer.

Separate intrinsic async continuations preserve initial publication, fetch,
readCatalog/JSON, personalization and final publication boundaries. Signals are
read again at the original checkpoints. Getter/callback exceptions and rejected
values retain identity. ReadCatalog keeps the header/Date.parse work before its
JSON await and the model parse/Number.isNaN/etag work after it.

The positive native comparison harness accepts the actual assembled namespace
and genuine runtime UA from the production dependency owners. It installs no
fake positive dependencies and is unexecuted. The assembly must also provide
its actual URL, Response, Headers and AbortSignal graph before running the
Source input. No Engine, SDK or shared build file is changed by this checkpoint.

The focused Source64 caller imports the unchanged actual4954 wrapper, management
retry, config and coding-agent UA modules. Its global fetch is a caller-owned
controlled boundary using genuine Node Response/AbortController objects; all
original management retries and attempt-timeout logic execute. Date.now is
explicitly controlled inside the fixture; owner admission/deadlines use real
wall time. No network request or user credential is needed.

Raw actual Node UA is retained in capture metadata. Request rows require the
wrapper's header to equal the actual supplied runtime UA. This permits the
intentional native Zig/QuickJS/OS identity without fabricating Node/Bun metadata
or rewriting the captured Source output.

Controls cover offline/newness restoration, freshness/force/etag, success and
304/404/501/transient statuses, retry exhaustion, all supported model types and
catalog shapes, duplicate precedence, cancellation, personalized cache identity,
live methods, auth identity, proxy/descriptors, deferred updates, async getter/
publication/personalizer failures, URL encoding and callee/getter ordering.

ActualSource capture is pending Root's LIGHT grant. Expected JSON remains absent
until genuine terminal success and complete immutable-input posthash zero.
Native compilation, native runtime, ModelRuntime integration, full Pi and public
activation remain unqualified. This is a source-only prerequisite checkpoint.
