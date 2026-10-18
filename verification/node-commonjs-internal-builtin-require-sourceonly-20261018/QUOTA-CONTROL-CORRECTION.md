# Quota control restoration

Test-only additive correction after b2497353cc0f987a751f83327e9d811b026c26b9:
the one-byte VM quota control restores `engine.options.memory_limit`, the exact
Engine configuration, rather than an unlimited limit. The actual production
owner, assertions, four source declarations, build target, authorities and
protected dependencies are unchanged. The original prepared.json remains a
historical exact b249 manifest; prepared-v2.json binds this correction.
No test, parser, compiler, metadata or native execution occurred.
