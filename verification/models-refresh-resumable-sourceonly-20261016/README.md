# Models refresh resumable bodies: source-only checkpoint

This checkpoint ports the actual `4954d760504c11df9b2cbdc040346107b6a8153d`
ModelsImpl refresh/publication bodies onto the proposed native async body ABI
from `e3216f5f`. It contains no execution or qualification of that C proposal.
The proposal module is an external integration prerequisite at this checkpoint.

The three async class methods (`runProviderRefreshPhase`, `refresh`, and
`resolveRefreshCredential`), async provider mapper, operation IIFE, and queued
publication IIFE use `createResumable` / `createResumableArrow`. Each original
await returns an owned `Action.awaited`; each original return or throw returns
an owned `Action.returned` / `Action.thrown`. No `flow.create`, `flow.wait`,
second outer Promise, or AsyncFunction prototype branding remains in either
refresh implementation file.

The expired OAuth branch returns the shared credential mutation expression
directly. Provider read failures still restore cache before auth/network; the
read method getter and provider ID getter stay inside the original try. Setup
before the provider race stays outside its finally. Publication persistence
retains its two current-generation checks, exact repeated persist getters,
live update receiver, original structuredClone, and serialized per-provider
tail retirement. The class and generic factory share the original lexical
known-type predicate supplied by the class composition.

Synchronous source catches accept only a captured guest exception. Native
allocator failures propagate through the native error union; newly tagged
native rejection reasons bypass the source error map and aborted-caller
success path. Guest errors with similar names/messages follow source behavior.

Formatting, Zig AST parsing, and whitespace validation are the only checks of
this migration. The previously qualified genuine Source60 observations are
unchanged (`D77AB7B2C9918C55E2DEAFAC8ABC9C7917095467EFBC7A4382FFD5A811B30331`).
Prepared native qualification has 60-row public-namespace comparison, pending
publication/clone retention across real GC, and a complete host allocation
exercise. None has been compiled or executed for this candidate.

`native_qualified=false`, `genuine_native_async_function_qualified=false`,
`full_factory_qualified=false`, `full_pi_qualified=false`,
`public_activation=false`.
