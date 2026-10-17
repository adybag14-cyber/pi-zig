# Actual transformed evalModule body — source only, uncompiled/unrun

This unit implements jiti2.7 eval.ts's actual transformed Module/evaluation
body using reviewed Module8a, cache/interop926 and byte-identical API12a leaves.
It exports a host `evaluateTransformed` entry, not a complete public evalModule
or createJiti facade. No Main/C/Engine/shared helper/default selector changes.
No Node, Zig, fmt/AST, compiler, native, or generator job has run.

The input is the actual Source front end's resolved context, evalOptions,
filename, selected parent cache and original source bytes, plus API12a's
explicit TypeScript/async transformation profile flags. The front end's actual
id/ext/cache/needsTranspile/options/resolver/transform/fsCache/debug ordering
remains required caller work. There is no invented successful transform or
empty substitute context. API12a prepare runs before any Module creation or
publication and preserves its documented unsupported-syntax frontier; this
does not reproduce all Babel options, output, errors, or getter behavior.

Every Inputs function must be the real Module, nested createJiti, pathe dirname,
jitiRequire and debug implementation. The missing complete factory/resolver/
pathe/options/transform bindings remain explicit. Inputs preflight rejects
noncallables before preparation/construction. Merely being callable is not a
provenance or qualification assertion; the eventual assembler and controls
must supply the actual completed implementations. All positive controls are
pending those genuine subjects. No fake nested factory is used in this packet.

The body constructs a real Module and preserves filename/parent children
getter/method order, actual nested factory argument order and identities,
require/path/paths assignment, and publication of the same Module to real
parent/native caches before compilation. Source's live async reads for wrap,
compile catch and return remain separate from the earlier transform option.
The API's raw seven-argument invoke is unchanged. Returning onError continues
Source control flow: a returning compile handler leaves compiled undefined
and reaches the actual call-error catch; a returning evaluation handler reaches
next. Only synchronous compile/invoke catches do native-cache cleanup.

Ordinary caught reasons transfer out of Engine before guest cleanup/onError.
A new thrown cleanup reason overrides the old without old-reason formatting;
fresh private native allocation reasons and preexisting uncatchable values
bypass ordinary handling. The private next owner has null prototype, roots
the real context/module and is retained by an aggregate-charged, VM-marked
ordinary callable. No manual thenable driver or AF/prototype retagging exists.
Source's Promise.resolve(evalResult).then(next) returns the actual raw .then
result, with real live callees/receivers/getters. Async rejection does not gain
extra synchronous catch cleanup. The next function remains ordinary.
Ignored push/debug/onError/capture returns are immediately freed by narrow
statement-call helpers, before later guest callbacks. They never enter the
enclosing broad Scope's retained values; no shared Scope implementation changes.

The real parse-marker branch preserves three mod.exports and two marker reads
when truthy, destructuring and template conversion order, actual Error creation,
then a second live Error binding read for captureStackTrace with actual
jitiRequire, returning onError, then
loaded=true and interop. The actual C2 captureStackTrace implementation already
exists; this leaf calls the live property without a synthetic missing-feature
guard, so guest removal/noncallability produces the real VM TypeError. No dummy
stack helper is installed. Its jitiRequire cut/format semantics still require
qualification. The compile SyntaxError/async/nativeImport branch
performs actual fallback debug then fails `RequiredActualJitiEsmEval`; data URL,
temporary-file import/finally/unlink fallback remains missing. It neither
substitutes a fake function nor silently enters the ordinary catch. Filename
support remains actual physical NUL-free string/UTF8 profile, not complete
Node/V8 filename diagnostics or lone-surrogate stack parity.

Five prepared native entrypoints require actual subjects and accepted Source
observations: real Module/cache/export identity, publication-before-async-finish,
returning onError trace/finish, missing required binding before publication,
and API12a rejection before publication. Thirteen causal inputs specify real
original-source module bodies and actual callbacks/options, including cycles,
cleanup override, live async reads, raw .then result, parse-marker effects and
fatal boundaries. They are not expected observations. No new expected exists.
The additive ignored-return control uses an actual returning onError object,
genuine FinalizationRegistry cleanup, and bounded actual VM GC/job execution at
the real loaded setter. It uses no WeakRef kept-object inference or substitute
factory. This native ownership probe is prepared only; it asserts no portable
Node GC scheduling oracle and requires complete actual subjects before running.
The final native allocation/collection/teardown and genuine original Source
capture still need separate bounded Root grants and complete actual subjects.

The API12a two leaves are copied unchanged from
12a4c7cfe61aa3360d4f9af7f9bc090cf0bbd55c; typescript.zig is the identical reviewed
2EAD eraser. The original authority eval.ts and MIT license are retained in
the earlier jiti packet; prepared.json seals them and all original proofs.
No qualification transfers from the earlier async primitive or Module review.
Queued C3 Graph0, Graph2 importer/default interop/mixed cache policy, and graph
reclamation/resource policy are still separate unfinished gates. Default SDK
selection remains off.
