# Token and plugin-iterator corrections — source only

Immutable AST checkpoint3bb07f94 and its original manifest/input/primary bytes are
preserved. Its independent finite review identified three concrete blockers:
missing LS/PS newline preservation, merged lexical boundaries, and use of object
CopyDataProperties where Source requires actual iterable argument consumption.
The first comparator46384 is separately peer-closed; its accepted original30
authority and full-report/strict-comparison policy are unchanged.

The native printer now recognizes CR, LF, U+2028 and U+2029 in actual inter-token
gaps. A gap containing any of those becomes a line break; any other nonempty
gap remains at least a horizontal separator. This preserves restricted
return/async/update productions, numeric-member separation and the boundary
between a flagless regex and a following word operator. Strings, templates,
regexes and comments remain atomic actual syntax regions. This repairs semantic
separation, without asserting Babel's exact whitespace or function-text bytes.

The actual native backend now calls a local native_jiti_babel_plugins helper.
It follows the retained Source condition and live getter sequence: read the
truthy opts.babel, resolve Array.isArray, read opts.babel.plugins, call with Array
as receiver, then reread opts.babel and plugins for the actual spread argument.
It uses the intrinsic iterator symbol, real method/receiver, real iterator and
cached next method. Every next/done/value is observed in order. Done avoids the
value getter. Yielded values stay rooted in a VM array with own data-property
creation until consumption completes; there is no live push/prototype setter.

The helper consumes the entire iterable before reporting nonempty unsupported.
A later iterator failure therefore retains its actual raw reason. Iterator
creation and abrupt Step/Value do not acquire an invented return/IteratorClose.
The reviewed native_jiti_budget.check enforces cancellation/quota as an actual
trusted fatal; a guest error named InternalError remains ordinary. The finite
array-index bound is explicit rather than overflowing native arithmetic.

Actual pending VM reasons are captured immediately after every live getter,
iterator factory/next call and step property, before a subsequent guest operation.
Each successful value is owned until the pending reason has been taken, then
freed. Local balanced diagnostic suppression and the existing exact allocation
generation guard preserve ordinary/fresh reason identity without coercion or
data-flag inference. No Engine, C ABI or generic helper changed.

Eight named native controls are authored but uncompiled/unrun:

- Actual VM differential execution of LS/PS return, async and update scripts.
- Actual VM differential execution of numeric-member and regex/word spacing.
- Actual backend refusal of nonempty arrays and nonenumerable indexed plugins.
- Actual custom-iterator completion, nonempty refusal, and done-without-value.
- Source getter/isArray/reread order and exact second-getter failure.
- Raw next-getter/next-call/done/value/later-step failures without close.
- Twelve genuine native success-with-pending profiles across iterator getter,
  factory, next getter/call, done and value, for ordinary/fresh reasons. They
  require exact identity, no downstream callbacks/coercion and balanced guards.
- A native C iterator reaching the actual 256-step budget check, plus an ordinary
  guest lookalike. No runtime outcome, metadata count or allocator pass is claimed.

These controls use real VM/actual native backend bindings. They are finite
compiler and protocol tests, not a stand-in Module/createRequire/bootstrap.
Nonempty custom-plugin execution remains explicitly unsupported; refusing it
does not qualify Babel plugin execution. The additional original input module
prepares twelve observations for a separately granted pinned original owner.
It is not loaded by the unchanged original30 caller and contains no expected
output. It preserves compiler code, diagnostics, order and plugin observations.

The separate correction build/runtime targets are not attached to default tests.
No compiler, parser/AST tool, formatter, Node, native or generator job ran. Main,
old shared lowerer/meta/typescript, generic owners, C/H and original controls are
unchanged. Source closure and any future execution require the exact successor
review; complete Babel/runtime/default-Jiti qualification remains outstanding.
