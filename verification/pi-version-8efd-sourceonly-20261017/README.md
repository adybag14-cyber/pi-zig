# Pi8efd current version alignment — source only

The implementation base is Root a45abd95e6335346eb1e860a7a5a0677df0b5148.
The accepted Source is 8efd314fa3d3232ce197d8d7a6a5660530b9d83e. All four
public package manifests declare1.3.0. config.ts derives VERSION from the real
package and main.ts prints that binding alone. This checkpoint aligns current
static native metadata, bare --version, update/reporting callers and both active
and retained legacy MCP initializer version fields with that target.

Management User-Agent now uses pi/<caller-version> (<platform>; zig/<actual
compiler-version>; <architecture>). It identifies the native runtime honestly;
it does not claim a Node/Bun installation. The Source configuration module keeps
its default Node/Bun getter semantics and package-derived VERSION/0.0.0 fallback.
An explicit host-only native_zig profile uses the same native header helper,
with separate configuration and runtime-import cache identities. No guest
runtime-property detection or process.version fabrication is introduced. Actual
default SDK graph construction/selection remains incomplete and unqualified;
the new profile is a capability supplied by a genuine native bootstrap.

Version-discovery PI_OFFLINE/PI_SKIP_VERSION_CHECK gates and install-report's
shared offline gate now use Source string truthiness: absent and empty permit
the operation; every nonempty string, including0,false and whitespace, suppresses
the relevant operation. Telemetry's separate1/true/yes parser, main's packageOffline parser and model-runtime's explicit
undefined/presence contract remain unchanged.

Historical sdk-lifecycle-version-6fb2e78.input.json and its1.1 expected JSON remain
byte-identical. Their existing native process test and assertions remain intact:
after the current SDK constant changes, that historical replay exposes the
version mismatch. It is not a qualified current-version gate. No dual-version
acceptance, output normalization or old-golden edit hides this dependency.
ARTIFACT-MANIFEST.json and generated ae7 catalog provenance also remain unchanged.
The existing release verifier may reject current target versus historical
artifact/catalog identity; this checkpoint does not relax it or claim release
certification. Workspace/source-authority pointers remain unchanged.

Prepared controls are unrun. Two update.zig regressions cover actual flag helpers
and native header construction; native_pi_version_alignment_controls.zig accepts
real configuration inputs for package-derived header/cache identity checks, with
no build registration. source-probe.mjs imports actual8efd config, public SDK,
User-Agent and version-check bodies. Its global fetch boundary throws a retained
marker solely to observe whether real version helpers reach fetch; it supplies
no successful response and does not claim HTTP or update integration coverage.
It records all observations without expected values. The separate future
pi-version-8efd.expected.json is absent and requires genuine bounded Source
capture and independent audit before native comparison.

Still-required physical controls, each on the exact reviewed artifact/Source:

- Original Source CLI --version stdout and native CLI --version stdout, including
  exact bare line/newline and terminal0 under their separately owned processes.
- Real native MCP stdio and HTTP adapters with a real local server retaining the
  initialize request; verify clientInfo.version against the original Source
  runtime's real VERSION wire binding. The low-level generic MCP Client.Options
  default is a separate contract, not another selected adapter initializer.
- Real management request/install-report headers and version query parameter,
  using a bounded local HTTP fixture and current config.version call sites.
- Fresh-process Source package override/config fallback; actual native package
  override with no successful readFileSync surrogate. Do not reuse cached module
  state between different package roots or runtime profiles.

No Node, Zig, formatter, AST, source generator, build/native job, Source capture or
live network request ran. No expected observation, generated catalog, historical
manifest, C, Engine, build target, public registration or Main file was changed.
