# Native AgentSession user-message delegation

The missing public sendUserMessage method is implemented in Zig through the linked C VM. It normalizes string and iterable content, preserves image identity and Source getter order, calls the receiver's live prompt method, awaits its result without blocking, discards successful prompt return values, and rejects errors with their original identities. Native Promise intrinsics implement the await boundary.

The unmodified latest upstream AgentSession.prototype.sendUserMessage was observed using caller-provided prompt receivers. No Source class or prototype method was replaced. All 21 Source cases replay unchanged: strings, empty content, options and nullish defaults, mixed text/images, non-text parts, join coercions, custom iterables, getter evaluation order, iterator close with original error identity, synchronous throws and asynchronous rejection, thenables, held prompts and invalid content.

The original reference passed with zero drift across 31,064 runtime and 1,774 tool files. The causal native regression initially compiled and failed because sendUserMessage was absent (8 controls passed). The first repaired Source replay passed 9/9.

Expanded Windows Debug qualification on pinned Zig 0.16.0/default backend passed 82/82 tests and 168/168 build steps. The sendUserMessage target executes 11 tests, including retained values across real GC and exhaustive allocator failure cleanup. Nearby SDK input/queue, durable image model consumer and Chord context gates also passed. Source/tool posthash: 4,245/19,546 files, zero drift; owned process gone.

The durable image consumer adds actual Source image result/readback and warning behavior without changing production model consumer code. Its private isolated gate passed 25/25 before Root integration.

Full AgentSession parity, typed native model/auth services, Chord Host lifecycle, non-Windows qualification and public native-default activation remain unfinished requirements. These component results do not authorize removal of the legacy host.
