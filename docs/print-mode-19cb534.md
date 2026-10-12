# Print-mode output-limit diagnostic

The scoped upstream change from `148622bc6f8d0ffd64e33cbc0e1e66754f45d32c`
to `19cb534c3b6e3871458a8fa59e98f0312c50e995` adds four lines to
`packages/coding-agent/src/modes/print-mode.ts`. After printing the final
assistant's text blocks, text print mode writes this line to stderr and
returns status 1 when that message has `stopReason: "length"`:

```text
Response was truncated: the model reached its output token limit.
```

JSON mode continues returning status 0 for a length response. When several
positional prompts run, only the final active message determines this
diagnostic. An earlier length response followed by a successful assistant
response does not produce the diagnostic.

`main.zig` carries the print result through its existing `runMain` wrapper.
This lets the normal session save and deferred extension/runtime teardown
finish before Zig returns a nonzero process status. The native implementation
examines the active, compaction-aware session context and skips auxiliary
session metadata. It preserves the existing output path and other error
handling. It does not modify agent retry, compaction, tool execution, native
backend defaults, or the Node extension bridge.

The fixture `src/coding_agent/fixtures/print-mode-original-19cb.json` is raw
output from the original built `runPrintMode`, `AgentSessionRuntime`,
`AgentSession`, and `ModelRuntime`, using a native-provider fixture. Source
methods/classes were not replaced; standard stdout/stderr sinks were observed.
The fixture also retains the ordinary error and abort reference rows. The
receipt binds the Source file, generated module, capture program and output
hashes, the owned Node process, and zero pre/post drift across 31,064 runtime
files and 1,774 tool files. Sixteen workspace junction identities were checked
before and after the capture. The capture used Node's 64 MiB heap limit.

The provider reports 64 output tokens against a 64-token model limit. An
earlier exploratory capture with zero reported output tokens is retained in
the external evidence directory: original AgentSession treats that length
stop as recoverable, removes the failed response during automatic compaction,
and the print routine has no final assistant to diagnose. Those exploratory
rows were not used as the output-limit golden. This patch does not change
that separate recovery policy.

`zig build test-print-mode-process -j1 --test-timeout 120s` exercises actual
CLI process output, exit status, final-prompt selection, JSON isolation,
verbose output, and session persistence after a length response. The checks
use private temporary home, agent, session and mock paths with networking
disabled and the native extension backend selected explicitly.
