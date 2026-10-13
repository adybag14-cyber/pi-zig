# Latest native components in shared integration

The shared branch now contains the complete cache-warming class and its pricing,
provider environment, refresh and formatting helpers, the Chord diff/piece/full
tracker implementation, and Pi 1.2 typed Env bounded file listing.

Component provenance before integration:

- Cache warming: aa56715d0a34e2b8417f6889a58b4332f5b28175,
  https://github.com/adybag14-cyber/pi-zig/actions/runs/38417984719,
  all six Windows/Linux/macOS Debug/ReleaseSafe jobs passed.
- Chord delta: 304c41542f642b5da7b24884a8ab7c207940301d,
  https://github.com/adybag14-cyber/pi-zig/actions/runs/38419821309,
  all six platform/mode jobs and their coverage collector passed.
  This includes the Linux Debug partial-array-publication regression repair.
- Env listFiles: 16a35fee538e6c14904e3e7493bf39ea05cfd3e1,
  https://github.com/adybag14-cyber/pi-zig/actions/runs/38421032884,
  Windows Debug and ReleaseSafe passed with the original 89-case ignore corpus.

These historical component results do not certify the integrated tree. The main
native Agent workflow invokes each qualification workflow from the same commit
and its final collector requires every nested job to pass, without skipped gates.
The existing full Agent, CodeMode, MCP, TUI, SDK and allocation partition checks
remain required. Compilation and runtime deadlines retain their original scopes.

The engine retains both cache/provider and Chord singleton roots and frees each
while its QuickJS context is valid. Generated inventories describe this combined
tree rather than taking one candidate branch's manifests as authority.

Public session-factory, full Chord Host and Env guest composition remain separate
unfinished work. These components do not activate the native public factory,
remove the compatibility bridge, or certify full Pi parity.
