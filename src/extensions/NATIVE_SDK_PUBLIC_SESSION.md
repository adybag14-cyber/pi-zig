# Native AgentSession mutation parity

Source authority is `6fb2e7815167e6b19006fc526d1a5d0f5f998787` in the actual upstream SDK, AgentSession and extension runner. The parent audit confirms these paths remain unchanged through `eba849739511223c51a62bbd7e3f1c00f99fb1d0`.

This candidate follows the separately qualified ResourceLoader owner20 and constructor binding22 packets, plus the SDK event/UI continuation candidate. `native_sdk_resource_owners.retainCaller` verifies actual Group membership, loader ownership, actual AgentSession, model-runtime lease, registry and manager before SDK Pi mutation. Constructor-bound calls outside events use the same private lease, with stale event admission checked before default lookup. No public JSON context or Main action queue grants SDK admission.

The thinking implementation filters actual observable model thinkingLevelMap properties, clamps upward then downward in Source order, writes the effective level, persists only the requested level when requested, and appends a transcript entry and notifications only when the effective level changes. Cycling returns the selected level and does not operate on a model without reasoning support.

The model setter retains the supplied VM model object, awaits the actual runtime checkAuth result through an intrinsic native promise continuation, records the provider/id, optionally updates model defaults and nonempty scoped selection, applies per-model thinking settings, and awaits model_select handlers. Per-model thinking does not rewrite the global thinking default. Native event tasks mark the actual payload VM value and release it using RT-only finalization, preserving the model identity observed by handlers.

SDK Pi session name, thinking, active tools, custom entries and labels apply synchronously to their admitted session/manager. Subscriber notifications are emitted from the actual mutation. SDK context model, thinking, scoped models, idle and signal getters read the captured original live session rather than serialized event-start values. Retained Main UI services keep their independent owner fences.

The native replay fixtures are derived only from recorded execution of the actual upstream SDK. Capture305 covers separate A/B sessions, immediate in-event mutations and outside-event append. Capture308 covers effective versus requested thinking persistence, duplicate suppression, cycle and notifications. Capture309 covers async model auth, transcript and settings changes, per-model thinking, model_select/thinking events and model object identity.

Capture315 additionally holds the actual auth resolver, proves no model change before release, observes retained context/scoped selection and enabled-model persistence after release, and distinguishes Pi false from the direct no-API-key rejection.

Capture317 distinguishes the retained public AgentSession from its SDK extension capabilities after dispose: public mutations still change that object, while events receive stale contexts and SDK Pi/default bindings remain denied. The narrow public mutation whitelist does not admit a disposed session through retainCaller or sessionModelLease.

Capture320 covers actual AgentSession.state/agent.state aliases, top-level shallow copies when assigning messages, retained message element identity, live thinking getters, last assistant text with aborted-empty and whitespace messages, scoped-model identity, prompt templates and idle waiting. Native state array accessors retain plain VM backing values through C function data, without opaque peer dereferences in GC.

Status: authored candidate, not qualified. Full AgentSession API parity remains incomplete. Queues, compaction, retry/branch summary, tool execution, prompt lifecycle and public class topology require their own actual Source replays and implementations. This packet does not certify those surfaces or promote the native default.
