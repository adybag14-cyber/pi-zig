# Image and classifier native facade audit

Authority is immutable Pi Source
`5ab7fe74c400097b386662205cd93900695b8a71`. The additional one-shot API set is:

| API | Operation | Built-in catalog records | Native implementation |
| --- | --- | ---: | --- |
| `openrouter-images` | `generateImages` | 59 | `native_ai_images_factory.create` |
| `typesafe-system-one` | `classify` | 36 | `native_ai_classifier_factory.create(.typesafe)` |
| `cloudflare-workers-ai-system-one` | `classify` | 3 | `native_ai_classifier_factory.create(.cloudflare)` |
| `openai-decisions` | `classify` | 1 | `native_ai_classifier_factory.create(.decisions)` |
| `llama-cpp-classify` | `classify` | 0; custom provider API | `native_ai_llama_classifier_factory.create` |

The counts come from reading the original provider data JSON by model type and
API. Chat records require the catalog generator's flattening and deduplication;
this audit does not substitute raw chat record counts for generated totals.

Existing `src/ai/openrouter_images.zig`, `classifier.zig`, `llama_classifier.zig`
and `openai_decisions.zig` are internal native struct/JSON clients. They do not
supply the actual public JSValue provider facades, awaited guest callbacks,
mutable value semantics and promise cache boundaries. Those clients are
preserved. `native_models_typed.zig` already installs the actual Models
`generateImages`/`classify` methods and auth application. Its implementation is
preserved; the central Models/provider owner wires the new operation maps.

The new facades use live VM values and directly linked C ABI functions. All
network calls use the existing owned HTTP worker; no worker was forked.
Classifier POSTs retain body mode and reuse the original native `retryProviderRequest` helper
and genuine branded Headers. The one-shot operation codecs retain the different
protocols: System One `bool` to `noul`, Cloudflare direct/completed envelopes,
Decisions named answer arrays and refusals, and OpenRouter chat-completions image
data URLs. Usage is installed before answer validation so malformed billed
answers retain usage. Decisions excludes HTTP 504 from retries.

The llama.cpp classifier retains concurrent label/template work, per-server and
model cached token promises, rejection eviction, newline-token fallback, token
uniqueness checks, ordered 256/4096/32768 readout escalation, and the public
rendering/probability/confidence/answer helpers. Questions remain sequential.

OpenRouter image requests use the pinned OpenAI 6.40 functional body/error/header
policy. Native request diagnostics identify the actual Zig version, directly
linked QuickJS version and target OS/architecture. Node 24 and JavaScript SDK
runtime/package identities are not fabricated. The prepared control records
retain original raw headers separately and compare functional headers strictly;
explicit caller overrides remain part of the strict comparison.

`ai-one-shot-5ab.input.txt` prepares 80 controls across all five APIs and their
public helpers, including auth, hooks, replacement payloads, retries, malformed
billed answers, Cloudflare envelopes, Decisions 504/refusal/image inputs, llama
readout escalation, token fallback/duplicates, cache reuse and label identity.
The baseline, retained-GC and pure-helper exhaustive-allocation tests are
prepared. The pure-helper allocation scope excludes network workers and async
transport callbacks; those require separate qualification.

The separate image registry and global image dispatcher are also prepared with
20 controls for live provider identity, captured getter order, synchronous
wrapper errors, async dispatcher errors, unbound implementation calls, method
receivers, strict API matching and explicit built-in restoration. Registration
uses the actual provided image implementation. Static legacy image catalog
queries and shared catalog object identities belong to the central Models
assembler. Source lazy-module loading and its public adapter still need their
separate native implementation; direct registration does not qualify those
boundaries.

The independent shared body collector is a further source-only checkpoint. Its
explicit native budget and pending large-body qualification are described in
`native-body-collect-source-20261015.md`. The native image JSON request path uses
its byte-event mode for successful and unsuccessful HTTP statuses. This replaces
the old 512 KiB aggregation limit with the documented explicit Engine-grounded
budget. Supplied guest fetch responses retain their actual `json()`/`text()`
methods and ownership. Large real-wire image and limit controls remain pending.

This follow-up is source-only. No original expected JSON has been fabricated.
Source capture, native compilation, runtime, broader timeout/abort controls,
complete provider registration and full factory/application qualification are
pending the respective coordinated grants and dependency intake. Nothing in
this audit qualifies the complete Pi application or activates a release.
