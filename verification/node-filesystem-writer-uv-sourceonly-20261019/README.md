# Actual filesystem writer: libuv Windows owner

Status: source-only successor. No build, metadata, runtime, Node reference capture or full WriteStream qualification was executed for this unit.

## Concrete dependency and change

The retained V10 classic realpath cohort reached the genuine filesystem installation and failed at `RequiredReviewedWindowsCrtDescriptorBridge` in the writer installer. This unit replaces that guard with the real libuv descriptor route. It keeps the existing process, Buffer, Stream, filesystem exports, private operation registry and Env I/O workers.

The new `native_uv_fs_write.c/.h` performs synchronous `uv_fs_write` and `uv_fs_fsync` over a borrowed numeric libuv descriptor. Open flags come from the actual platform `O_*` macros. Real open, reference ownership, physical close and published close use the already-intaken shared `PiUvFileHandle` from SDK commit `0f6952d6877af242f3d0eb1e68d4440a56ff4093`:
- C: `56590C33A17FBD7D1A69B8D7E07E6311031B576290858B832B1DFDF7F5AE05B0`
- H: `10E429D64FE65DCC46DAE73B07E5AE2F0672D3B0E40333C99095E32986021D0D`
- actual UVException: `51D61C9725774D27D4E664216162A26F998378470B4EF648D6CE3229C8806E40`

A Windows packet retains that native owner and receives a copied numeric fd before submission. It does not make another CRT association or own an independent HANDLE. The worker receives native data only. Physical close exchanges the descriptor once; the VM completion publishes the closed view before the callback. Failed submission restores the original registry entitlement. Unadopted opens and abandoned packets retire only after the real worker has returned. The existing POSIX packet path remains selected on Linux.

The task retains its memory owner, copied native bytes and path, and a native wake entitlement until completion or joined shutdown. Its worker copies the wake token before publishing done and never reads its packet afterward. C435 selects actual failure before callback-root/native-owner retirement; a thrown completion removes and destroys that task once.

## Build composition

The admitted TCP/vendor prerequisite is VM commit `2b7b761ecdbe7f3b7cfd23768257fd7f9325bc6e`. All original 134 vendor files and source membership remain unchanged.

The original shared helper is `tools/build_native_node_network.zig`, full Main baseline:
`8B2FAD905DC0D32D6E67180874E8E433E1AEFD740AE1861289C3FB891B371B02`.
Its only implementation additions are the shared FileHandle C file and this writer C file in the same `pi-node-network` library.

Main `build.zig` baseline for the accompanying exact intake patch:
`6D5AD0F34455D4867355DECD30EDA71B389AE9932E42A39509BE6E43DFDF8EE0`.
The owned branch predates the TCP build intake, so its build diff also carries the identical original network declaration. Root must preserve Main's existing declaration and targets. `main-build-intake.patch` contains only the transitive QuickJS-to-existing-network link and the new install target. Read-only `git apply --check` passed against that Main baseline; no Main file was changed.

The new target is `build-native-node-fs-write-uv`, root `src/native_node_fs_write_uv_test.zig`, filter `native actual filesystem writer`, installed artifact `native-node-fs-write-uv.exe` on Windows. It declares 12 tests. This is an install-only target. The UV include path is added only to the actual root importing `uv.h`. The same Windows/Linux platform admission is preserved.

## Authored controls

1. Real published operations and private registry captures survive mutation and GC.
2. Scalar/vector byte results, actual flush and close produce independently read binary file bytes.
3. Append preserves existing bytes even with an explicit position.
4. Exclusive and missing-path errors come from actual physical I/O and complete asynchronously once.
5. The actual Web-to-Node stream pipeline uses the real Writable and reaches finish then close.
6. A real completion callback throw preserves its reason and destroys the removed task once.
7. Native open publishes a valid borrowed CRT/libuv descriptor, with independent memory accounting and exact last release.
8. Cancellation before packet execution performs no physical open.
9. An unadopted real open is closed before its memory entitlement is released.
10. Physical close and published close are distinct, with one eventual native owner release.
11. Actual Env Hub shutdown joins the worker and retires its unadopted file without invoking a guest completion.
12. A missing registry descriptor completes once through the real asynchronous task.

SDK has source-peer closed the C helper/raw packet physical slice and controls 7–10. Root's complete read found the signed synchronous `uv_fs_write` return limit; the request now clamps to `INT_MAX`, preserving actual partial writes and suffix retries. SDK closed that exact successor at `62DB3206CE9CE22A723A339F31885B3651E7A2E3CE800FA1C37710B84E4B911B`. VM has source-peer closed the Task/Registry/completion slice at `B846C3C4A77EA3013F4036652B9F0C9C318845F9959C56BC7FF5B29E6AA1F6AB`, Fixture and controls 1–6/11–12 at root `2DB50112F3B60C9D64A639EDB19657CD6C477909A21BE063BE7952F62B536211`, and the helper/intake patch at `8BFDE80A83241C476F014300F0AC31B353B2E1E6E41214E43B0B19BC76498FD2` / `22DE85F9F889446200594AB5A37A82704F84418CAFB9ECA44B46E481217C415F`. The final patch `18876BA5E44483A820632B4DB557413E2363E87FB1B4D19C9715D4F91EF49A5C` removes only the two whitespace-only unchanged context rows from the reviewed patch; its added source lines are identical and read-only `git apply --check` passed again. Root independently read the full production/control/build unit. All receipts are finite source reviews; no execution or broader writer parity is implied.

## Limits retained

This unit does not claim complete Node callback-FS validation, full WriteStream Source parity, ordinary async backing-buffer mutation parity, source reference capture, platform execution, or complete public fs/promises. The existing `native_node_fs_write_stream_test.zig` and its Source8 capture-required declaration are unchanged. The existing copied-buffer packet design is preserved here; the separate genuine backing-storage lease work remains an explicit dependency for broader native I/O observations.

The original V10 negative evidence and all original declarations remain intact. Native execution belongs to Root's separate sealed build/runtime grants.
