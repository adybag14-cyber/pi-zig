# OAuth text result ownership correction

The private text helper in the Kimi, Meta, xAI and OpenRouter source ports returned
an Auth Ops.text Scope borrow through an expression boundary that consumes and
retires the Scope. It now duplicates that value to give C435.finishValue its own
result reference before temporary retirement. No shared Ops behavior, provider
algorithm, test declaration, source fixture or public API changes.

The bounded call-site review found only expression-result uses (directly or via
newError/value); no caller consumes this helper as a Scope borrow. The four exact
single-line replacements completed the SDK ownership and byte-delta peer review.
All existing exact-message controls are retained for the next build/runtime run.

| Provider | Corrected production SHA-256 |
| --- | --- |
| Kimi | DE292DBBAFCBA1876BB242BE80D5973D6919736BB2D5E7E44ACAEFCB764A5258 |
| Meta | FE634ACF6F28A04ABEB9AF32A657767E2CE8BB0CCD41DEADB3FDC20E817ABA16 |
| xAI | 560DD8A7D9368D25061FEA9FCA1EA7987D0789F6ADFF228D82BB6093928A6CB1 |
| OpenRouter | C7AFB2B8664A4652291FB45FFFC913A9D8CDE1A9CCBE3E2573F2F60EF66947E8 |

This is source-only review. Earlier compilation or runtime results do not qualify
these changed bytes. Meta's separately reviewed normal iterator-close correction
is already part of its preceding source; it is not repeated in this delta.
