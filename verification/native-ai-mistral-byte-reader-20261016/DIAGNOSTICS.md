# Diagnostic-only producer/consumer and trusted allocation patch

Apply with git apply --unidiff-zero diagnostic-producer-consumer-oom.patch to a new isolated diagnostic
successor of b70a7e63, then obtain Root's separate native admission. No execution
or Zig formatting/AST/compilation has occurred for this patch.

The patch records actual HTTP byte-delivery lengths and awake timestamps;
Mistral VM producer stage/completion, owner job/control counters; and each
Source30 consumer event type after the original snapshot has already been
created. The consumer trace reads only its new plain snapshot's type and adds
no Promise/await, message clone, delay, tick, split or changed assertion. The
existing snapshot itself remains unchanged. Probe/binding installation is
limited to the Source30 loop; facade allocation sweeps retain their old setup.

Source8 allocation failure diagnostics report the actual FailingAllocator index,
induced-failure flag, generation before/after, captured native generation tag,
uncatchable flag, retained diagnostic and original allocation stack before the
existing nativeAllocationError classification. Native flow.rejectError gains
only an observational raw/captured tag print; its semantics remain unchanged.
No global error-boundary change or weakened checkAllAllocationFailures occurs.

Compare diagnostic results against the retained75/9 baseline archives and
report any observational perturbation explicitly. Real output operations may
influence wall-clock arrival races, so trace output alone does not qualify
Source parity. A useful trace must retain all original expected packets and
assertions and identify whether reader delivery, producer demand, consumer
progress, or terminal/error propagation caused the remaining difference.
