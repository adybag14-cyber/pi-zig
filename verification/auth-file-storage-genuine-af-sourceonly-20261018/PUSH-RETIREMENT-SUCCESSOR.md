# Push expression temporary retirement

Independent Source review of immutable `4200370e` confirmed a finite extra-root
issue: executorBody's single Scope retained the callback, live push callee and
ignored push return during later iterable callbacks. A mutated push can remove
the callback from its array and return an otherwise sole object. Source has
already completed that expression before evaluating `method(...args)`.

The successor executes the real push in a short `pushCallback` Scope and
records its void/error completion with the unchanged exact 41AA helper before
retiring those roots. The actual rest array, captured method and executor
arguments remain the Source lexical state. Iterable spread starts only after
the push completion has finished. Actual current/fresh fatal cleanup keeps its
precedence; no Source close/finally behavior or shared policy is replaced.

One additive actual native control creates a target, WeakRef and take closure
in a **prior** VM job, then calls the real `JS_ClearKeptObjects` boundary before
the tested public lock call. A genuine mutated Array.prototype.push delegates
the actual push and returns that target while clearing its sole lexical owner.
The subsequent actual iterator getter runs real GC before its first WeakRef
deref. This distinguishes the required retirement from keeping the ignored
return until the enclosing executor exits. No new WeakRef is created in the
tested job, and no guest restoration is attempted after an error/fatal.

There are now eleven authored native tests. None has been compiled, queried
or run. Prior source candidates, manifests and original inputs remain intact.
The latest `push-retirement-prepared.json` is the cumulative current-byte seal;
earlier manifests describe their own historical candidates, not a current pass.
The current DATA-safe AF1116/Bfb producer, genuine host I/O and Root ownership
grant prerequisites remain explicit. No C, Engine, shared Scope/Body, helper or
Main files are changed by this successor.
