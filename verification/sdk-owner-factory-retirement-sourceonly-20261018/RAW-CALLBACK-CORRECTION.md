# Raw progress callback boundary correction

Original `232f946c` and its `500DCC62` manifest remain immutable historical
source. Async identified that the actual progress setter is installed with raw
`pi_js_function_magic`, bypassing the Node/class callback's diagnostic and
current-event boundary. The original two-control packet did not close that
direct callback or direct host install path.

The successor wraps that same raw callback with balanced diagnostic suppression
and one real NativeInvocation. It checks entry before effects, records the
actual write/Scope outcome, and pops the frame through the existing Engine exit
before returning to the VM. `installProgress` receives the corresponding direct
host boundary, including success/status and error exits. No field/write order,
callback identity, method length, class declaration, shared helper, C or Engine
implementation changes.

Two additive controls use the actual PackageManager constructor/progress method
and real SettingsManager.inMemory for a successful construction, then install a
throwing progress property setter. They assert exact ordinary reason, one write,
zero poisoned reason.toString calls, no escaping current-event pointer and a
balanced suppression counter. The direct-host variant traps defineProperty on
the actual installer input and makes the same diagnostic assertions. Together
with the old two carrier controls there are FOUR authored declarations, all
UNRUN; actual metadata remains unknown. The install-only target/filter and the
original Source caller/authority, original README and old prepared manifest are
unchanged. `successor-prepared.json` records current bytes separately.
