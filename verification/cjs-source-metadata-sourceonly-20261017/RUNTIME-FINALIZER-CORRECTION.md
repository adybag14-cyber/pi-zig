# Actual pending ownership through runtime metadata retirement

The ede40961 source checkpoint is preserved. Follow-up review identified a
runtime ownership frontier beyond the compiler's capture-only precondition:
an actual public Error constructor can own a native-finalizer prototype obtained
from newTarget.prototype. Freeing that object after ordinary metadata failure A
can publish fatal B. Blindly throwing saved A after that free would discard B.

The correction uses a metadata-local owner populated only by actual pending
slots. Each release clears its owned slot before draining pending, frees exactly
once, then drains again. Every pending value taken during retirement participates
in the same policy: first ordinary unless an actual later fatal arrives, then
first fatal. Releasing a displaced/nonselected reason can itself publish another
pending value, so draining continues. Presence is separate from the reason value;
no old captured record, rejected value, absence sentinel, guessed error name or
allocation tag is promoted to an event. No new public ABI or Engine state is
introduced, and the legacy metadata-NULL path retains its previous behavior.

All metadata failure owners, including initialized frame records, prepare/error
objects, logical-format temporary values, and the caller's actual Error object
use that owner. The metadata-specific error-production boolean and internal -2
status remain narrow. The existing C3 AF pending-owner pattern is a source
precedent, not an authority transfer or an AF implementation change.

A sixteenth prepared named metadata control uses actual JS_CallConstructor2 with
the real intrinsic Error and a real constructible newTarget. A native getter
transfers its sole-owned native-class prototype. The one-shot native finalizer
sets B uncatchable at the time it actually throws B into the live slot; merely
holding B before that event has no effect. At every measured genuine backing
allocation failure (limit512), any observed prototype-finalizer event must
surface exact B, remain uncatchable and preserve the earlier no-preparation
assertion at the native call boundary. At least one such finalizer event is
required. Successful baseline and all teardown paths disarm the finalizer before
test cleanup; context and B remain alive through the last possible callback.
There are no injected VM fields, synthetic parser/stack results or product fault
hooks. This remains source only: no compiled metadata or runtime result is
claimed, and the broader old legacy array/prepare policy remains outside scope.
