# Agent full-method AF corrections — SOURCE successor

Original1ec058e76b4ef1d3788f4ee9c62ece64ddb3e7be and its entire32-row packet
remain immutable historical source evidence. Google identified two concrete
fatal-boundary omissions; both are corrected in this separate contained tree.

The processEvents iterator tick now matches actual VM JS_ThrowInterrupted and
native_tsconfig_values.tick: create the actual interrupt exception, take that
owned reason, mark it uncatchable and rethrow the SAME reason through checked.
Cancellation/interrupt budget cannot become an ordinary Agent AF rejection and
enter Source runWithLifecycle recovery. No C/global iterator helper is changed.

construct now checks its successful result before transferring to Scope. An
actual pending exception is captured pending-first. A captured callback reason
is restored as host fatal only if it is both uncatchable AND a fresh private
allocation tag inside this constructor's exact generation boundary. The actual
global Promise constructor consumes executor exceptions into a rejected idle
Promise, so merely marking callback OOM was insufficient. A catchable fresh tag,
historical marked tag or marked lookalike remains ordinary data on success.
Owned returned results are released on exceptional exit; Scope consumes the
result exactly once even if its own append allocation fails. No generic fresh
captured-tag inference or replacement reason allocation is introduced.

Both prepared native AF comparison helpers now assert bool JS_IsAsyncFunction
directly, matching actual quickjs.h. Root already carried the same prompt-helper
one-line correction; later intake must preserve all Root lexical/bool fixes and
apply only the scoped changes, never replace its newer shared snapshot.

Three actual VM test definitions are prepared: marked executor GPA failure via
the REAL global Promise constructor must escape with exact identity, including
unsigned generation wrap; successful construction must ignore catchable fresh,
historical marked and untagged marked data; actual processEvents cancellation
set during captured-next acquisition must escape host-fatal before next executes.
These use real native AF/ordinary callback/global Promise/AbortController bodies,
not a substitute Agent or fabricated rejection trace. The isolated build/test
steps are not attached to default tests. No job or parser was run.

Original32 Source observations/native comparisons remain unchanged and unrun.
Additional fault/GC/pending-success controls still need Root's accepted current
C3/C4 composition and full real application bootstrap. This old-parent tree is
not a proposal to roll back Root's current C/H, Engine, expanded qualification
targets or session helper lexical fixes. No Main/C/H/Engine/default/expected or
original corpus edits; no compiler/AST/Node/native/generator execution or runtime
qualification claim exists. Full Agent low-level loop/response/tools continuation
work proceeds separately, preserving the reviewed class-method boundary.
