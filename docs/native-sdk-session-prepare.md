# Private native run preparation

The native `_prepareRun` body follows original Pi `19cb534` over a live receiver.
It finds the last assistant message and awaits non-continuing compaction, then
awaits `emitBeforeAgentStart`. Explicit selected-tool edits win; otherwise the
current active tools win, including the original reference-alias behavior.
User images are normalized after handlers. The starting user/custom message is
followed by consumed pending next-turn messages and normalized handler messages.
The loadout callback runs before the run options are stored, and a returned
system patch is placed first. Rejections preserve the original queue-consumption
and mutation boundaries. The original last-assistant and active-tool-name
helpers are also implemented in Zig.

This component is installed only in owned tests. Production SDK installation
does not activate it. Compaction, the extension runner, image normalization and
the structured prompt/loadout renderer remain required receiver dependencies;
missing methods are not replaced with successful callbacks.

The genuine Source capture invokes `AgentSession.prototype._prepareRun.call`
with test-only receiver callbacks and inherited original simple helpers. All 44
captured rows cover message identity, async/error order, tool precedence, image
hints, pending queues, custom content and system patches. Timestamp values are
normalized for comparison; original clock calls still run. These fixtures do
not qualify the image resize backend or structured system-prompt rendering.

A retained negative shows a real full-class gap: deleting an own normalizer
callback reveals Source's inherited `_normalizePromptImages`, which succeeds
for absent images. The private native prototype lacks that inherited method
and rejects. The final unavailable-dependency cases explicitly shadow methods
with `undefined`, qualifying the private call boundary only. This correction
does not repair or conceal the full-class gap. `_preparePromptAndToolLoadout`
also remains an unported receiver dependency.

The focused native target executed 11 tests: the 44-row Source replay, collection
at compaction/handler/image await boundaries, all 28 measured Zig allocator
failure indices, and eight imported controls. The allocation test retains the
standard failing allocator and complete exhaustive checker. Its extra unlimited
measurement is not failure coverage; QuickJS's C allocator is not fault-injected.
The previous lifecycle target separately passed nine tests on this patch's base.
The unchanged 120-second test, 10-second host and 300-second outer guards apply.
