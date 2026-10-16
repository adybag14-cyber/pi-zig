# Unexecuted native callback controls for six-file guards

These are concrete qualification cases to author/run only under Root's later native admission, after accepted C composition. This document is not a test result. No tag, raw identity, cleanup count, allocator or GC validation is claimed for the new graph. The existing Root AF/tag tests qualify their own candidate/helper only.

Use the actual factory/private SDK route and actual native_node_function callbacks as caller inputs. A fresh callback OutOfMemory follows native_node_function.fail to Engine.throwNativeOutOfMemory, creating a private tagged reason; retain that exact value from the test Engine's native_allocation_exception before observing the guard. Do not forge a name/property as native authority. For historical cases, create/retain the tagged value before the tested boundary, then have the callback throw that exact retained value without incrementing generation. Lookalikes are ordinary guest Error values with copied names/messages/public properties and private tag0. Already-uncatchable reasons are marked by the native fixture and must escape regardless of tag age. Direct OutOfMemory error unions have no preexisting reason to preserve; their separately constructed primitive reason must be fatal.

| Selected caller seam | Ordinary behavior and cleanup observation | Fresh/uncatchable behavior |
| --- | --- | --- |
| Factory setup call (e.g. owned header/environment getter) | Source error stream uses original guest reason | Exact captured reason escapes; no normal error normalization |
| Factory fulfilled advance hook callback | Body failure closes once; step getter failure does not close | Fatal callback does not enter ordinary failError/close mapping |
| Factory decoder.fail/normalization callback | Ordinary normalization failure follows existing API rejection path | Exact captured reason escapes, without nativeAllocationError allocating another OOM |
| Constructor capture env/value getter | Ordinary raw historical/lookalike throw retains original reason | Constructor wrapper rethrows exact fresh reason |
| sdk_headers build/buildMixed coercion or live iterator callback | Existing ordinary validation and original throw survive | Both wrappers preserve the exact fresh reason through nesting |
| SDK dispatch callback in a normal property/call operation | Ordinary failure becomes the source AF throw | Guard executes before body.failure; exact reason remains captured |
| _callApiKey callback | Ordinary source keyFailure behavior remains | Fresh reason skips ordinary OpenAIError/cast conversion |
| Captured fetch's live call getter/call | Ordinary fetch error/cause and existing finally behavior remain | Fresh reason skips ordinary body.failure conversion |
| castForeign, JSON.stringify fallback, response JSON.parse | Ordinary failures follow retained discard/fallback behavior; cancellation/interrupt rules remain Root's | Exact guard executes before shared discard can classify to OutOfMemory |
| Reader synchronous read throw | Catch releaseLock once; cleanup failure replaces read reason | Fresh read failure escapes before catch cleanup |
| Reader fulfilled done getter throw | Catch releaseLock once; successful cleanup retains raw getter reason | Fresh done failure escapes before catch cleanup |
| Reader normal done=true releaseLock throw | Catch calls releaseLock a second time; second ordinary failure replaces first | Fresh first release failure escapes without a second call |
| Reader catch releaseLock failure | Ordinary cleanup reason replaces saved reason; saved owned Action is freed once | Exact cleanup reason escapes; no retained original reason leak |
| Reader rejected read Await | Historical/lookalike rejection calls release once and remains original if cleanup succeeds | Existing explicit read boundary recognizes exact fresh rejected reason |
| Reader return cancel callback | Ordinary cancel throw skips release and Await | Fresh reason escapes exactly |
| Reader return release callback | Ordinary release throw prevents reaching cancel Await | Fresh reason escapes exactly; no added Await |

For every seam test fresh captured tag, already-uncatchable, historical tag and lookalike separately. Inspect exact C/JS strict identity at the host exception surface, captured_exception and native tag, not just error name/message. On ordinary cases inspect the actual promise rejection or public event/result surface appropriate to that function; retain complete callback/getter traces. Check next/getter/read/release/cancel call counts and no duplicate close. Repeat meaningful fresh/historical cases across the existing unsigned u64 wrap rule using the unchanged helper, then run GC and the admitted allocation sweep for the composed graph. No implementation should modify a user lookalike or clear an already-uncatchable reason to force a pass.

`readable-callers.mjs` separately prepares12 genuine shim caller cases and3 actual public API/custom-fetch/getReader cases with ordinary raw identity and cleanup order assertions. Both sets are unexecuted, contain no shim implementation, and create no expected Source fixture. The full-route byte input deliberately omits [DONE], forcing the second reader result into the tested completion branch.

Retained helpers/generators outside these six files have their own outstanding failure-boundary questions. In particular existing native_ai_openai_sdk_stream catch paths are not repaired or requalified by this packet. They must remain explicit follow-up work under their owners, rather than expanding this source intake into unrelated/shared changes or claiming full58 fatal qualification.
