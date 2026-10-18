# Private consumed ignore7.0.8 supplier — prepared source only

The actual SDK package-discovery implementation calls the bare `ignore()`
default with no options, retains the returned matcher during recursive walking,
calls its live `add(patternsArray)` method and calls its live
`ignores(relativePosixPath)` method. Directory inputs end in `/`.

`extensions/native_sdk_ignore708.zig.createDefault(engine)` supplies that private
default callable. Its returned JSValue is owned by the caller. Pass it unchanged
as `native_sdk_package_assembly.Inputs.ignore`; the assembler/discovery captures
the value. One Engine retains one default factory; factory invocations construct
distinct ordinary matcher objects. No importable or global `ignore` module is
installed. The implementation is Zig plus calls into the linked C VM, with no
production JS/TS/Node host, no minimatch alias and no constant match result.

The implementation ports the original package's rule manager, ordered negation,
directory parent exclusion, cache aliasing/invalidation and Windows path policy.
Its separate source-specific gitwildmatch compiler preserves escaped literals,
space-only trimming, BOM/CRLF handling, POSIX bracket classes, slash exclusions,
out-of-order ranges, globstars, pending trailing-wildcard markers and pinned
wildcard runs. VM strings and real VM RegExp objects retain UTF16 and native
regular-expression semantics. Literal compiler-step syntax is checked separately
against the actual primary file; that data comparison is not execution proof.

The actual default factory, Ignore/RuleManager/IgnoreRule constructor names,
ordinary fields, live consumed methods and required internal prototype methods
are represented directly. Source helpers needed by `add`/`ignores` are retained;
other Ignore library methods (`test`, `checkIgnore`, `filter`, `createFilter`,
legacy `addPattern`) and named exports/testing setup helpers are outside this
private supplier. This is not a complete replacement namespace for user imports
of the npm package. Initial module construction assumes the actual platform's
standard VM intrinsics, and reads the real `process.platform`; it does not invent
a Windows process or force another frontend's path policy.

Raw producers use the exact cd145 private VM adapter
`native_sdk_chalk_scope.zig`, with the already intaken reviewed SDK completion
helper SHA41AAFFBFED0B2B598D51E8B46432E1B53A373BA101DC7B0F4C396201E65432B6.
This preserves a real body outcome before temporary retirement and qualifies
only actual pending private allocation events from individual operation/release
generations. Captured errors and old tagged DATA are not broad allocation tests.
Every real callback has its native entry/invocation boundary; the public supplier
adds its own guarded initializer and commits its cache after completed cleanup
and final normalization. Reentry cannot overwrite another cached default.

The shared `native_node_function` / `native_class` construction internals and
atomic VM allocation operations retain their separately unqualified frontier.
The local adapter does not recover events already discarded inside those shared
helpers. This source-only checkpoint makes no full-factory allocation-safety,
Source replay, production, default SDK or whole-application qualification claim.
The borrowed raw adapter is private and assumes the actual guarded entry path or
an already normalized preceding operation; it is not a general pending-event API.

`primary-provenance.json` binds the exact original installed ignore7.0.8 members,
MIT license and current Pi package-manager consumer to the accepted original31064
current-byte authority EFEC9629751FA119BE0B311D206A7F8A10A5A9E31213482FBBF647C6B6C11CF0.
The original recovery lifecycle negative remains unchanged. The matching package
has no runtime dependency imports in its index file. Actual reference captures
must still seal the complete accepted runtime, Node distribution and all control
inputs before and after their bounded owned child.

The byte-identical shared caller/native fixture plans 246 ordered observations:
23 eight-path rule matrices with rule/lazy snapshots, plus 16 receiver, cache,
raw-error, live-regexp, shape and path-policy controls. It captures outputs from
the actual package; no expected output JSON is authored. `capture-primary.mjs`
imports the genuine original CommonJS entry and checks those authored IDs.
The false config template is not an execution grant.

Three native test names are prepared: semantic/compiler/cache/receiver/GC
controls, actual first ordinary A versus native cleanup B plus fresh raw pending
OOM and historical DATA, and initializer reentry/cache cleanup. These use real
native finalizers and allocator producers for causal checks, independently from
the original Source observations. Actual compiled test metadata is unknown.
No Node, source capture, Zig fmt/AST, compiler or native test has run. The shared
build file, Main, accepted runtime and historical captures/goldens are untouched.
