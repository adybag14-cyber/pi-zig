# Incremental native HTTP byte publication

The direct reader successor f8e9d80c037a99b69816c6d07f18035c0a72965d passed
formatting, AST parsing, Debug compilation and exact74 metadata. Runtime
retained 73 passes and the original strict Source30 Mistral thinking/tools
snapshot negative, with every full input/artifact check unchanged. That result
is preserved and does not qualify the full Source30 or custom-fetch cohort.

The worker's response Writer previously buffered every mode in its 4096-byte
sink. Small byte responses were consequently published only when that sink
filled or the request finished, even if the real peer had flushed its body
chunks earlier. Mistral's real reader could receive all three small events in
one delivery and parse them without another reader Await between events.

Byte framing now uses the Writer's empty buffer and publishes actual incoming
HTTP reader chunks immediately. SSE and whole-body modes retain their existing
buffer. Error bodies retain their existing accumulation policy. No synthetic
event boundary, cloned partial message, timer tick, sleep or drain count is
introduced.

The new regression uses an actual loopback peer that writes and flushes prefix
bytes, then waits on an owned event before emitting EOF. The native reader must
observe the complete prefix before its callback releases that event; it accepts
arbitrary incoming byte fragmentation. Failure releases the event before engine
and peer teardown. The optional fixture gate defaults to null, preserving every
original Source fixture write/flush plan and expected observation.

The proposed first gate retains all original74 names and adds this incremental
HTTP test. Original Source20/customFetch8 is a separately admitted gate with its
full snapshots, getter/callback/reader traces, GC and allocation controls. No
qualification is claimed before both actual terminal outcomes and full frozen
inventory checks. No C, Engine or expected packet changes are included.
