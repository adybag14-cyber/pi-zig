# Genuine ReadOnlyAuthStorage and ordinary one-off read

This separate source unit starts from Root
`6be4a789c69bee98da06ea57190e519c06b1a551`. It preserves the File2 branches,
all historical proofs/assertions and the existing legacy readonly producer.
It repairs missing exports in the selected production auth namespace rather
than claiming the class was newly added upstream. Exact c268154c originals and
license are retained under `authority/`; no original execution/output or
expected fixture exists. No parser, AST, formatter, compiler, Node, native test
or generator has run.

## Actual callables and exports

`ReadOnlyAuthStorage.read/list/modify/delete` are genuinely async in Source;
none contains Await. The new producer therefore uses real native AF return,
adoption and throw, with no manual outer Promise or prototype branding. `load`
and the ordinary constructor retain their actual status. Fields remain public
runtime properties with Source initialization/default-path/cache behavior.

`readStoredCredential` is an ordinary exported function, publicly re-exported
by upstream index.ts. The production auth carrier now includes it as the SAME
function returned by the readonly producer. It performs a one-off raw read
without store validation or configured-key resolution. Default argument
evaluation precedes its try/catch; normalization/read/BOM/JSON/property work is
inside that best-effort catch. It is not made async because a related API is.
The separate SDK public-index assembler must project this real function; this
patch does not label its factory-only namespace a complete public SDK module.

Production create now supplies the actual getAgentDir, resolveConfigValue and
isCommandConfigValue bindings to the producer. The filesystem owner retains
and checks the third binding on warm cache hits. Runtime imports adds exactly
one field from its actual existing resolver namespace. No prefix-only command
checker, fabricated namespace, resolver stub, child process or completed SDK
graph is supplied here. The required extra binding is deliberate; standalone
createDefault now takes that genuine function explicitly. No in-repo caller
used the prior standalone signature.

## Source algorithm and root ownership

The existing readonly load/validation/snapshot algorithm is reused with actual
native filesystem reads and Source live JSON/Array/Object methods. Read errors
and parse errors are formatted in Source's catch; validation errors remain
outside that catch. EOF/missing-file caching and ordinary mutation rejection
remain distinct. Read preserves repeated key/env/type property reads and calls
the actual configured-value helper only for eligible keys; command keys clone
without invoking the command. Structured cloning is the live genuine realm
binding. List evaluates Object.entries before this.load, then map before
creating its real ordinary mapper. Pair binding uses a real IteratorRecord and
normal return; for-of body failure preserves ordinary A across ordinary close
B while actual native fatal events bypass guest cleanup. Abrupt next/done/value
does not gain an invented close. The existing reviewed native budget guards
the native validation iterator.

Every new callback/operation records the actual completion before its Scope
retires. Raw checked operations pass through exact per-operation guards, then
canonical ownRoot; no broader body-start generation reclassification occurs.
Conditional, iterator method/done/step, binding, parsing and list expression
temporaries have short root scopes before later guest work. The SDK helper is
copied ONLY from immutable source-closed 62ded, exact C435, with CD583672 review
copied unchanged. No shared Engine/Scope/Body/C changes are included.

## Real controls and outstanding composition

The common original/native observer uses the genuine class/helper and owned
physical files. It covers all five method shapes, real OAuth clone isolation,
literal/command/env keys, actual list/snapshot/missing reads, mutation rejection,
two signal checks, held returned-Promise adoption, validation and complete
parse-error observations, raw one-off reads, and an actual process.env property
replacement showing default evaluation outside the catch. That replacement
uses an owned empty object; it reads/copies no host environment values and
restores only on the ordinary completed test path. No host environment changes.

Native-only controls require the actual SDK auth namespace to match its private
installed owner and the exact four VM AF bits/nonconstructor flags. They supply
real marked private Error DATA successfully, then test rejected/fulfilled async
return adoption; a separate actual throw of that same kind of value must stop
subsequent work with exact identity and balanced boundary state. The retained
three typed bodies require genuine namespace/fixture inputs. The compile target
has an explicit fail-if-run sentinel and only an install edge: **not three test
results, not observed metadata, and not a substitute for actual integration**.

The actual FS/TTY/private builtin/child/process/config/resolver/clone providers
and complete SDK owner must compose before these positive bodies can run. Root
G2/current Engine internal retirement qualification, DATA-safe AF1116/current C
and Bfb remain separate prerequisites. Internal shared spread/normalization/
function factories/resolver/clone implementation qualification does not transfer
from this leaf. VM-specific JSON error text and full reflection/stack fidelity
are retained observations, not claimed Node-equivalent diagnostics.

The pre-existing filesystem namespace owner still needs its separately assigned
scope-retirement/publication correction. API owns that successor and will layer
it over these exact new dependency fields without rolling back this producer.
No broad SDK, CLI/default selection, real OS/GPA or application pass is claimed.
