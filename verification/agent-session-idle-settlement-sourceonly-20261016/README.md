# Ordinary AgentSession async audit and idle/settlement migration

Base: `a41a94de0b0ca5e689bb9d59cd31c26b78edeebb`. Source authority:
`0fbdbd3f8ab1876ac260c0f08226a400759323b8`, actual
`packages/coding-agent/src/core/agent-session.ts`, SHA256
`E0FA206E8C49A98C024708068DF39C0E4944F4251633425FC083B2FBB5EC0AC6`.

This is source-only preparation. No Zig invocation, source capture, native
compile, or native execution was performed under this lease. The inherited
qualified async primitive and live `native_async_body` helpers are consumed
without changing C, Engine, shared flow, constructor, declaration order, SDK
inputs, or the application/default SDK route.

## Installed async surface

`upstream-async-inventory.json` inventories all 44 actual async prototype
methods, their exact Source method hashes, their native module, and every
lexical await line. Nested callback awaits are separated from outer method
awaits. `_handleAgentEvent` is an additional async instance arrow field created
by the constructor; it is not a prototype method.

The production installer contains synchronous modules too. Public values,
queries, utilities, statistics, loadout, restore and active tools primarily
install synchronous methods/getters. Registry and hook installers are
synchronous even when they create async callbacks. Returning a Promise does
not by itself make a Source callback async.

The following actual async closures need their own migration; they must not
be confused with the installing synchronous method:

| Source closure | Source start | Actual await lines | Native owner |
|---|---:|---|---|
| Nested runner `emit` | 759 | 760 | `native_sdk_session_boundaries` |
| `agent.prepareRequest` | 790 | 812, 823, 840, 841 | `native_sdk_session_hooks` |
| Nested request `prepare` | 793 | 801 | `native_sdk_session_hooks` |
| `agent.finishTurn` | 889 | 891, 892 | `native_sdk_session_hooks` |
| Legacy `prepareNextTurn` adapter | 903 | 903 | `native_sdk_session_hooks` |
| `agent.prepareNextTurnWithContext` | 905 | 906, 907 | `native_sdk_session_hooks` |
| `_handleAgentEvent` instance field | 1104 | 1144 | `native_sdk_session_events` / constructor |
| Hidden-declaration `transformContext` | 1774 | 1775 | `native_sdk_session_hooks` |
| Forced-prompt `transformContext` | 1794 | 1795 | `native_sdk_session_hooks` |
| Deferred prompt action | 2060 | 2060 | `native_sdk_session_prompt` |
| Deferred custom-message action | 2346 | 2346 | `native_sdk_custom_message` |
| Extension action `setModel` | 3458 | 3460 | `native_sdk_session_registry` |
| Extension context compact IIFE | 3485 | 3487 | `native_sdk_session_registry` |

`_executeNestedToolCall` has no outer await: its await at 760 belongs to the
nested `emit` callback. `steer`, `followUp`, and `cycleModel` also have no await
and directly adopt a returned Promise. `_queueSteer` and `_queueFollowUp` are
genuine async methods with synchronous bodies. The extension context `compact`
callback itself is synchronous and starts a void async IIFE. These distinctions
are part of the remaining migration boundary, not claims of current parity.

## Selected cluster and exact await map

Only these three installed method bodies are changed:

| Method | Source await | Native action / resumption |
|---|---:|---|
| `abort()` | 2473 `await this.waitForIdle()` | Start executes original abort flags/callbacks/order, returns one owned `awaited`; fulfilled resumption returns undefined; rejected resumption throws the same reason. |
| `waitForIdle()` | 2480 `await this._getIdleWaitPromise()` | Idle branch returns immediately without await. Active branch awaits the existing memoized Promise once, then returns undefined or throws the same rejection. |
| `_emitAgentSettled()` | 1085 runner `emit` | Stage 0 awaits runner emission; fulfillment emits the public event using the saved `aborted` value, then exits the first finally. Rejection exits that finally and propagates. |
| `_emitAgentSettled()` | 1094 each deferred `action()` | Stage 1 resumes the live captured iterator sequentially. No Promise is added between actions. Exhaustion and abrupt completion each enter the original idle-resolution finally once. |

The first finally clears `_isEmittingAgentSettled`. The deferred list is
spliced only after that first try completes. The second finally resolves idle
waiters after deferred iteration, including an action rejection. An abruptly
interrupted iterator is closed while preserving the original guest reason;
iterator-step failures do not perform IteratorClose. A guest idle-finalizer
failure overrides the original action error as in Source.

Private invocation state uses the inherited null-prototype owner from
`native_async_body.init`; stage/action fields are private lexical locals. Both
control methods retain a private unsigned BigInt allocation-generation
boundary. Settlement retains its own boundary and uses
`rethrowRecognizedAllocation` for rejected native allocation identities.
Synchronous native allocation failures propagate as native failures. Entered
Source finalizers are attempted before propagating a direct fatal OOM; cleanup
cannot turn it into success or an ordinary guest error. Iterator-close native
failures are classified against their own boundary rather than swallowed by
the old blanket `closePreserving` catch.

No `flow.create`, `flow.wait`, outer flow Promise, or AsyncFunction prototype
branding remains in either selected module. The 17 synchronous control method
bodies and their helper region are unchanged; normalized-LF region SHA256:
`8C8E89860B5CB82047D6AC8D811C90BAE56788EA3046A8E0471EADCE25BD4C7C`.
Sync installer flags/arity/order are preserved, while only the two async
control entries use `createResumable`.

## Existing immutable fixtures and qualification gap

`selected-method-source-equivalence.json` verifies exact UTF-8 method bytes
without normalization between the retained fixture authority and Source0fb:

| Method | Retained authority | Equal method SHA256 |
|---|---|---|
| `abort` | e6220e1 | `CBFDE211CB397829D9E39F0005B565F3CD5212CF9864993CC5D50FD1757AC837` |
| `waitForIdle` | e6220e1 | `6B145442F03C175598823B56954A8CF4224E634C9007F31173D311D94FC943E0` |
| `_emitAgentSettled` | 19cb534 | `6356FD700348796742C559AD347470AA65794401DA4DD13AC7996830BCCB012F` |

The retained Source35 control fixture, control GC/allocation tests, and
Source19cb settlement/lifecycle fixture and allocation tests were not edited.
These are historical fixture authorities with byte-equivalent selected
methods. Their factories, constructors, supporting dependencies, application
route, and the complete current ordinary class are not thereby qualified.

Next admitted validation must compile these bodies, replay the unchanged
control and lifecycle fixtures, exercise retained GC and all allocation
positions, and assess the actual ordinary-class constructor route separately.
This packet makes no formatting/AST/runtime pass claim: only source inspection,
exact historical method comparison, sync-region comparison, and `git diff
--check` were performed.

`native_qualified=false`, `full_factory_qualified=false`,
`full_pi_qualified=false`, `public_activation=false`.
