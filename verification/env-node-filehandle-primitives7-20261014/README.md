This is a private primitive checkpoint based on FS20 commit
`4a11aaba4b99373aaaee8da24567d12284bd571c`. It does not install the public
FileHandle class, activate NodeExecutionEnv or qualify the complete Env package.
The lifecycle source file is deliberately unimported and unqualified. Remaining
work includes the complete shared FileHandle/EventEmitter prototype and symbols,
public argument handling, content methods, streams, readline, byte web streams,
exec, watchers and genuine native POSIX replay.

The seven selected tests include six named test bodies and the actual imported
VM storage ownership body. They compare actual Node24.14.0 protected Promise
ordering, species, identity and prototype poisoning; sweep all host allocation
failures for protected promises; replay real libuv descriptor metadata and
vectors; and sweep metadata/vector/view-root/pending-close allocation failures
through a mutex around every allocator vtable route. No failure is converted to
success and no mandatory body is skipped.

The retained local Debug7 receipts refer to the exact 5,333-file working input
manifest before this documentation, workflow and evidence packaging. Compile
PID48656 completed successfully at 2026-10-14T13:14:04Z; runtime PID45792 completed
successfully at 13:14:44Z. Actual execution was 7/7 with no skips. Both complete
source and 19,546-file compiler comparisons had zero drift. Both owned process
identities were checked absent after the terminal receipts. Compiler peak RSS
was 750 MiB; this is a per-compiler measurement, not an aggregate resource limit.
These historical receipts are not an exact-commit ReleaseSafe qualification.

The pinned compiler manifest retains every compiler input hash. Reference
captures retain exact Node executable identity, five real capture receipts and
their 1,902-file original Pi source post checks. The fixture manifest separately
hashes all ten input/output files and the verification-only capture program.
That capture program is materialized byte-for-byte outside the checkout by the
PowerShell helper; it is not a shipped host implementation.

The private workflow qualifies the published exact commit separately. Windows
Debug and ReleaseSafe each compile and execute the seven primitives, then the
existing FS20, listing and typed Env gates. Each native phase freezes and checks
all source and compiler bytes, runs with `-j1`, and admits fresh 8 GiB only on its
explicitly authorized sole hosted runner. Local admission remains 16 GiB.
Compilation retains its separate 1,320-second bound; ordinary execution retains
300 seconds, individual tests 120 seconds and host awaits 10 seconds.

Windows, Linux and macOS also recapture the five original Node24 reference
packets using checksum-pinned same-platform binaries. Windows compares all five
packets to the checked-in Windows reference. POSIX packets are retained as real
platform references only: native POSIX, the full FileHandle graph, Env package
qualification and public activation remain false.
