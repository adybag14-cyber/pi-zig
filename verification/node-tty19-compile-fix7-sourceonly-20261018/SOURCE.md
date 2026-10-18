# Seventh actual compiler correction - source only

The five actual errors are pinned, and no original assertion changes.

* winerror.h uses __MSABI_LONG but does not include its definition. The pinned
  toolchain's _mingw.h includes _mingw_mac.h, which defines that macro. Include
  this prerequisite first and keep the SAME Win32/WSA header constants and map.
* The only newly constructed borrowed File in the TTY/CRT family follows a
  successful GetNumberOfConsoleInputEvents or GetConsoleScreenBufferInfo probe.
  These establish actual console input/screen-buffer capability. std.Io.File.Flags
  explicitly defines nonblocking=false for a non-file handle. This is NOT a guess
  about disk/pipe NT mode and NOT derived from public Console.setBlocking.
  The borrowed view remains private/nonowning and is used as the handle identity
  by this console/CRT lifetime. Actual IO still uses the same native console APIs.
  No generic filesystem IO, independent close, transfer or new query is introduced.
* The lease's Close union has exactly closed/failed variants, both handled;
  remove only the compiler-rejected unreachable else prong.
* Give the UTF8 mask's literal the existing u32 width BEFORE its runtime shift;
  the original mask/count/decoder algorithm remains unchanged.
* Copy the original alias-identity MJS bytes unchanged under src and use that
  legal package-relative embed path. The original verification file stays intact;
  import/evaluation filename and ALL assertions stay unchanged.

The manifest records the family-wide related-form inventory and exact pinned
Zig0.16 File/header authorities. There is only one bare winerror include site,
one console borrowed-File literal, one untyped runtime shift, and one bad TTY
embed path in the pre-correction scope; each is corrected. Existing CRT association
receives a complete File from its caller rather than inventing File flags.
The previous entire-src anonymous-empty-struct-repeat correction remains intact.

Microsoft console-handle authority: https://learn.microsoft.com/en-us/windows/console/console-handles
Console buffers/API distinction: https://learn.microsoft.com/en-us/windows/console/high-level-console-input-and-output-functions
The File.Flags decision is grounded in the pinned Zig source's explicit non-file
case; these web references do not imply an observed physical console qualification.

No Node/compiler/parser/AST/native/controller jobs; no Main/sharedC/H/Engine edits.
Physical3a00 remains HOLD until Root's checked same-path ff after actual seventh
negative closure. All seven failed compiles remain negative. Only the original
213245 UNSEALED pair with fresh typed Root grant/new154-role entitlement/fresh
proof+prefix may be reused. New semantic helper units remain separate.
