# Actual lazy grammar batch 1, source-only

This isolated batch starts at qualified eager highlighter commit `733800b8b872d86c5766dc4a30cf44ae8d373254`. It adds four actual highlight.js 10.7.3 factory bodies in Zig: `dockerfile`, `makefile`, `protobuf`, and `ini`. Their `create` and `build` entry points use the existing native legacy-function adapter and highlighter Scope. Existing core, compiler, scanner, eager registration, and frontend modules are unchanged.

The authority is the installed highlight.js package under the immutable upstream dependency checkout, covered by the complete 31,064-file dependency manifest. Each original factory's path and digest is retained in `verification/highlight-lazy-batch1-20261015/original-inputs.json`. The authoritative package index contains 191 canonical factories, including 170 outside the existing eager set.

TOML belongs to the actual `ini` factory and its `toml` alias. The installed version has no separate `toml.js`, `graphql.js`, or `hcl.js` factory, and GraphQL/HCL are absent from the 191-factory index. This batch does not invent those factories or replace them with another language.

The new bodies retain Source object field order, shared mode identities, regular-expression versus string values, helper getter order, ordinary receiver calls, Makefile identifier addition/coercion, and the assignment to the live object returned by INI's `COMMENT` helper. INI's private regex concatenation uses the existing native regex helpers, retaining their live array and regular-expression property behavior.

The shared input fixture prepares 29 comparisons: factory metadata, complete raw grammar graphs and identities, live helper access, throwing getters, coercion and setter behavior, twelve scanner samples, actual aliases, and unsupported factory absence. The capture driver loads the genuine installed original factories and core. No expected JSON has been created or inferred. Genuine Source capture and native validation require separately granted resource slots.

Current checks are Zig formatting and Git whitespace only. This checkpoint is uncompiled, has no Source differential result, and does not activate lazy loading or claim these languages are available through the application. Integration must retain the actual 191-factory index order, including re-registration of the 21 eager factories.
