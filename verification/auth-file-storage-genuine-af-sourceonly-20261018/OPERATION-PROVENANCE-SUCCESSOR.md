# Exact failing-operation provenance successor

The historical `eb40192b` product and `9f49ef44` control-bootstrap successor
are preserved as immutable commits. A source self-audit identified this causal
sequence: getter one successfully creates/returns private Error DATA A; getter
two throws A without advancing the native generation. Getter two's exact guard
correctly treats A as historical, but the old whole-body generation fallback
could then mark A fatal. No execution was needed to identify that source bug.

The current successor removes that outer generation reclassification from the
File methods and the newly adapted lock/Promise/iterator callbacks. Ordinary
captured reasons transfer unchanged after current pending/Bfb event precedence;
direct trusted host OOM still takes its fatal exit. Generations now belong to
the actual property get, call, constructor, numeric/coercion, VM allocation or
private-state write that can fail. Private action/state decoding is guarded at
its own operation. Ordinary reason suppression and Source finally preserve the
outcome already recorded before native retirement. Completion's per-free
cleanup generation is unchanged.

The actual lock's pre-existing native acquire/release helpers use those same
local per-operation getters/calls/conversions, so an adapter-wide fallback is
not needed. This adds exact pending normalization to their shared numerical
and option helpers; their filesystem/retry/heartbeat algorithm is unchanged.
It does not establish inherited synchronous Scope/constructor/timer cleanup
or full third-party custom-fs parity.

Three additive native controls are prepared: (1) the genuine File method's
result getter returns successful unmarked private DATA A and its next getter
throws the same A, requiring ordinary catch plus actual finally; (2) its actual
next native getter produces a new initially unmarked private failure, requiring
exact fatal classification and no guest finally; (3) the real public lock's
stale getter creates A and its later update getter throws A, requiring ordinary
adapter rejection. The original seven controls and common original observer
remain. There are now ten authored native tests, no observed metadata/results,
and no new original output or authored expected fixture. All execution is held
for Root's explicit grant and the required DATA-safe producer/Bfb composition.
