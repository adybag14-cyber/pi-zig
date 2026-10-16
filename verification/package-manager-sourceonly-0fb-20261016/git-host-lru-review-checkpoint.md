# LRU review fixes before workspace consolidation hold

Source-only successor to 15c3e3ab7e2d51537cd54014095eb801e8ce7dc5.
Root requested a clean checkpoint and then a hold until the relocated worktree
under C:\Users\adyba\pi-zig is supplied. No files/directories were moved or
deleted by this lane, and no further edits or jobs will run during that hold.

Body independently compared the core default algorithm with the exact retained
lru-cache index.js SHA256 A1B0CE295FAA12144A37BB69880609D7EBCC6054CE0C105B7CB20C9021FCB217
at pi-upstream-89e5c2c0-20261011/node_modules/lru-cache/dist/commonjs/index.js.
It found the core default ordering consistent, with two narrow corrections:

- Ignored Map.set/delete/clear and Array.fill return values now use a direct
  call/free boundary. An ephemeral hook result is retired before any later
  guest callback, instead of remaining in the helper Scope until its exit.
- The three computed-assignment sites identified by review now resolve their
  actual LHS property atom before reading the RHS tail/next/prev value. A raw
  object index can reenter from Symbol.toPrimitive and alter that RHS state.
  connect retains its already evaluated caller-local p/n semantics.

The constructor argv pointer uses the same const-cast convention as the
existing native JS constructor helper. There is no Engine, shared Scope/sdk,
class, transport or C change. Previous checkpoints and all control/Source/
golden files are unchanged. The new correction still needs independent delta
review and additional targeted raw-index/ignored-result lifetime observations
after the relocation hold; the existing five original Map cases are prepared
and unrun. No expected output has been authored.

The original runtime path C:\Users\adyba\pi-upstream-runtime-19cb534-20261012
is currently absent. Read-only checks also found the 4954, 0fb and 4dd Source
node_modules junctions still point to that missing target. This packet makes
no claim that the 31064-file runtime authority is currently intact. A matching
retained index.js supports static comparison only; Root owns full recovery and
consolidation. No reference authority was reconstructed or retargeted here.

Only source edits, reads, hashes and git diff checks ran. Node/Source observer,
Zig fmt/AST/compiler, native/C execution, allocator checks, default selection,
application/release and complete Pi qualification all remain pending.
