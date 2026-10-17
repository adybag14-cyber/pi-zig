This packet implements the ordinary jitiRequire and jitiResolve bodies from
jiti 2.7.0, immutable source fd3bb289b75ed207edfb686d671ed50144f7e90f.
The implementation is Zig. The linked VM executes user input and real ordinary
native functions. No production JavaScript host, Node bridge, module facade or
identity dependency is added. This is source-only and has not been compiled.

`native_jiti_resolve.createConstants` creates owned copies of the two actual
module-scoped RegExp literals; the module owner must share those same two values
across every instance/call and free its own references after function rooting.
`Inputs` contains genuine pathe/mlly/isDir bindings and those constants.
`resolve(engine,inputs,ctx,id,options)` returns an owned raw result. `create`
returns the genuine ordinary jitiResolve declaration (length 3).

`native_jiti_require.Inputs` contains those resolver inputs plus real Node
fileURLToPath/builtinModules/readFileSync, pathe extname/isAbsolute, mlly
pathToFileURL, actual debug and the actual ordinary evalModule frontend.
The immutable is_windows value is the actual std-env module initialization
result. `require` and `nativeImportOrRequire` return owned raw values/Promises;
`create` returns the genuine ordinary jitiRequire declaration (length 3).
No outer Promise, fake AsyncFunction or implicit Await is introduced.

The factory owner is typebox_operators_resume; the missing actual mlly/pathe
policy owner is models_refresh_resume. The reviewed interop/module-cache leaves
and the real Node.Module callable owner are explicit composition prerequisites.
They are not copied over newer Root helpers by this packet. Root a45 CommonJS
currently lacks require.extensions, resolve.paths and option-aware resolve;
its SourceLoader normalization hook has no conditions/extensions/paths policy.
Those cannot satisfy these dependency slots by renaming a function. Real
nativeImport must be the linked-VM module operation after its separate gate.
The transformed evaluation hostbody alone is not evalModule's full frontend.

Resolver order is native regexp, tsconfig candidates, aliases, parent-directory
adjustment, explicit/import/require condition attempts, direct native resolution,
per-extension/index and JS-to-TS fallback, then try/last raw rejection. Require
order is parent cache creation, protocols, builtins, virtual modules, tryNative,
resolution/format/native classification, cache, utf8 read, actual eval frontend.
Source catches retain raw ordinary reasons; fresh private host failures escape
with exact identity before fallback/iterator cleanup. Imported callbacks retain
real captured values through VM function-data tracing, not native borrowed refs.

`source-caller.mjs` is a prepared genuine reference caller only. It imports the
exact admitted official jiti factory and real bundled Babel transform supplied
as explicit paths, creates original owned fixture modules, and calls actual
jiti APIs. It does not execute the native candidate or a subject stand-in.
The later controller must pin those source/package bytes, version/inventory,
owned directory and permission/network/process/resource fences separately.
No such grant or execution is implied here. Source expectations are absent.

The additional causal matrix describes direct source-boundary inputs and native
fatal/GC cases not available through the public jiti API. No synthetic result,
golden, successful capture or full jiti/default-loader claim is present. Previous
Source48/39, CJS19/39 and OpenAI58/52 authority packets remain immutable.
