# Native default Babel AST frontier successor — source only

This successor extends the actual native backend while genuine public bootstrap
work proceeds independently. It does not replace any of the accepted original
12+18 inputs, original output96DA, old nine-plus-seven controls or frozen9f tree.
The comparator checkpoint46384 remains separately reviewable. No compiler,
formatter/AST tool, native, Node, generator or allocation job was executed here.

The new native compiler has no fixture IDs or original-output dependency. Only
verification code reads the accepted original JSON. New native Zig passes use
the actual linked Tree-sitter TypeScript grammar and real existing TypeScript
lowerer. The older shared native_jiti_cjs_lower/native_jiti_import_meta and
typescript implementations are unchanged. The existing native default backend
selects the dedicated Babel units in this isolated successor, with no default
CLI/SDK/public-loader activation.

## Actual compiler extensions authored

- Meta visitors match the pinned MemberExpression/Identifier rules. Computed
  identifiers, writes and deletes are visited; local process bindings remain
  live. Optional members, literal-index members, bare meta and unknown members
  remain compiler output as they do in the original. Producing compiler text is
  distinct from proving that a later CJS wrapper can evaluate that text.
- Default, namespace and mixed named/default imports use actual compiler-emitted
  interop helpers, including their real WeakMap cache and property descriptors.
  These are generated user-module syntax, not a host Babel implementation or
  substitute require/dependency. Native code derives the required helper from
  actual import AST records and interopDefault. Existing finite binding/shadow
  and unsupported write boundaries remain explicit.
- Mutable export declarations initialize their actual export aliases. Later
  mutable writes are still rejected until a scope-aware live-write pass exists;
  they are not silently compiled with stale exports.
- Native TypeScript enum generation is parsed as its actual resulting program.
  The compiler no longer assumes unchanged source byte lengths. Entirely
  type-only imports are erased before that transform, so enum expansion cannot
  turn erased type imports into runtime side effects.
- Legacy class decorators use actual class/decorator nodes, hygienic temporary
  names, non-Identifier expression evaluation in source order, then reverse
  decorator application. Member decorators, metadata extensions and anonymous
  decorated class forms remain explicit unsupported boundaries.
- Top-level resource declarations receive an actual disposal context, original
  initializer expressions, reverse disposal and error-suppression helper. The
  primary plugin's Program hoisting/var conversion and its observed export
  initialization behavior are retained. Nested resource scopes, anonymous
  using-initializer naming and resource/exported-function hoisting remain
  explicit unsupported cases; no dummy disposal or successful fallback is used.
- Empty actual custom-plugin iterables add no plugin, following the real spread
  rather than assuming array length proves emptiness. Nonempty custom plugin
  execution still requires its genuine implementation.
- retainLines:false now invokes a native token printer over the actual output
  tree. It preserves original line terminators carrying ASI/return meaning and
  treats strings, templates, regexes and comments as actual token regions.
  This is not a claim of exact Babel whitespace or function-text parity.
- Inline maps are derived from the actual source string and the actual fixed
  empty Babel source-file-name profile. The retained Babel source-map code and
  gen-mapping0.3.13 implementation skip empty-source mappings but retain source
  content. The map's empty mappings/names therefore follow that specific
  algorithm; no invented location map is supplied. Alternate filename,
  sourceRoot/input-map and unrelated Babel options remain unadmitted.

Both original JSX-in-.ts and malformed-input failures now reach actual native
parser validation. A genuine VM SyntaxError contains the actual deepest/leftmost
tree failure position, converted to UTF16 index/column. It is returned with an
actual error stub/result. Native error code PI_JITI_NATIVE_PARSE_ERROR and native
wording explicitly distinguish this diagnostic from Babel's parser. Babel/V8
wording, exact location choice and stack remain raw negative comparison axes;
the implementation does not forge BABEL_PARSE_ERROR or use authored positions.

Native helper templates derive from the actual licensed Babel helper algorithms.
Their generated identifiers are compiler-private/hygienic; source is never
selected by a testcase name or matched to a captured answer. The new official
primary files are inert, version-bound to the accepted jiti pnpm lock. The
gen-mapping archive also matches that lock's original SHA512 integrity. All
license bytes and file hashes are retained under authority/primary-pins.json.

## Verification preparation and limits

The same original30 target retains full native/original code, errors, function
text and every original row. It now reports compiler completion/category matches
separately from exact output/diagnostic and public evaluation comparisons. The
strict assertion still fails exact mismatches after writing every observation.
No unsupported result can pass merely because a frontier was labeled as such.

Sixteen additional generic original input programs are prepared with no expected
or observed output. They exercise import combinations, enum/type-import offsets,
mutable declaration, computed/optional meta, local bindings, decorator order/name
collisions, resource order/nullish values, empty plugins, maps and return ASI.
They do not replace or enter the original thirty-row capture automatically.

One separate GPA lifecycle test is authored for Zig allocation cleanup across
the actual syntax/module/printer passes. It uses the standard original baseline
and every original failure index; it is uncompiled/unrun. There is no baseline
count or GPA pass. C parser allocations, VM memory and fatal behavior are outside
that GPA-only scope and require their own actual controls. This target is not
attached to default tests and has no execution grant.

Exact generated bytes, complete reflection/diagnostics, broad syntax and
scope-aware mutable updates remain unqualified. Resource/decorator behavior,
helper execution, parser positions, ownership, allocator/GC behavior and all
frontier support still need actual granted compilation and execution. The first
comparison may produce material negatives; those raw inputs/results must be
retained. The full twelve-evaluation path still requires the genuine completed
public profile/createRequire/compiler graph and cannot be filled with stand-ins.
