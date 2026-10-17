This is a source-only successor to a2515a4af6c1c3b3ada40ffc03aea4fc2be4d466.
The original a251 packet and C8A44058689AEA991DAE49ED8C7014BE1A653CD4580452CC5CDD1EDD41992417
collector remain byte-identical. No compiler, AST, Node or native job has run.

The finite review findings are corrected directly:

- options.paths dedup reads lookupPaths[j] for Includes and, when absent, reads
  it again for Push. A public Module._resolveLookupPaths override can expose a
  different second value or throw the exact second-read reason.
- _resolveLookupPaths returns paths only when paths.length > 0, using the actual
  numeric VM comparison. An escaped private array and a species-created result
  can distinguish this from truthiness.
- the four native guard implementations now use one CommonJS-private helper.
  It first captures an actually pending completion without changing its flag,
  and otherwise mirrors linked QuickJS JS_ThrowInterrupted: create the actual
  InternalError, own that real reason, mark it uncatchable, then capture it with
  diagnostic coercion suppressed. No stale captured value or rejection-data bit
  is used to infer a current failure. No generic C/Engine/Module helper changes.

reference-corrections.mjs is a separate prepared original Node caller. It mutates
the actual public Module lookup methods and an escaped array's species solely
inside its dedicated child, with restoration and controlled paths. Those are
deliberate Source inputs, not substitute production namespace dependencies.
It has six prepared observation rows; no expected or observed output exists.
The original C8 collector's future wrapper does not execute this new caller.

native_node_commonjs_corrections_test.zig has five prepared named controls:
actual guest-catch bypass through the genuine ordinary VM callable for cancellation
and native-budget pressure, stale captured-flag isolation, and exact current
pending fatal/ordinary identity. Unexpected owned results are freed on assertion
failure. These test the actual private helper and callable failure transport;
the five production call sites are statically reviewed. No claim that removing
an entire call site is detected by this helper-only unit is made. Actual compiler
metadata/imported-anonymous counts remain unknown; no runtime pass is claimed.

All original missing real Node/CommonJS collaborators remain explicit. The
ordered builtin table remains absent, the new bodies are unselected, and no
default Node/CommonJS/jiti/Graph2 or addon compatibility is qualified here.
