# Checkpoint 184 artifact correction

The supplied `pi-zig-v8-checkpoint-184-FINAL(1).zip` is not a usable source checkpoint.

- archive size: **148 bytes**;
- SHA-256: `605d4b850dd5a4090a88c2f6295db4625f730f6692cd82282e62dd4d062b2297`;
- regular-file entries: **0**;
- directory entries: one empty `pi-zig-v8-checkpoint-184/` directory.

Consequently, no checkpoint-184 implementation claim can be reconstructed or independently verified from that archive. Checkpoint 185 is rebuilt directly from the intact checkpoint 183 archive and reimplements the stream lane in real source. It supersedes the empty checkpoint-184 artifact.

To prevent a repeat, checkpoint 185 contains:

1. the complete Zig rewrite tree;
2. the complete supplied `pi-main` tree under `upstream/pi-main/`;
3. the untouched supplied `pi-main` ZIP under `upstream/source-archive/`;
4. per-file SHA-256 inventories;
5. fresh-extraction build and test records;
6. a separate byte-identical transfer verification.
