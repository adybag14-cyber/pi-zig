# Planned TypeBox native termination ownership

This isolated source unit lets the real planned TypeBox Machine transport the private execution-termination completion introduced in ce098 without turning it into diagnostic JavaScript DATA or entering guest finally handlers.

The Machine preserves its existing rule that a later ordinary cleanup reason overrides an earlier ordinary completion. It uses the actual classified native reducer only when a private completion participates, preserving cached generic-fatal authority while cancellation changes the active private lease. Native cleanup still runs after a cancelled abrupt completion; a later actual ordinary or fatal cleanup reason can replace that inactive completion. Returned flagged Error DATA remains ordinary data.

## Source changes

src/extensions/native_typebox_continuation.zig contains the reviewed Reason/failure-capture, Machine call/cleanup/complete, and terminal publication changes. The full production packet has 14 exact replacements from the preserved 69286C14 owner. One is the already-reviewed outer ExecutionTerminated gateway. internal-machine-intake.json contains only the 13 internal replacements from 521944FB, for Main after the separate gateway packet has been applied.

The new root contains 15 named controls using actual createPlanned/native-call dispatch, real Frame/Scope holders, actual private request/event/cancellation, and the existing guest-finally machinery. The original 16-control TypeBox root is byte-identical. The seven-line build addition installs the actual test artifact without executing it.

## Main application order

1. Apply the separate ce098 termination C/H packet, preserving Main's existing private-setter addition, plus its exact Engine 87DD/F42 and five-gateway 37F9 snippets.
2. Apply this unit's internal-machine-intake.json 13 edits. Its 521944FB preimage already contains the outer gateway; do not apply that branch twice.
3. Add this unit's new root and the exact seven-line build-intake.json insertion, preserving every existing Main target.
4. Retain the proof directory unchanged. The donor's actual Engine was not overwritten with Root's Engine successor.

SDK closed Machine ownership and controls 1–8. Modules closed Reason/capture ownership, controls 9–15, and the seven-line build seam. The peer-closure record identifies each bounded scope.

## Validation and limits

Static source readback, SHA-256 pins, exact full-delta reversal and forward replay, unchanged-original-control comparison, and additive build reversal were performed. No native build, metadata query, Node evaluation, test run, formatter, or generator was run. Declared names are source declarations, not queried metadata. Runtime acceptance remains a separate Root-owned gate.
