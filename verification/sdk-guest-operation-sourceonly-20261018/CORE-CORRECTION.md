# Core correction after first finite review

The original96801c90 packet is retained. Its five controls and first implementation remain historical source, not runtime qualification.

Async found two real raw-contract cases: negative status without pending could manufacture a null throw via js.capture; host error materialization could overwrite an actual pending event before leave. The successor checks actual pending/B1 BEFORE materializing a host error and before normalizing a negative status. Missing pending now creates the same explicit InternalError as Engine.checked(value)'s missing-reason contract. Captured-only history is not authority. No tag/flag/generation classifier was added.

A sixth test declaration covers a historical diagnostic plus negative-without-pending, and actual ordinary/marked native pending before typed OutOfMemory. Exact reason and unchanged native allocation generation ensure no replacement OOM was synthesized. The marked fixture is explicitly a privileged actual-pending native fatal, not allocator-stage qualification. All six declarations remain UNRUN; no metadata or expected output exists.