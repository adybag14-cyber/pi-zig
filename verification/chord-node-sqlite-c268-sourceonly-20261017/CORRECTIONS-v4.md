# Current-event generation correction v4

This is a separate source successor of the immutable v3 packet. Review found
that a raw native finalizer can produce a genuine private-tagged allocation
failure before any wrapper marks it uncatchable. Bit-only cleanup selection
could discard that new fatal, or replace an earlier raw fatal with a later one.

The leaf now records the real allocation generation before each relevant actual
C call (get/call/constructor/coercion/set/ownKeys/named-parameter get), and passes
that boundary into returned-value normalization before cleanup. Newly observed
current cleanup events use the existing unsigned private-tag freshness rule or
an actual uncatchable bit; a genuine fresh native reason is marked then. This
never classifies the isolated historical diagnostic or rejected Await DATA.
Cleanup retains its selected owned reason outside both slots while disposing
other owners, with first-fatal priority.

The additive native file now has ten test declarations. The new tenth control
uses a real successful native getter plus real native finalizer: ordinary first
error then raw native OOM must select the OOM; raw native OOM first then another
raw native OOM must retain the first exact reason. A third variant crosses the
u64 allocation-generation wrap/zero-skip boundary. Producers use the actual
Engine throwNativeOutOfMemory path without pre-marking the new reasons. A real
armed GPA allocator also proves no root append runs after pending is observed.

All original 25 observations, four original tests and previous packets remain
unchanged. The four additive original-caller rows and nine earlier declarations
are retained. Neither ten declarations nor any reference input has been compiled
or executed. Actual metadata remains unknown; no output or golden was created.
The v3 scope/frontier/dependency limitations continue to apply. No shared C,
Engine, Main, default build, namespace or runtime-authority change is included.
