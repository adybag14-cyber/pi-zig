# Full GitHost source-only successor

This supersedes the bounded projection candidate 3602326d8e2a2b2ddaa836c925b92cf4ff698af1
without rewriting that negative checkpoint or any Source/expected/input authority.
Root requested the full constructor/template surface after reviewing the known
four-field projection gap. This successor has not been formatted, AST-checked,
compiled, captured against Source or executed natively.

`native_hosted_git.zig.create(engine, .{.node_url = actual_module_object})`
returns the real native GitHost constructor. Create it once for the actual
module and share it across consumers/managers, preserving public host-table
mutation, function identity and its private cache. Pass that constructor to
`native_sdk_git_source.create` as `hosted_git_info`; the resulting parseGitUrl
namespace is the existing assembly's required Git input. Neither factory is
selected or installed by this checkpoint.

The authored surface comprises the constructor (length 6), all four static
methods and all 16 public prototype methods in Source order, with their actual
lengths/ordinary method descriptors. The constructor calls live Object.assign
with its actual target, complete host object and seven source-ordered fields.
The native host objects preserve defaults/override order, shared function
identities, protocols, metadata, extractors and all template functions.

Thirty-five pinned template-arrow bodies were textually transcribed into native
Zig functions. `transcribe-host-templates.ps1` reads and hashes hosts.js, accepts
only its pinned expression grammar, and emits those bodies without evaluating
JavaScript. The accompanying JSON records each original field/destructuring/
template. This script does not generate host objects or expected answers; those
source-ordered objects, raw extractors and class bodies were authored/reviewed
separately. The text generator was run locally; no Node/Source observer/Zig/C or
native candidate process ran.

Real VM property/iterator/spread/RegExp/encoder operations implement maybeJoin,
maybeEncode, formatting, the five raw extractors and #fill. Destructuring still
reads fields even when a template does not subsequently interpolate them.
Browse rest arrays retain live indexed reads, including missing-index prototype
getters. URI/error catches use the reviewed package-owned captured-root transfer.
Public addHost and the parser use the actual live host/protocol table objects.

The private #fill brand uses the existing public QuickJS-NG JS_NewPrivateSymbol
API. Its atom is invisible to JavaScript own-key enumeration. Ordinary class
identity is checked before private own-property access so Proxy/exotic receivers
cannot introduce a trap at the Source private-brand check. No WeakMap or other
guest global is used to manufacture the brand, and no instance is held strongly
in a separate brand registry.

The leaf-local constructor owner reuses native_class.zig's existing lifecycle
and GC roots, with intrinsic JS_GetFunctionProto in place of a guest global
Function.prototype read. Shared native_class.zig, Engine and C are unchanged.
The module-captured node:url object still supplies URL by a live property read
at each hosted construction; Pi's parser and unknownHostedUrl independently
read the live global URL as their original bodies do.

The private native algorithm preserves the used max-1000 successful-entry LRU
identity/promotion/eviction/reentry behavior and undefined-result deletion.
JSON.stringify executes on every public fromUrl call, including hits. This is
not a public replacement for the entire lru-cache package/diagnostics API.
Its used-call behavior and broader global/prototype hooks still require the
genuine comparison gates; static authoring does not establish equivalence.

`git-host-full-0fb.input.mjs` prepares separate original observations of full
descriptors, instance own keys, every host/prototype method, direct template
getter order, Object.assign argument shape, constructor reentry/cache identity,
private-brand ordering, subclassing, fromManifest, #fill options, live addHost
and inherited split-ref reads. It uses the original GitHost and Pi functions;
supplied addHost/template callbacks are intentional public-API inputs. It can
use the already prepared full-observer runner with a fresh seal and grant.
Expected output is absent, and there is no successful comparison result.

The historical 50 package controls, four lifetime rows, six pattern caller
cases and first Git/hosted input remain unchanged. Root/Engine/shared flow/C,
application/default selection, release and full Pi qualification are untouched.
