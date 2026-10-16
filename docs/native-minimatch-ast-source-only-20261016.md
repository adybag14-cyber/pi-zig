This is a source-only AST follow-up to 7af3116b. It replaces the earlier
string-recursive extglob compiler with native tree operations based on the
pinned minimatch 10.2.6 AST source. No Zig, formatter, AST command, C compiler,
Node oracle, or native test has run. No C, Engine, namespace transport, shared
helper, build graph, package registration, activation, or publication changed.

The original AST source SHA256 is
`ec35db8358a5a7333dbd6bdb1ea6bd3f03d1433297de7d615f24f7df5fba06b5`.
The exact upstream Pi authority remains
`4dd2b149d155d7369de16ea4dc77c84e9f5ffb24`. The source licenses preserved by
d849736a apply to the source contract used here. The original 92 inputs and
all 68 supplementary inputs, their runners, and their receipts are unchanged.

The new AST represents plain sequences, extglob alternatives, parent pointers,
parent indexes, string caches, magic/Unicode flags, and empty-extglob state.
Parts lists have shared identity so usurp assignments and later splices retain
the original alias behavior. The native source follows this order:

1. Parse with the original default `maxExtglobRecursion ?? 2` condition. The
   condition is `extDepth <= 2`; adoptable nested operators use depthAdd zero.
   Escapes and bracket regions suppress extglob starts before that decision.
   Over-depth operators become ordinary text under the original parser order;
   they are not matched by a new approximate depth regex.
2. Flatten each extglob in up to ten passes, in the original direct-adoption,
   adoption-with-empty-alternative, then usurp order. The direct, space and
   combined adoption maps and usurp result types are represented explicitly.
   Original parent indexes are retained when a child changes parent.
3. Cache strings, then fill negative tails in reverse creation order. For each
   negative node, following parts of each plain ancestor are cloned into every
   alternative. AST tails remain AST nodes, including another negative extglob.
   Clones stop registering negatives once tail filling has begun.
4. Render using the original isStart/isEnd tests, literal-dot/traversal rules,
   negative-alternative end binding, repeated alternatives with a second dot
   pass, whole-segment empty positive fallback, and empty negative state.

The existing native bracket parser, UTF16 transport and original fast-test
selection are retained. The ordinary glob callback now emits only ordinary
glob regex data; it does not insert its own extglob or dot guards. The AST owns
those decisions. Default unescape behavior includes both original replacement
passes and their nonoverlapping prefix consumption.

The new, separate corpus contains 48 original-input cases covering logical
depth two/three and the next boundary, same-operator adoption, space adoption,
usurp, literal and AST negative tails, ancestor tails, negative siblings,
segment-start dot protections, repeated dot alternatives, empty alternatives,
escaped operators and unfinished syntax. Its original-package oracle verifies
the pinned closure and all earlier corpus hashes before creating any output.
It captures either a boolean or an exception name and uses exclusive output
creation. The original expected JSON and native observations remain ABSENT.
The differential test requires that original evidence and is not registered in
the build graph.

The native AST has explicit admission limits: 16,384 constructed nodes,
64 recursive frames for tree operations, and 4,000,000 bytes for each rendered
or cached intermediate text buffer. These are native resource limits. They do
not establish original quota equivalence, safe allocation-failure behavior,
stack safety, cancellation behavior, or runtime parity. Valid source patterns
outside these limits return explicit unsupported errors. The existing numeric,
option and brace-expansion boundaries remain explicit.

Static source and whitespace checks are the only validation so far. The new
representation targets the previously identified default-depth/adoption gap,
but resolving that gap is not proven until the original and native controls
run successfully. Malformed grammar, all previous corpora, allocation/stack
behavior, globstar quotas/interrupt handling, class-suffix allocation cost,
cross-platform execution, and actual PackageManager caller assembly remain
required work. No full minimatch or full Pi qualification is claimed.
