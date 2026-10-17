# Owned cleanup correction to thin GetAsyncIterator API

Originala70796d55812dea940eb76244e0f2dd16a038769 and its entire packet remain
unchanged historical negative evidence. Min found a concrete reentrant-finalizer
priority/ownership issue in that wrapper's postpending cleanup.

The wrapper now keeps its chosen reason owned OUTSIDE the pending slot. It takes
and clears any pending cleanup reason before freeing another value. Only the first
actual fatal promotes over an ordinary chosen reason; all displaced owned values
are released with the pending slot empty. Any exception raised by that release is
captured in the next drain iteration. Only after the pending slot is empty does
JS_Throw restore the owned chosen reason. Thus freeing ordinary originalA cannot
replace newly latched fatalB with ordinaryC, and JS_Throw never releases an occupied
pending reason while overwriting a finalizer-installed reason.

One actual native VM test definition adds two finite nested-finalizer controls.
The callback creates ordinary/fatal originalA fresh and transfers its SOLE owned
reference into pending state; cleanup_original is borrowed identity only. No
getter/function capture retains A. Freeing resultR raises fatalB (ordinaryA case)
or ordinaryC (fatalA case). Promotion frees A and its finalizer transfers sole-owned
C; freeing C raises ordinaryD. Counts prove R/A/C finalizers actually run. The test
requires exact chosen firstfatal identity and an empty pending slot after owned
caller release. The recorded native callback convention violation remains explicit.
Nonterminating/malicious native finalizer chains are outside qualification; this
introduces no general VM loop/fatal policy or generic JS_Throw rewrite.

All acquisition logic still delegates actualJS_GetIterator(ctx,obj,true), and entry
pending/no-work policy, borrowed input/owned result, header, Zig binding and original
12 tests remain. Total prepared VM test definitions are13. build/test steps remain
isolated/unrun. No C4/CallSite/Engine/Main edits or Node/compiler/parser/AST/native/
generator jobs, expected/golden/observed data, or qualification claims occur.
