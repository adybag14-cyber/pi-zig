This isolated successor preserves published Source checkpoint
`d21acb167144c55366d9b2cb7e28db7c9b821a60` and adds the focused compile/install
target `build-native-file-revision` plus runtime target
`test-native-file-revision`. Native stat now prepares Windows namespaced paths before opening the kernel object, preserving the genuine trailing-space Source fixture. Ordinary GetFullPath/Get-Item normalization cannot guard this object; the owner uses exact absolute extended paths and FileInfo/OpenRead.

The pair owner requires Root's exact clean candidate seal, NATIVE4, fresh
16 GiB admission, at most four coordinated roots, `-j1`, outer compile 1320s,
outer runtime 300s, per-test 120s through the matching Zig build runtime target,
and ten-second owned-process settling. It freezes the whole candidate, compiler
19,546, Source 1,970, dependencies 31,064, Node/tools 1,774, controls, all six
retained physical Source paths and 84 absences, with complete posthash and path
inventory checks before a phase can qualify, including dependency/Node inventory comparison. The isolated process owner retains the four-root global semaphore and records slot 4 without changing other lane owners.

Compile qualification records installed and actual cached executable/PDB hashes
and queries genuine Zig0.16 test metadata without running tests. Exactly the
six authored names and any known imported storage control must be present.
Runtime uses that same build target and exact artifact manifest, checks all
actual selected tests passed and rejects skips. Both original Source fixture
roots and all genuine Source30/negative proof remain intact.

The symlink test now validates the captured Source EPERM host-denial outcome
instead of skipping on this host; where creation works it still compares a real
symlink with its target. No successful symlink claim follows from the denial.
All six original physical Source paths are mandatory on this host. This is
preparation only until the pair has terminal pass and full post-zero evidence.
