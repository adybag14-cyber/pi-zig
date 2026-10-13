# Native session events and constructor hooks

This is a private Source-authoring component for upstream
`19cb534c3b6e3871458a8fa59e98f0312c50e995`. The candidate has formatting and
AST validation, and genuine upstream reference captures. Native compilation,
runtime comparison, and allocation qualification have not run because fresh host
free memory remained below the unchanged 16 GiB admission requirement.

The component uses ordinary Source session fields. It has no native SDK hidden
state or legacy `data` alias requirement. The factory must initialize the Source
fields and provide all live helper methods before attaching it.

Install in this order:

1. `native_sdk_session_events.install(engine, prototype)` installs event
   projection, retry prediction, replacement, public subscriptions, queue events,
   persisted-message lookup, and the limits-model method.
2. `native_sdk_session_hooks.installWithDependencies(engine, prototype, deps)`
   installs the six original constructor installers and their private helper
   bodies. The dependency record is retained in native function data.
3. `native_sdk_session_events.attachWithDependencies(engine, session, deps)`
   installs the own bound `_handleAgentEvent`, subscribes it to the real Agent,
   and installs all six callbacks in Source constructor order.

The dependency record requires `normalizeToolResultImages`, `convertToLlm`,
`getVirtualModelState`, `shouldCompact`, and `estimateProjectedContextTokens`.
The message converter comes from `native_sdk_messages.create`. The last three
utilities come from `native_sdk_session_estimate.install`. The factory must
supply the actual native image normalizer. Plain `attach` rejects with
`RequiredNativeSessionHookDependencies` before mutation; missing dependencies
cannot activate an incomplete factory.

Required live session helpers include `_preparePromptAndToolLoadout`,
`_buildBoundaryContext`, `_commitBoundaryDrafts`, `_reportInvalidBoundaryContinuation`,
`_runAutoCompaction`, `_isRetryableError`, and the custom-message transcript
helpers. They are invoked directly on the current receiver. The event and hook
module never replaces a missing helper with a successful empty result.

The handler awaits extension dispatch before public listeners, and invokes public
listeners before persistence. Listener exceptions block persistence. Queue removal
precedes dispatch. Replacement preserves the finalized message object, retry
settlement follows assistant persistence, and pending custom messages flush after
turn-end dispatch. Hook closures read the live extension runner and session fields.

`test-native-sdk-session-events` contains three comparison tests:

- 28 genuine SDK-factory Source event scenarios, including a real Agent prompt,
  against actual native Agent, ExtensionRunner, and SessionManager components.
- 16 genuine SDK-factory Source hook scenarios, including hidden/forced/request
  projection and tool blocking/errors. Four use an explicit nested-recorder
  collaborator to test event decoration and usage merging; they do not certify
  `NestedToolCallRunner` itself.
- 28 original exported utility cases, including usage invalidation, getter/error
  behavior, threshold coercion, virtual state, and three functions' metadata.

The native fixture's unused image dependency explicitly throws if invoked. It
provides no image-normalization success fallback. These tests do not activate the
production session factory or certify a complete SDK, distribution, or release.
Further next-turn, virtual routing, image, boundary drafting, complete factory,
and induced-allocation qualification remain necessary.
