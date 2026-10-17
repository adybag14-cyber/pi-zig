# Import-meta target correction — prepared SOURCE successor

This packet corrects the independently identified write-target omission in
6d4f86bc6b69bd2e77b0fcff8b201bb0a7e0aa4f. The old packet, its source caller,
12 admitted inputs, 18 frontier inputs, authority/licenses and prepared manifest
remain byte-for-byte unchanged. Its manifest is historical SOURCE evidence,
not a positive qualification of the omitted target cases.

Only native_jiti_import_meta.zig changes. The target walk follows transparent
parentheses/non-null wrappers and array/object/rest pattern containers. A pair
pattern contributes its value target only; a default pattern contributes its
left target only. The walk then checks the actual left field of assignment,
augmented assignment or for_in_statement (the retained grammar uses this node
for both in and of). Existing update/delete checks remain. This rejects selected
meta expressions that would otherwise become writable process.env or the local
jitiESMResolve binding. Rejection remains UnsupportedJitiMetaForm before any
replacement/path callback or publication. No shared eraser/lowerer is changed.

The walk stops on computed keys, default initializer right sides and ordinary
expression edges. These evaluate the selected meta value as a read. A selected
meta value used as an outer member's object/index also stays a read: this patch
does not add a blanket rejection of every expression inside a target statement.
The preexisting unsupported computed/optional meta and process-binding frontier
is preserved.

inputs.json contains nine rejection cases and seven preserved read/call cases.
They use the same schema as the original genuine Source caller. A future
separately admitted capture may stage the unchanged original source-caller.mjs
beside these owned additive inputs, pin the official Babel/public jiti paths,
and capture all emitted code/errors/execution records without projection. It
must not overwrite the old packet or compare native rejection with a fabricated
Babel diagnostic: Babel may compile these assignments, while the declared bounded
native profile deliberately rejects them. This is a capture plan, not execution
authorization or an executable controller.

Prepared native control specifications (not runnable harness entries):

- For each of the nine target programs, call the actual meta rewrite with a real
  Engine and owned filename. Record UnsupportedJitiMetaForm and zero path calls;
  compose through the actual default backend to record its existing coded
  unsupported exit and zero user execution/Module/cache publication.
- For each of the seven read programs, call the actual rewrite and composed
  backend. Keep the raw output code and actual completion. In particular,
  computed pattern keys and default initializer RHS must reach the existing
  path/env/resolve replacement logic rather than the write rejection.
- The nested array/object/default/rest and TS non-null cases independently cover
  target ancestry; the for-in/of cases cover the distinct left-field terminal.
  Existing direct assignment/update/delete behavior is retained unchanged.
- Source and native runs require separate Root admission, complete seals and
  real callback/allocator/GC observations before any runtime claim.

No expected, observed or result files exist. No Node, compiler, AST/parser,
native, generator or capture job ran. Ordinary text/schema reads and Git/static
hash checks do not establish compilation, AST acceptance, code-format parity,
whole-Babel parity or default selection. The existing original caller's owned
process/dummy fixture environment contract remains unchanged.
