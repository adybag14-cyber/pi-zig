Source-only successor to e07c7f903a0d982133d0648a9c9084f3fade112a.

Independent Body review accepted the helper's fatal and same-object ownership,
but identified that versions.run retained an unused catch {} reason through
mode-4 fallbackTarget. All four synchronous handled version catch modes now
call package_catch.ignore before entering the shared recovery branch. Borrowed
async rejection input still receives only guard checking; named withProgress
and Git catch(error) retain their owned binding through actual use.

The prepared same-object native test now defers old-binding cleanup on every
failure path, disabling that defer only after its deliberate early free.

Original Source/goldens and all previously prepared class inputs are unchanged.
No Node/Source/Zig formatter/AST/compiler/native/C job ran. Static diff checks
only; no runtime or ownership qualification is claimed.
