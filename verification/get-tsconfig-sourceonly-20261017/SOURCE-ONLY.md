# Actual get-tsconfig4.14.0 consumed exports — source only

The implementation ports the getTsconfig(searchPath) and
createPathsMatcher(tsconfig) path consumed by actual jiti2.7 src/jiti.ts51–68.
It is native Zig over linked C VM values, supplied actual Node fs/path/Module/
process bindings and actual filesystem effects. It is not a host loader,
constant-negative matcher, empty-config replacement or package registration.
Composition must retain one namespace per realm and preserve the actual library
require/cache identity. Main and shared helpers are unchanged.

The primary npm get-tsconfig4.14.0 archive is SHA512 verified and retained inert,
with every member, MIT license, exact registry metadata and gitHead
24bc5a798af42c3725b9bbb8a9ae9566e4293120 source. Source package.json is the development
manifest; published package.json identifies the actual4.14.0 release. Its build
lock fixes jsonc-parser3.3.1, slash5.1.0 and resolve-pkg-maps1.0.0. All three
original archives, members, integrity metadata and licenses are retained.
jsonc-parser is bundled into the published product, not an optional strict-JSON
substitution. Microsoft MIT attribution applies to the JSONC port.

Implemented algorithms:

- Search up through real existsSync calls; per-call actual Map caching of fs
  results; fresh config objects on each parse; native JSONC scanning and tolerant
  recovery, UTF16 strings including isolated surrogates, duplicate/prototype
  assignment, comments, incomplete containers and number/string recovery.
- Relative/absolute/package extends, optional actual Module.findPnpApi hooks,
  package tsconfig fields, exports conditions/arrays/wildcards and blocked paths,
  scoped packages, .json/directory fallbacks. No PID/process or fallback host runs.
- Reverse extends-array precedence, independent circular trackers, reference
  removal, implicit-base Symbol ownership, inherited path rewriting versus literal
  pattern prefixing, output exclusion defaults, watchOptions, configDir expansion
  and actual compiler-option defaults from the pinned source.
- Exact paths before wildcard paths, longest wildcard prefix with original tie
  order, UTF16 string slicing, replacement semantics, baseUrl fallback and POSIX
  relative-specifier guard. Matchers retain actual private state through GC.

No full package API is advertised. getTsconfig optional configName/cache/includes
parameters are outside the consumed caller and explicitly refused. In particular,
the includes=true createFilesMatcher branch is not silently simulated. Full
public namespace/findTsconfig/parseTsconfig/createFilesMatcher exports are absent.

Remaining dependency and verification gates:

- Composition must provide the genuine fs, path, Module and process objects.
  The actual CommonJS/Module graph, including optional PnP capability identity,
  is owned separately; this work does not manufacture a missing Module object.
  Existing Node path/filesystem Unicode, error and OS behavior remains a real
  dependency gate. No actual native execution or Source comparison has run.
- Native JSONC nesting is capped256; extends and package-target nesting are
  capped128. These are explicit uncatchable host resource quotas, not parity
  passes. All ordinary Source catches preserve fresh fatal bypass.
- Broad realm mutation of builtins/prototypes/proxies and custom iterators is
  unqualified. Internal native loops currently rely on the dense arrays produced
  by JSONC/Object.entries; the public actual jiti caller supplies plain parsed
  data. Invalid substitution map shapes still enter the real VM map operation.
- Native ABI/syntax/allocator checks have not run. Formatter, AST, compiler,
  Node, generator, parser execution and runtime jobs remain prohibited until a
  separate Root grant. No public/default selection or build target changed.

Prepared original inputs are real filesystem text,19 searches and14 specifiers.
The common subject program defines42 observations:2 export metadata +19 configs
+19 matchers +2 cache/capture observations. The original capture imports the
actual supplied package entry, builds a fresh physical fixture and writes a new
result only; the native comparison reuses that exact retained root. No expected
JSON exists. The separate original public-jiti caller invokes actual createJiti
and resolve; it does not replace the factory or patch internal functions.

Three standalone native controls are authored for UTF16 units, fatal nesting
quota and every Zig allocation failure in scanner/partial-value cleanup. Two
assembly controls compare the whole original observation and retained matcher
after GC; they require actual registered dependency identities. None ran. Full
assembly allocation coverage still needs the genuine Module graph and a granted
owner. These controls are prospective inputs, not an accepted proof.
