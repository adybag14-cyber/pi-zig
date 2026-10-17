# Additional rejected-DATA callers at exact c720 base

The following are concrete source callsites, not claims that the entire native
runtime has been audited. They remain unchanged in this bounded packet. Each
rejected-input classifier needs the same actual-event/DATA distinction while
preserving its particular Source catch, retry, cleanup and finally behavior.

| Product | Exact c720 callsites | Consequence to inspect/correct |
| --- | --- | --- |
| native_ai_openai_factory.zig | 101–105, including `.closed` closeGeneration | Rejected DATA may skip Source close/error handling. |
| native_ai_openai_sdk_readable.zig | 56–61; 112–116 | DATA classification can skip actual releaseLock cleanup or become fatal. |
| native_ai_openai_sdk_request.zig | 60–63; 199–206 | Both AF rejected input and ordinary Promise.catch argument are DATA. |
| native_ai_provider_retry_request.zig | 28–35 | Rejection may bypass actual retry/Source error policy. |
| native_jiti_import.zig | 60–69 | Invalid fresh-tag classification followed by explicit input flag clearing; neither establishes a new event. |
| native_jiti_require.zig | native_fallback 241–248 | Rejected Promise.catch argument must enter actual fallback without private-history inference. |
| native_sdk_event_bus.zig | 73–77 | Rejection can bypass actual Source catch. |
| native_sdk_extension_initializer.zig | 123–131 | Pending checks are present, but generation inference and DATA flag clearing remain invalid. |
| native_sdk_factory_production.zig | 123–131 | Explicit input-bit throw and private inference both promote DATA. |
| native_sdk_session_hook_helpers.zig | 56–64 | Both generation classification and input-bit throw can bypass before-tool Source catch. |
| native_sdk_session_settled.zig | 87–91 | Generation/bit inference bypasses normal advance/finally. |
| native_ai_models_refresh_publication.zig + methods.zig | nativeReason 12–19; rejected callsites 160,203,268 | Private history changes refresh abort/provider/cache rejection handling even without marking a bit. |
| native_cache_warmer_refresh.zig | 75 | Rejected DATA classified to direct OutOfMemory. |
| native_ai_anthropic_events.zig | 161,168 and freshAllocation | Generator rejected DATA changes close precedence and Source error wrapping; audit separately against generator ABI. |

Do not remove synchronous operation-boundary checks indiscriminately. For
example readable.releaseAfterFailure, client_options.capture, sdk_headers.build,
Jiti transform catches and lstat callback exits inspect a captured *failed
operation*, not a settled rejection argument. Their freshness/ownership and
actual event checks require their own producer semantics.

There are inherited completion exits returning `.thrown` directly throughout
Models/Agent/generators. They also depend on the C3 ordinary throw-completion
frontier described in README. A tag-only grep cannot prove their full behavior.

The newly authored CF transaction is owned by Body, outside this c720 snapshot.
Root and Body were notified of the same completion-DATA rule. No change to that
unit is silently included here.
