The qualified private runtime commit is
`75ea66c91352b0f62965e331ac36adcf3a50ca9f`, on branch
`work/env-node-filehandle-e6220e1-20261014`. Its terminal hosted run is
[38572898382](https://github.com/adybag14-cyber/pi-zig/actions/runs/38572898382).
This proof publication adds evidence after that commit. It does not relabel a
later source tree as the qualified runtime input.

Windows Debug and ReleaseSafe each passed all seven selected private FileHandle
primitives without skips, all twenty selected FS comparisons without skips,
twelve listing tests, and ninety existing typed Env tests with fifteen original
platform skips and zero failures. The primitive gate includes the real
descriptor/vector/pending-close allocator sweep and protected-Promise allocator
sweep. Raw logs, exact compiled inventories, owned process identities, admission
records and pre/post summaries are retained for every phase.

All eight native phases used the same 5,360 source rows and exact commit/tree.
`qualified-source-before.json` retains that common full source manifest.
`complete-input-audit.json` records each original phase manifest's hash and the
row-by-row comparison. The complete 19,546 compiler inputs in every native
artifact were independently compared to the retained pinned compiler manifest
from the preceding primitive checkpoint; no compiler row differed. Native
source and tool post checks reported zero drift. Both compilation-only phases
per mode executed no runtime tests. All phases admitted at least 8 GiB after
their full prehash on explicitly authorized sole hosted runners. These are
admission checks, not claims about aggregate peak memory consumption.

Windows, Linux and macOS each captured all five real Node24.14.0 reference
packets. The retained references include their original 1,902-file source walk,
source and candidate post proofs, pinned Node identity, exact input/temp
materialization identity, and every packet output. Windows matched all five
checked-in packets. Linux and macOS packets are genuine source references only.

The preceding run at `ee2726a5082c9fcabd7d0df33f3d57fc2e9a6b26` failed before
native compilation because the Windows ZIP extraction step tested a native
exit-code variable after a PowerShell cmdlet. Commit `75ea66c` fixed that check
without changing runtime code or reference inputs. This successful run did not
skip the failed Windows prerequisite.

Qualification covers protected Promise behavior and the existing real libuv
descriptor metadata/vectors and scoped FS gates. The lifecycle source module
remains unimported. The complete shared FileHandle/EventEmitter object graph,
method frontend and streams, full Env package, native POSIX Env and public
activation remain unqualified. New content and stream-state implementations are
separate unqualified work.
