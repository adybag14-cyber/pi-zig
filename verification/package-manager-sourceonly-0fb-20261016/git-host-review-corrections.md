# Full GitHost independent review corrections

Source-only successor to 92fd1addecaf6305077b2b2ed9bf46adefa94de5. Body's
independent review identified four concrete boundaries, corrected here without
changing Engine, shared Scope/sdk/class helpers, transport ownership or C.

1. Reused Scope.put delegates to sdk.put, whose negative data-definition status
   does not capture the actual pending VM reason. The package-local data helper
   duplicates the borrowed value, defines the same data property and captures
   a negative result immediately. Owned package/Git leaves now use that helper;
   a catch cannot classify an absent/stale captured slot instead of the actual
   reason. The separately owned transport was reported to its owner and remains
   unchanged. Two unregistered native controls prepare absent/stale-slot proxy
   throws and exact fresh private fatal reason handling; they are unrun and do
   not establish real allocator-exhaustion coverage.
2. formatHashFragment's second regex has empty flags, while its other three
   patterns have g. The helper now takes explicit flags. A separate genuine
   formatter input observes each regex's source/flags through the original
   function's supplied replace callback.
3. Pi's inherited split.ref getter receives the split record and can mutate its
   own repo. The parser no longer eagerly captures repo: it reads it only in the
   truthy-ref candidate arm and rereads it for each startsWith/returned expression.
   Separate original controls observe a false ref installing a throwing repo
   getter and a later ref changing repo after the actual hosted call.
4. SCP correction uses JS addition/default coercion, not template interpolation.
   It now finishes the first addition before resolving the second slice and
   does not force String coercion. The separate original control supplies a
   transparent String.slice wrapper and observes Symbol.toPrimitive's hint and
   ordering. correctProtocol retains its actual template/String coercion.

All preexisting input/Source/golden files remain unchanged. The added formatter
and repo/coercion controls are separate files. All expected output is absent.
Only read-only review, source edits, hashes and git diff checks were performed;
no Node, Source observer, Zig fmt/AST/compiler, native or C job ran. The entire
class/default/application and all allocator/runtime qualification remain pending.
