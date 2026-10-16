# Pi-zig workspace

The active integration checkout is `main/`, on
`work/pi-zig-consolidated-20261016`. Open that folder for repository work.

```text
pi-zig/
  main/                  Root integration checkout and shared Git metadata
  worktrees/             Assigned agent branches
    archive/             Historical registered worktrees
    unregistered-archive/ Preserved older standalone snapshots
  upstream/
    pi/                  Official Pi source at the reviewed integration target
    snapshots/           Earlier source references
    archive/             Other retained upstream comparisons and dependencies
    runtime/             Pinned dependency runtime and recovery staging
  evidence/              Original captures, failures, artifacts and move journal
  toolchain/             Pinned Zig 0.16.0
```

The reviewed integration target is Pi `4dd2b149`, newer than the inspected
`v1.3.0` release. Its 273 genuine reference observations are accepted; native
replays and complete application/release qualification remain unfinished.

The original 19cb dependency runtime was deleted outside this work. Recovery is
in progress. Its required new location is
`upstream/runtime/19cb534-20261012`; it is not usable until all 31,064 original
file hashes, workspace links and absence records validate.

The consolidation moved 431 present registered worktrees, including `main/`,
inside this container. Missing historical entries and their nine locks were
preserved. Move journals are in `evidence/workspace-consolidation-20261016/`.
Historical proof files retain their original paths and bytes. The explicit
`path-relocations.json` maps those old locations to the contained layout.

No old directory aliases were left outside the container. Existing verification
launchers must be adapted and resealed before use at their new paths.
