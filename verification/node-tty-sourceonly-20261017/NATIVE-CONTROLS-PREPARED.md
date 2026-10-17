# Actual console/native controls — capture pending

No Node/native/compiler/AST execution occurred. No expected packet is present.
The actual Node24 `original-console-output.mjs` must run only under a separately
granted bounded native fixture that owns a private console screen buffer and
actual stdio/report handles. It must not write the user's terminal or worker JSON
wire. The producer must hold/verify the fixture EXE, PID, creation, command, job
identity and console handles before authorizing these operations.

1. Positive original output: actual private console stdout, genuine fd3 report
   pipe. Capture WriteStream inheritance/columns/window size and real callback,
   Promise/immediate ordering. Native producer reads the actual private screen
   buffer/cursor after acknowledged Node completion. Original constructor's
   fd1 duplicate must retire while the original stdio endpoint stays live.
2. Original decoder input matrix in original-console-output: split non-BMP UTF8,
   cross-write CR/LF/CR, overlong NUL, bad continuation/start-byte reparse,
   invalid 0xff and surrogate encoding. Capture genuine Node physical output
   and callback/counter traces; do not generate an expected Unicode replacement
   string from a generic TextDecoder. Source libuv deliberately differs.
3. Large whole-call output: real Buffer >64KiB through the same native sync hook;
   actual console write must complete before the guest's after-write observation,
   and no guest callback or second Engine's output may interleave within the
   process-global Source output lock. Flushes remain fixed8192 UTF16 units.
4. Real output failure: create a native console with actual read-only access
   or retire the independently owned endpoint at the reviewed boundary. Capture
   Node Buffer versus small String counter/error behavior. Do not fabricate a
   Win32 return code. Require exact real errno/code/syscall and same thrown
   callback identity/no duplicate callback.
5. CRT admission negatives: actual pipe/file/nonexistent descriptors and real
   input versus output consoles. isTTY uses only GetFileType/GetConsoleMode,
   whereas constructor probes require actual input or size/cursor access. Check
   prior thread-local invalid handler restored after every invalid fd.
6. Native duplicate/ownership rollback: fault-inject ONLY owned fixture API
   boundaries, preserving genuine previous handle state. A failed duplicate owns
   nothing; a failed native ticket association retains duplicate ownership for
   one checked CloseHandle. False close retains native slot/error and never
   retries. Stdio duplicates use direct HANDLE tickets without another CRT fd;
   genuine fd>=3 transfers to the reviewed CRT close pool. No borrowed File
   independently closes a CRT-owned HANDLE. Saturate the CRT fd table in the
   owned fixture and compare original Node stdio-TTY construction: no extra
   CRT association/EMFILE admission point is permitted.
7. Actual input completion: private native console input, original Node
   ReadStream, real producer input events and one active demand/read. Capture
   line/raw native data, modifier/function keys, repeat counts, surrogate carry,
   resize records and actual pause/read(0)/resume behavior. Neither zero-result
   nor process exit can manufacture EOF. The raw-record translator remains a
   required incomplete implementation; do not select an approximation.
8. Native read cancellation admission race: pause the worker before entering
   the actual ReadConsole API, request cancel and release it. ERROR_NOT_FOUND
   cannot imply completion. The same worker/ticket/generation/arm must be fenced
   until syscall return and the actual CancelSynchronousIo call retire; it must
   never cancel a later ticket. At250ms retain quarantine/native lease storage,
   without success/EOF/close/absence claims. Native Ref tokens contain no Engine,
   Task, guest roots, allocator or std.Io pointer.
9. Wake detach shutdown: reserve native owner/worker/canceller refs before read,
   detach the Engine sink, then retire the actual pending native read and CRT
   close. No attached-only retain may be requested during shutdown. Require
   actual native memory/GPA/slot retirement; if cancellation fails, retain the
   bounded native uncertainty and block admission rather than reuse the slot.
10. Remote/frontend: Microsoft console handles are duplicable only in the SAME
    process. A remote worker must consume a real authenticated frontend-owned
    capability, including synchronous operation reply/identity/error semantics.
    A hydrated TTY bool/dimension or serialized parent HANDLE never authorizes
    worker console adoption. Native frontend capability export is still missing.

These are control specifications and an original program, not executed native
entries or accepted goldens. Source20/14 and all historical Native29 observations
remain unchanged. Source-only review does not establish functioning selection.
