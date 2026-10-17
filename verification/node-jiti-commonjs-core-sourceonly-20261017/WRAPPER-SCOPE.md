# Actual Module.wrap and wrapper tracking

This source unit implements the exact pinned loader initialization and the
`wrap`, `wrapper`, Proxy set/defineProperty, getter and setter bodies. It uses
the actual known constructor and the same charged/traced lexical owner as the
prototype bodies. It does not install a default namespace or call a compiler.
`wrapper_patched` is a native cell; write traps and setters set it before their
actual operations, including an operation that later throws.

The initial array and genuine VM Proxy preserve actual property forwarding,
receiver behavior, array identity and Proxy invariants. The set trap calls the
captured Reflect.set with all four arguments; the define trap calls captured
Object.defineProperty and returns its actual target result. Those are real VM
operations, not a shadow property map. Getter/setter declarations are ordinary
nonconstructible methods; wrap is an ordinary constructible function named wrap.
Both Module descriptors omit enumerable/configurable as in Source.

The wrap expression performs its first indexed read, first addition/coercion,
then a fresh Module.wrapper read and final indexed read/addition. A body coercion
can therefore replace the suffix source. No joined string or cloned array hides
that order. The state roots retain wrappers, handlers, Proxy and captured
primordials. Module-private owner authentication precedes native pointer use.

Install is a host bootstrap operation requiring the exact constructor and its
already-created lexical owner, before user code. A partial allocation failure
does not authorize publication of that partially initialized bootstrap. No
transactional rollback of nonconfigurable descriptors is claimed. Source's
actual compiler must later branch on the same wrapper_patched cell and use the
live Module.wrap. That compiler/source-map/ESM integration remains pending.

Six distinct genuine original Node caller controls are prepared for default
shape/descriptors, prefix/body/suffix coercion order, raw throw, actual Proxy
mutation and borrowed setter receiver. They have no expected/observed output
and have not run. Product compilation, native GC/allocation controls and full
CommonJS/jiti qualification are absent.
