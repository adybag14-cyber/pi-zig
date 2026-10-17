# Actual Module._load body, source only

The ordinary anonymous constructible length-3 function implements the pinned
Node24 `_load(request,parent,isMain,options=kEmptyObject)` body. It uses the exact
constructor and lexical owner from the prototype unit. It preserves the private
relative cache, live public `_cache`, children update and circular routes,
resolve result destructuring order, node-prefix-before-cache and bare-builtin-
after-cache order, main publication, first versus last parent, private source
and circular-visited relations, shared public Symbols and load/finally cleanup.
Source's repeated exports reads during circular-warning cleanup remain repeated.

The Source watch reporter body is implemented over the required real watch-mode
predicate and real process.send; it preserves the repeated send getter before
calling with the process receiver. Children operations use captured actual VM
Array primordials. Native private fields are VM WeakMap relations; public source
keys use the same actual symbols created by the prototype unit. The constructor
already updates the new module's parent children, so `_load` does not add it twice.

On an ordinary captured load exception, ownership of that exact reason moves
outside the capture slot while actual finally cleanup runs. An ordinary cleanup
throw replaces the original as Source finally does; successful cleanup restores
the original reason exactly. An actually captured uncatchable VM completion or
explicit native allocation failure bypasses guest finally work under the linked
runtime policy. A generation snapshot immediately before the load getter/call
also recognizes a fresh privately tagged allocation reason before clearing the
capture slot or running any guest cleanup, rethrowing that exact reason through
the existing helper. Historical tags and guest lookalikes still take ordinary
finally cleanup. No rejected value, error name, stale tag or reason data flag is
used to invent a new failure. This corrects a concrete source-review blocker in
the initial d0cb unit; its original commit/manifest remain historical. No shared
C/Engine/helper policy changes occur.

Required real collaborators remain resolveForCJSWithHooks, loadBuiltinWithHooks,
BuiltinModule normalizeRequirableId/canBeRequiredWithoutScheme, circular exports
and warning Proxy, watch options, Node debug/validation, real process and the
actual prototype loaders/compiler/FS/ESM/NAPI. The callable checks only reject
missing functions; they do not establish authenticity. No substitute namespace,
dummy builtin registry, always-failing loader or default installation is supplied.
Load-source/hooks/ESM composition must share this exact private owner and maps.
Bootstrap partial allocation failure is negative, not an admitted usable graph.

Eight original Node24 caller controls use actual Module._load, actual files,
genuine custom extension dispatch and temporary mutations of real public caches.
They cover observed function shape, true Module/cache/parent identity, relative
cache export liveness, real cycles, successful custom handling, failure cache and
child cleanup, finally-error precedence and prefix/bare builtin cache order.
They do not expose or claim to observe Node's private last-parent slot; that
accessor remains a source/ownership review boundary until composed controls exist.
These are prepared inputs with expected/observed output absent. They are not
native or original runtime proof; no Node/compiler/native/generator job ran.

Five additional direct native controls call the same loadWithCleanup function
that the actual loadBody calls. They use genuine native VM load callbacks, actual
Proxy deletion/getters and real children arrays in an explicitly controlled
private lexical owner. That cache fixture is not presented as a whole Module
constructor, namespace or missing production dependency. Fresh private failures
from both getter and call must skip cleanup and retain exact identity; historical
and lookalike reasons permit cleanup to replace them, while an ordinary raw reason
survives successful deletion and child removal. This is the approved direct
boundary seam, not a copied cleanup implementation or whole-loader mutation proof.
All five remain uncompiled/unrun and compiled metadata count is unknown.
