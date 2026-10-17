# Incomplete source implementation checkpoint

Base: 328eab6e4536eec1632edfef47ab376440b5ac45, reviewed strict/top-level CallSite source over C3 DA14/A79.

Root authorized the actual CJS function-body compiler and detached parse-only ESM probe. This first implementation checkpoint factors the real ordinary function directive/name/body/using/return-epilogue parser into a terminator-parameterized helper. Existing declarations still call it with their exact closing-brace terminator and save their original source. The new intended caller will use TOK_EOF directly over the original body. No wrapper text or outer program is parsed/evaluated.

No new compiler/probe entry point, header, diagnostic completion channel or controls exist yet. This is incomplete, uninvoked scaffolding and not an execution/intake candidate. Exact trusted grammar/error construction categories, allocator/regexp failure provenance, parser/FD/realm ownership, actual line origins, detached module cleanup and causal controls remain to implement and independently review. The existing body parser behavior has only been statically compared; no equivalence execution is claimed.

No compiler, formatter/AST/parser, generator, Node/native, metadata or test job was run. No Main, Engine or frozen link worktree edits occurred. Governing design is immutable Core 2f3f170cec6a151d126e075d70a0507b37a87284, with Node/V8 original wrapped-source primary; no fabricated metadata/cache outcomes.
