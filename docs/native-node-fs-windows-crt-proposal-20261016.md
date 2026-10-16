# Unselected Windows CRT descriptor ownership proposal

Status: source-only proposal, not imported, selected, compiled or executed. `selected_after_independent_review` is false at both external-call entry points. The current writer operations guard Windows installation with `RequiredReviewedWindowsCrtDescriptorBridge`; neither a numeric HANDLE nor an invented token is published as a Node fd. No C, QuickJS or Engine source is changed. Body's independent API/ownership review is required before selection.

Microsoft documents that `_open_osfhandle` associates a genuine CRT descriptor with a Win32 handle and transfers close ownership to that descriptor. After successful association, `_close` owns both descriptor and underlying handle; a second `File.close`/`CloseHandle` is invalid. The private `std.Io.File` view therefore becomes a borrowed IO capability only. [_open_osfhandle](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/open-osfhandle?view=msvc-170), [_close](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/close?view=msvc-170).

The exact Node24 libuv implementation supplies a primary failure precedent: it calls `_open_osfhandle` after CreateFileW, closes the still-owned Win32 handle if association fails, and publishes only the returned CRT fd on success. Its close path uses `_close` and reports failure instead of claiming closure. [Pinned Node24 libuv Windows fs implementation](https://raw.githubusercontent.com/nodejs/node/v24.14.0/deps/uv/src/win/fs.c).

## Proposed flags

The supported source writer flags are `w`, `wx`, `a` and `ax`. Native file creation happens first. Association does not perform a second open, truncation or creation.

| Node flag | Native create disposition | Append IO | Proposed CRT association flags |
| --- | --- | --- | --- |
| `w` | Create or truncate | false | `_O_WRONLY | _O_BINARY | _O_NOINHERIT` (`0x8081`) |
| `wx` | Create new exclusively | false | same (`0x8081`) |
| `a` | Create if absent, retain content | true | above plus `_O_APPEND` (`0x8089`) |
| `ax` | Create new exclusively | true | above plus `_O_APPEND` (`0x8089`) |

The pinned Zig Windows fcntl header supplies `_O_WRONLY=0x1`, `_O_APPEND=0x8`, `_O_NOINHERIT=0x80` and `_O_BINARY=0x8000`; its SHA256 is `D5F509A50CA32E344A88A8DBAB1D657CA0F035CB636E5F71A1ECB099D857FDAF`. Binary mode prevents text translation. No-inherit adds descriptor protection to the already non-inheritable native handle. Microsoft describes those modes on its open API page; its `_open_osfhandle` page enumerates a smaller flag subset, so acceptance of this exact combination by the pinned linked CRT remains an explicit independent review item. [_open/_wopen flags](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/open-wopen?view=msvc-170).

Append must remain an actual kernel append write. Body review identified that the existing direct NtWriteFile append helper is outside `Threaded.Syscall.start`; Group cancellation therefore cannot prove retirement of that call. The new packet now rejects Windows append before opening a file. A future cancellation-aware append owner must preserve actual append-only/kernel append semantics; ordinary writes on a generic-write handle or seek-then-write are insufficient. The `a`/`ax` association masks above are a proposal, not an admitted IO path. Mode/umask, share modes and additional `r+`/numeric/open flag families remain unqualified.

## Ownership transitions

1. Before association, `NativeOwned.file` is the sole close authority. Failure retains that file and captures errno immediately; its exact rollback closes the native handle once. No invalid descriptor is passed to `_close`.
2. Success clears `NativeOwned.file` and creates one `Lease` with the actual CRT fd, a native generation and the borrowed file view. The registry is keyed by that real fd; its generation is internal ownership metadata, never a public descriptor substitute.
3. Each async open/write/sync job retains its exact lease and native reservation generation before submission. Borrowed IO count is owner-only and released only after the real operation has returned or its cancellation is fully retired, including abandoned task cleanup. Worker packets contain native storage only.
4. The owner freezes admission immediately in `closing_wait`, including while existing IO is pending. At zero in-flight IO it enters `closing_submitted` and returns one separate native ClosePacket; repeated requests produce no second packet. The packet carries the reservation generation and a unique close-attempt sequence. A native pre-reserved claim rejects duplicate or stale copied packets before `_close`. The worker never reads or mutates Lease fields; it release-publishes only its result. The owner acquires that completion and updates phase before callback. Provably unsubmitted work can return to `closing_wait`; admission stays frozen, and a new attempt sequence prevents the discarded packet from closing later.
5. Failure publishes its exact errno once. It neither blindly retries a possibly reused fd nor independently closes the original HANDLE. A 64-slot native-only registry reserves capacity before native open and retains failed-close records without allocation, Engine or JS roots. Failed slots are not silently recycled or called absent. Successful close releases its reservation. Association-failure rollback must also release its reservation after exact native close. The registry and separate worker packet are authored in the unselected proposal; real default-operation integration and all failure gates are still required.

## Native filesystem interaction and gates

Default `node:fs` open/write/writev/fsync/close operations must all share this same actual descriptor registry. Open transfers its result only after every fallible owner allocation succeeds; abandonment closes an unadopted result after worker retirement. `_destroy` cannot close a borrowed file while writes remain active. Stream `fd` becomes null at the original close-submission point while the close job retains the real lease privately. `autoClose:false` leaves actual ownership with the native fd registry until explicit close or host shutdown.

Existing path-oriented readFileSync/writeFileSync/appendFileSync (and their promise wrappers) now explicitly reject numeric descriptor inputs before path ToString or file side effects. They cannot reinterpret a published CRT descriptor as a filename. Registry-backed descriptor reads/sync methods, proper promise FileHandle forms and currently missing readSync/closeSync/fstat methods remain separate unsupported surfaces. No raw integer-to-HANDLE conversion was found in this stream worktree's earlier node_fs; Body's review corrected that initial wording.

The direct CRT close itself is not claimed cancellation-aware. Integrating its worker into shutdown requires a reviewed bounded native close ticket and detachable wake/lifetime rule; Group cancellation alone is not asserted to interrupt `_close`. Pending-IO retirement, close-worker lifetime, fd registry admission and failed-absence storage must all be closed before selection. The proposal remains unimported and guarded false.

Unknown/foreign descriptors, descriptors closed outside the owned registry, raw FileHandle imports, CRT linkage/ABI, all close-failure races, inherited handles, and GC/OOM/shutdown traces need their own controls. The proposal does not import a foreign descriptor or guess a HANDLE from an integer. Selection requires independent review of the real linked CRT and exact flag mapping, bounded native failure quarantine, single-close transfer, pending IO retirement and prepared full original controls. Runtime recovery and new Root execution grants are separately required.
