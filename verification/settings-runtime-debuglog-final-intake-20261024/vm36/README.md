# Target primitive String symbol hooks

This source-only packet changes exactly two QuickJS guard conditions: split and the shared replace/replaceAll implementation now look up their symbol method for every non-nullish argument. The complete existing owned property access, RegExp validation, JS_CallFree and fallback bodies remain byte-identical.

The primary retained Node commit f657bb8ed86365ff3fdbe32e27563e778b41486a declares 24.14.0. Earlier 24.13 labels for that commit are preserved historical labels, not this packet's version claim. The official 24.13.0 commit def0bdf8abee441cfcbf793a8dc24a6f3b899573 has byte-identical used V8 dispatch, replaceAll, and protector bodies. Exact source URLs, headers, tag objects, full-file equality and excerpts are retained.

There are 36 declared controls using the actual Engine and original String builtins: 20 split controls, 12 shared replace/replaceAll controls, and four actual native-fatal controls. Guest accessors are real hooks on primitive prototypes, not substituted split/replace providers. The native controls use the retained actual native producer and compare its recorded original uncatchable value after a prior distinct ordinary private value.

No public C ABI or header changes. Fresh QuickJS compilation against the selected C is required; an old archive cannot establish this correction. The standalone build is only a projection: compose its exact additive insertion onto the accepted later build.

The adjacent match/search/matchAll object gates are inventoried with exact target authority and remain unselected. No broad String, timer bootstrap, diagnostic-channel or port-completion claim follows from this packet. No native, parser, Node, reference or candidate execution occurred.
