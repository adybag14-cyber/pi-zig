# Package catch lifetime and concrete dependencies

This is a source-only successor to `22bec1ffb8bf718a7f0b05b33cb7574a10bd2917`.
No Node, Source observer, Zig formatter/AST/compiler, native or C job ran.
The original Source package file, historical method inventory, expected files
and all 50 previously prepared class/leaf/physical inputs remain unchanged.
All semantic, allocator, default wiring and complete Pi qualification remains
pending. Source declaration coverage is still 98, including 33 async methods.

`native_sdk_package_catch.zig` is private to these package leaves. `take` first
propagates direct OOM and preserves preexisting uncatchable JS reasons. It
rethrows the exact fresh privately tagged allocation reason before ordinary
handling. Only an ordinary JS exception transfers the engine's owned captured
value into the catch binding and immediately sets the engine slot to null.
Non-JS errors never consume an unrelated captured value. `ignore` immediately
frees an unused catch binding. Named catches keep their binding until callback
or rethrow construction completes, then free only that binding. They never
clear a later engine slot by identity: a callback may throw the same object
again. Async borrowed rejection inputs use `guard` without consuming a slot.

The eight changed leaves are accumulator, discovery, resources, storage,
settings/progress, install, versions and Git cleanup. The separately owned
transport environment catch was reported to its owner and is absent from this
patch. Engine and all shared async-flow modules are unchanged. Propagation-only
iterator-close paths are unchanged.

Four native test declarations are prepared in
`src/extensions/native_sdk_package_catch_test.zig`; they are deliberately not
build-registered or executed in this packet. They cover weak-only captured
reason release with actual VM GC and observational finalizer reporting,
old-binding release after a same-object callback throw, non-JS/direct OOM and
preexisting fatal identity, and exact fresh versus stale private allocation
reasons. They do not claim a real allocator-exhaustion result.

The separate genuine class input
`src/extensions/fixtures/package-manager-catch-lifetime-0fb.input.mjs` prepares
four supplemental observed rows: two actual withProgress callback rethrows,
one actual manifest catch and its weak/finalizer observation after owner-run
real GC and job-boundary retirement. It records observations without expected
bytes. Its finish function does not implement or simulate GC. Finalizer timing
is not asserted. The existing 50 cases remain a distinct historical set.

## Exact dependency handoff

`dependency-pins.json` records the actual official lock entries and SHA256 for
every file in the seven immutable installed dependency directories (234 files).
The official authority read here is
`0fbdbd3f8ab1876ac260c0f08226a400759323b8`; parent reports newer 4dd source bytes
are equivalent, but this packet does not advance or independently certify that
newer target. PackageManager SHA256 is
`61BB2F0B434B0F5C48AB6BFACD9DFF1D99084320EECF695755CD32BD88099310`.

| Dependency | Exact import and used boundary | Owner / next dependency |
| --- | --- | --- |
| ignore 7.0.8 | package-manager.ts:37 default factory; no-argument factory at 335/387/499/536/610; matcher.add(array) at 281; matcher.ignores(relative POSIX file/directory path) at 360/409/437/445/519/556/635 | google_runtime_resume; no external runtime dependency |
| minimatch 10.2.6 | package-manager.ts:38 named minimatch; six two-argument/default-option calls at 680-690 in matchesAnyPattern; file path, basename and relative path, then equivalent skill parent paths | minimatch_native_resume; brace-expansion 5.0.12 then balanced-match 4.0.4 |
| semver 7.8.5 | package-manager.ts:39 named valid/validRange/satisfies/gt/maxSatisfying/rcompare; strict default options at 67/71/1196/1518/1533/1566 | models_refresh_resume; six actual functions, no external runtime dependency |
| hosted-git-info 9.0.3 | utils/git.ts:1 default import; fromUrl(candidate) at 187 and 211; reads domain/user/project/committish only | this lane after catch review; lru-cache 11.4.0 plus actual URL parsing |

The assembly already requires actual `Inputs.ignore` and `Inputs.minimatch`
functions, `Inputs.semver` namespace with the six named functions, and
`Inputs.git.parseGitUrl`. It does not substitute a matcher or parser. Function
shape checks are prerequisites and provide no provenance certification.

Ignore must preserve actual rule order, negation/ancestor exclusion, validation
and platform defaults. Discovery shares matcher state during recursion and
prefixes lines from .gitignore, .ignore and .fdignore in that order.
Minimatch must preserve default dot/negation/comment/glob/extglob/brace behavior
over caller-normalized paths; a different model-resolver caller additionally
uses nocase:true and belongs to that dependency owner's broader audit.

The complete Pi Git parser is 226 lines, SHA256
`BFF4590AEFA988BA625026769AC5AD02F02558D59BD7D566F4728E1EE4DA1DA9`.
Its graph is parseGitUrl -> splitRef -> hosted candidate passes ->
buildGitSource/safety checks, with parseGenericGitUrl fallback. It uses real
URL construction/serialization and decodeURIComponent, accepts historical
shorthand only with the git: prefix, splits @ refs without confusing URL auth,
and validates decoded host/path against NUL/backslash/leading-slash/.. escape.
Hosted candidates use actual host extraction/protocol tables, optional www
normalization, encoded fields and ref precedence; a three-host heuristic is
insufficient. The scoped implementation must preserve these used fields and
their failures. The reference fromUrl uses a max-1000 LRU and caches GitHost
objects. A native algorithm cache may replace it only if hidden by the used
Pi parser boundary and documented; exposing a supposedly complete hosted-git
API or fabricated cache object is not authorized by this scoped dependency.

Remaining platform collaborators are real filesystem glob/Dirent/stat/mutation,
path/crypto/environment, child streams and inherited frontend stdio. Concrete
third-party work precedes actual full constructor/default assembly capture;
that precedes native comparison/ownership qualification and full application
wiring. No release or full Pi compatibility claim follows from this packet.
