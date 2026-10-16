Upstream 0fb source proof and native preparation
===============================================

Target authority is official `earendil-works/pi` commit
`0fbdbd3f8ab1876ac260c0f08226a400759323b8`, observed directly on main and HEAD.
Relative to `4954d760504c11df9b2cbdc040346107b6a8153d`, four commits change
12 files. Package manifests, lockfiles, provider implementations, SDK,
TypeBox, stream modules, UI, model generator, flake, and tracked model catalog
are identical. Latest release remains v1.3.0, published 2026-10-15T19:17:33Z.

The native implementation adds node-fetch retry wording to both the VM
classifier and the ordinary Zig classifier. It resolves durable compaction
overrides by exact `provider/modelId`, retaining nullish fallback, object-rest
getter order and lazy key access. Threshold preparation captures settings for
the request; overflow uses that request's model and a fresh policy captured
at classification; summary selection captures its policy before awaiting
context/hooks and keeps it for sizing. Existing strict `terminate === true`
semantics already accept false as a no-op.

The corrected genuine-source run passed 27 controls: 17 policy/retry, six
public Harness cases, and four direct compaction selections. The public cases
prove exact-model threshold selection, overflow enablement, summary sizing,
and false/true tool termination. Direct selections prove one settings read
and unchanged summary policy/stream after context and hook activity. Expected
rows in `src/extensions/fixtures/upstream-0fb-source.json` are the unedited
captured source output; native tests bind each input by SHA-256.

Full before/after verification covered 1,970 source files, 31,064 immutable
runtime/dependency files, 1,774 Node files, seven controls, five then-current
candidate files, and 84 actual optional/historical absences. The source tree
contains 1,927 tracked files and 43 carried generated data files. Their exact
official provenance, hashes, and deterministic generation timestamp are
recorded in readiness.json and generated43-provenance-files.json. No generator
was rerun because its inputs and flake are unchanged. The observer maps every
workspace export to this latest source and rejects old source implementations
or unmanifested external modules. Before reading dependencies it also requires
the carried package manifests and lockfile to match byte-for-byte.

The first attempt failed before source execution because Node --import received
a Windows path instead of a file URL. Its failed owner record, stderr, and
before/after seals remain. The corrected run exited zero in 27.7 seconds with
approximately 116 MB peak working set. Node used a 256 MiB old-space limit;
the owner supervised a 2 GiB process limit and a 300-second deadline.

Native compilation and runtime qualification are deferred pending Root's serial
native slot. Canonical Zig 0.16.0 formatting and git diff whitespace checks
pass. The prepared target is `test-native-upstream-0fb` (compile-only target
`build-native-upstream-0fb`). No new C source, release, main merge, publication,
or public activation is included. Source control success does not certify the
whole Pi implementation or a versioned release.

Additional overflow source proof
-------------------------------

Five additional source controls passed in a separate bounded run, bringing the
total to 32 distinct source cases. The original 27 expected rows retain their
SHA-256 unchanged. The additional output is
`src/extensions/fixtures/upstream-0fb-overflow-source.json`.

These controls pin request model A, switch the current agent to model B in an
afterResponse hook, and give A and B opposing policies. Source selects A's
fresh classification policy: A-enabled/B-disabled waits for compaction, while
the inverse fails. Another case changes settings and getter-backed overrides
inside an awaited context read; the previously resolved policy remains fixed.
A no-cut case reads settings/policy once. Two errors on the same runtime and
task read new settings separately and move from retry to overflow compaction.

Native error-policy pins belong to the fresh private state allocated by
`classify()` for each response; they are never copied into a retry checkpoint.
The no-cut continuation now also reuses the already computed overflow boolean.
Preparation captures thinkingLevel when upstream destructures the agent,
before asynchronous context/rendering work. These additions and their native
test remain uncompiled; Root requested a temporary hold on all Zig commands
while its serial Body pair runs. The original canonical formatting check
applies to checkpoint a25c8a2c, not an unverified claim about later changes.
