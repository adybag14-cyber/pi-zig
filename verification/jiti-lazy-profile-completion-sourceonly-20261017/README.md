# Public profile lazy provider completion revision2 — source only

Root authorized this correction after the independently closed6ad public
wrapper/profile unit was intaken. Original6ad code/manifest/review/readback remain
immutable Git authority; the old control file is also retained byte-for-byte
in authority/original-6ad-controls.zig.txt. No Source expected file is edited.
The actual public wrapper/lazyTransform/onError/nativeImport implementation,
canonical core/frontend/require, C/H, Engine and shared helpers are unchanged.

## Concrete correction

Old profile.complete(engine,&Prepared,alreadyLoadedBabelModule) required a
loaded cache record before the public namespace existed. Even a genuine new
Module would become observable too early through require.cache and could have
the wrong first parent. Pinned lib/jiti.mjs loads Babel only when lazyTransform
first calls the actual createRequire(import.meta.url)('../dist/babel.cjs').

Revision2 is profile.complete(engine,&Prepared), TWO arguments. It hard-wires
the actual native_node_commonjs_converted_provider.register/ready API against
the exact staged constructor/physical Babel filename/native backend export.
Registration stores a real ordinary five-argument native CJS body in the
authenticated canonical ctor's private provider map. It does NOT construct a
Module, read/write Module._cache, choose a parent, set loaded or execute the
backend. Only actual readiness admits Engine's real ESM exotic namespace.

The first real lazy require resolves/loads the physical Babel path using actual
Node/CommonJS createRequire/_load/load/extensions/_compile. The registered
body is selected inside real _compile only for explicit commonjs format with
initialized unpatched wrappers. Thus actual _load supplies the real new Module,
cache-before-initialization and real createRequire dummy parent at the correct
time. Other formats/patched wrappers still need the real compiler/wrapSafe.
No lookup-only require, fake namespace, eager Module, empty registry, generic
undefined callback, always-throw bootstrap or Node bridge is introduced.

All prior entry/post-guest pending guards and exact error ownership remain.
The profile checks actual VM pending status after register and ready and before
namespace publication, preserving actual events without formatting. Repeated
successful complete returns the same namespace. Failed completion stays failed.
The actual provider registration is context-owned and retains its genuine
backend; no registration/namespace graph reclamation or arbitrary retry policy
is claimed. Prepare remains a once-per-actual-module host operation; conflicting
providers for a physical filename fail closed rather than silently overwrite.

## Actual required dependency, not an inferred closure

This source directly imports the sealed, independently reviewed b0efd1a2 API
from worktrees/node-jiti-commonjs-core. Its exact provider SHA256 is
22AF40935E75D8BD371B5876AE817946344CE6301A7AB17CF8F39A6974768EC8;
the inert exact source is retained here for peer review. At authoring Main
b34833e8 and this isolated base do NOT yet contain that new provider leaf.
Its constructor pathObject/convertedBody/retainConvertedBody + canonical private
map and genuine prototype._compile dispatch are a REQUIRED separate Auth-owner
intake. No older vendor, fake host callback or copied whole CommonJS branch
fills that dependency. Root will consolidate only the independently closed
minimal Node source unit. Native compilation/execution is deliberately unrun.

Full genuine createRequire, actual _load/wrapSafe/compiler/platform dependencies
remain unqualified. The underlying native transformer keeps its explicit
grammar/options/code-format/diagnostic frontier. The change is source-only,
unselected, expected-absent; it does not establish whole factory/SDK readiness.

## Revised genuine controls, all unrun

- Actual canonical constructor/cache remains empty before/after namespace
  readiness. No host-created Babel Module is supplied to make it positive.
- An instrumented real canonical Module._cache getter throws if it is read.
  Lazy readiness must succeed with zero getter reads and an empty real cache.
- Actual pending event before complete still wins before phase/registration.
- First lazy transformation uses the real createRequire/_load pipeline and
  actual retained physical Babel file. Only then must the real loaded Module
  appear, with exact native exports/filename/loaded state and actual parent
  filename derived from the real module URL. A later call keeps same Module
  and same real parent. No fake constructor, compiler or require is supplied.
- Existing actual constructor/new metadata, conditional options/getter/spread,
  shared lazy identity and current-event-over-real-loader-success retry controls
  remain, with original Source factory authority and expected files preserved.

Positive subjects still require the actual complete bootstrap. Inputs are not
replaced with stand-ins and no prepared control is claimed executed.
