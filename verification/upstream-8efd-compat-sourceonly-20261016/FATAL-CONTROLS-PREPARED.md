# Unexecuted host-input lifetime/fatal controls

These are source-prepared controls, not runtime observations. Source-callers have no authored expected JSON. New native guards need exact C/JS identity, pending exception and ownership checks under a later Root grant; names/messages alone do not qualify them.

Four unrun native tests are authored in src/native_durable_live_host_inputs_test.zig. The ordinary retention test seeds an existing operation capture/diagnostic, calls a real native C supplier which itself enters Engine.checked and replaces the capture, and asserts restoration of the original owned cause. The fatal test uses actual Engine.throwNativeOutOfMemory in a C supplier and asserts exact strict identity with the retained native allocation reason, uncatchability, and no restoration of the old cause. The tool getter test catches the actual native API getter error in guest code then checks that its ordinary native captured slot is empty.

Before native acceptance additionally cover:

| Actual seam | Required observation |
|---|---|
| settings/models option getters during public Harness construction | Read once at Source order; getter throws retain raw reason; replacing options later does not replace captured input; plain object mutations remain live. |
| settings/models callable | Bare undefined receiver, zero arguments, every access; raw ordinary throw; bound function/proxy/class behavior uses VM call semantics; returned Promise is not implicitly awaited. |
| runtime.models, runtime.settings and tool models/env getters | Real descriptor name/arity/enumerability/configurability; ordinary capture transferred before guest catch; a newer pending reason wins; a new same-object capture is not cleared by deferred identity cleanup. |
| retention supplier and documentRetentionMs getter | Seed prior captured reason AND diagnostic; supplier/property callback enters native capture; ordinary success or throw restores prior cause while releasing bookkeeping captures; fresh tag/already-uncatchable overrides prior exactly. |
| Manager contextRetentionValue settings supplier | Ordinary cause is owned before reporter; Source reporter/fallback0 preserved; fresh tagged/direct OOM/already-uncatchable bypass reporter and fallback and escape through settleIdleContexts/scheduleContextExpiry. |
| actual publication, Session after-storage and queued sweep callers | New retention fatal remains exact through touch/sweep/settlement; no stringify/replacement/swallow; real worker/owner line and first-failure state retained. |
| tool env Await and rerun | Original API identity; env is undefined before fulfillment and exact supplied value afterward; each attempt owns a different cell; no eager model getter via spread. |

For every fatal seam separately supply fresh private native allocation reason, already-uncatchable reason, historical tagged reason, and ordinary guest lookalike. Use actual native callbacks and the Engine's private generation/retained reason; do not forge properties as authority. Preserve u64 wrap classification. Test callback reentrancy and explicit GC while the old detached cause remains owned, including cyclic reasons, then meaningful admitted allocation failure positions. Preserve pending/newer reason precedence and exact identity at the host surface. Check primitive/raw pending reasons rather than relying on diagnostics.

No new direct-capture guard qualifies the legacy raw clock/readSettings policy or all generic durable callbacks. Those broader seams remain separate audits. Complete public generation/compaction/hooks/deferred/recovery capture remains required; the source-only caller packet and local tests do not establish it.
