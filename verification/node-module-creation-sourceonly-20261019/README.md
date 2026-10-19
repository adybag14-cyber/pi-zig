# Genuine Module creation component — source only

This unit ports the retained Node v24.14 constructor, makeRequireFunction,
createRequire/createRequireFromPath and _nodeModulePaths bodies onto the
canonical checked Node operation and owned completion boundary. It adds a
private bootstrap for their real shared Module constructor. It has not been
built, queried for metadata, run natively, or captured with Node.

## Actual composition

The private core takes the real default values from the process/path built-in
registry, the completed argument/inspector/Stream graph and the actual internal
file-URL owner. The existing shared Module constructor owns the same CommonJS
cache and private lexical records. createRequire reads that completed lexical
constructor; it does not follow mutable Module.Module or construct another
loader facade.

Constructor staging completes before publication. Both Graph outputs and all
seven Prepared outputs are adopted through the actual owned boundary. A
completed reentrant winner is retained before a losing candidate retires. The
createRequire declaration has its own completed private cache so a retry after
a later core failure reuses the same declaration and constructor.

The original endsWith function is obtained from the completed argument-message
owner's existing capture. The new argument-owner accessor does not add another
primordial snapshot or change the message Inputs ABI. The broader constructor
capture remains a startup operation before guest modules; the eventual full
public assembler must preserve that timing.

_nodeModulePaths retains the actual twelve-element nmChars Array. Every
selected indexed read goes through the checked property operation, including
out-of-range indices that can invoke an inherited Array.prototype getter.
The indexed operand completes and retires before the matched-count update.

The existing v24.14 public loader composition has not been replaced. The
private creation component is a dependency for the complete same-Module
_load/_resolveFilename/_compile/extension-handler/Jiti graph.

## Declared validation entrypoint

- Target: build-native-node-module-creation
- Root: src/native_node_module_creation_test.zig
- Filter: native actual Module creation
- Installed Windows artifact: native-node-module-creation.exe
- Declared controls: 24
- Genuine Node observers: 17
- Native identity, lifetime and producer controls: 7

The target only installs the filtered test artifact. It has no run dependency
and no addTest name override, preserving the root controller's canonical
cached test.exe/test.pdb protocol. Declared counts are not metadata results.

The fixture installs the actual process/Stream/os/path owners and then the
private core. Its test view contains those same objects. The context controls
observe the actual newly created Module through a normal inherited filename
setter; they do not supply a substitute constructor or completed namespace.
The live-dispatch controls mutate real public methods only for their selected
observer, then restore them.

Two native controls retain a progress record before the operation and inspect
only its own numeric fields after an actual fatal. Both require the exact first
producer reason and dirname/path/catch counts 1/0/0. A real C holder finalizer
tests expression retirement before the next setter. Ordinary private DATA and
successful flagged DATA run in separate fresh Engines. Probe storage outlives
Engine teardown, and fatal injection is disabled before teardown.

## Source authority

authority.json points to the existing immutable Node v24.14 source packet and
its independently admitted original executable/capture. This intentionally
preserves the original Module/Jiti authority rather than silently changing it
to the separate v24.13 filesystem authority.

The authored node-source-observer.mjs checks exact Node version and executable
SHA-256, accepts exactly one declared observer name and invokes it against the
real node:module/node:path/node:process objects. It launches no child process,
loads no candidate implementation and creates no output file. Root must grant
and supervise each execution independently.

The two warning observers require a fresh process with the explicit
--pending-deprecation flag. All other observers require the normal startup
option. No observer runner has been executed for this unit.

## Finite source reviews

- SDK reviewed makeRequireFunction against helpers.js 144–188 and the
  constructor/host statement slice against the retained loader/util bodies.
- VM reviewed constructor publication, accessor ownership and actual
  rest/warning/captured ReflectApply behavior.
- SDK closed the actual nmChars Array/indexed-read correction and the remaining
  requested reverse-scan slot/callee/last-assignment slice.
- VM closed createRequire/core and the completed original endsWith accessor.
- SDK closed observer/control declarations 1–8 and 14–15 plus the genuine
  Fixture/Probe and native declarations 18–24.
- The VM peer for observer declarations 9–13 and 16–17 is pending as this source
  packet is prepared.

These are bounded source reviews. No execution or full public Module
qualification is implied by their closure.

## Explicit remaining work

The VM owner is providing the actual opt-in synchronous argument owner and
constructor-realm prototype bridge. The current borrowed argv convention
cannot yet reproduce original-parameter retirement when _nodeModulePaths
assigns from = path.resolve(from). This unit neither frees borrowed argv nor
claims that mutable-parameter slice qualified. Its path observers use primitive
string arguments.

The actual Object-prototype fallback for a foreign new.target realm remains a
shared ModuleCallable dependency. The existing private-parent owner remains
bounded by its previously recorded private-property/proxy limits. Exact
cross-version behavior of the reused v24.13 error/URL dependencies outside the
selected v24.14 bodies remains a separate qualification task.

Complete loader/public namespace installation, file handlers, module cache
loading cycles, Jiti, TypeScript, ESM and TLA are subsequent actual source
composition work. The public tool/queue/edit-diff owner follows that graph.
