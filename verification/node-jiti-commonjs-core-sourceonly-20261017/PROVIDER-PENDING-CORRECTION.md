# Actual pending path-capability correction

The live path.isAbsolute getter and its callee are separate boundaries. A native
getter may return a function with a real VM reason still pending; a native
callee may return true with a real reason pending. Neither success permits
creating or admitting a converted provider. Registration now checks the actual
pending slot immediately after each operation, before the next call/allocation
or private registry insertion, under its existing local suppression/generation
boundary. Owning the successful value in Scope does not clean it up until after
the pending reason has been captured. No data bit or historical capture is used.

Four prepared genuine native success-with-pending controls cover ordinary/fresh
getter and callee cases, zero diagnostic coercion, no downstream callee on getter
failure, exact reason/generation, no cache/parent publication and ready=false.
The combined root now has thirteen source declarations, not an observed compiled
metadata count. No jobs ran. Existing b0efd1a2 manifest and independent source
receipt remain historical for that narrower boundary; this correction is a new
checkpoint requiring independent source review and separately granted runtime.
