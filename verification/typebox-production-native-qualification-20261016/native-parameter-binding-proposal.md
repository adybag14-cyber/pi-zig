# Source-only genuine pattern-properties parameter repair

The actual b97 native batch passed build and metadata4 with complete frozen
posthash0, then failed1/4 runtime with fullpost0. Source80 matched first14 rows
and stopped at missing Default; Source52 matched first50 and stopped at genuine
compat-valid (Checkfalse, Errors[]). Source396's391 depth result remained a
negative. Owner46416/runtime78008/metadata35336 were independently absent with
globalnative0 before releasing the lease.

Actual BuildPatternProperties calls EmitGuard.Every on Entries(value), passing
the generated parameter strings `[key, prop]` and `_`. Original generated
JavaScript destructures the entry pair. The native IR previously bound the
whole pattern string as one environment key, leaving the individual generated
key/value variables undefined. This explains the native checker rejecting the
valid record while the actual independent Errors visitor accepts it.

The proposal lowers the fixed generated parameter forms during EmitGuard
recording into private typed identifier/array binding records. Code() continues
to return the unchanged original text. Native callback invocation binds an
identifier directly, or destructures an array binding through the real VM
iterator API, preserving left-to-right Next/value reads, early IteratorClose,
and original exceptions through closePreserving. The same callback scope and
private lexical environment retain the bound values.

Independent review found the initial ASCII identifier admission too broad:
reserved words could be accepted, and special names such as undefined, NaN or
Infinity could bind a value that identifier() would resolve as a literal or
numeric operand first. The correction leaves identifier() unchanged and admits
only the pinned schema compiler's six scalar names (`_`, `refinement`, `context`,
`value`, `element`, `index`) and canonical decimal `var_N` names from Unique().
Only a flat tuple of two distinct `var_N` names is admitted. Empty/singleton or
longer tuples, duplicate names, elisions, nested arrays, object patterns, rest,
defaults, leading-zero generated names, and every other identifier fail with
NativeTypeBoxParameterPatternUnsupported before IR recording completes.

native-parameter-original-source-corpus.json records the exact original source
files, hashes and all emitter call sites supporting this admission boundary.
This was a static source read; neither the original compiler nor its emitted
checker ran. Reserved and special shadow names are deliberately outside this
bounded backend's parameter scope. No general lexical-shadow support is claimed.

This is bounded lowering of compiler-produced scalar parameter strings, not a
general JavaScript parser, AST host, Function/eval checker, or arbitrary source
replacement support. Unsupported parameter forms fail explicitly. Existing
compiler-owned join-mutation and arbitrary BuildResult source replacement risks
remain open. No source fixture/golden, C, guard, timeout or counter changed.

The original genuine compat-valid and pattern-properties rows supply the
regression controls. No native execution, Zig formatting or AST command has run
for this proposal during the Highlighter lease. Semantic/native confirmation
requires the next explicitly granted matching pair.
