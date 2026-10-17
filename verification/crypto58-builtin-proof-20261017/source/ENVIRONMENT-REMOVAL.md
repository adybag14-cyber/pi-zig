# Dedicated runner typed-null environment removal — source-only

Root's diagnostic root-crypto58-env-20261016-235238 showed inherited environment
NAMES still present after the former reset. Root then isolated an owned-name
probe on PowerShell7.6.6/.NET10.0.12: passing $null to the string parameter left
an empty variable (null_name_present=true), while [NullString]::Value removed
it (typed_null_removes=true). Only owned marker values were read in that Root
probe; this source successor does not rerun it or inspect inherited values.

The runner's dedicated-process-only reset now passes [NullString]::Value to
Environment.SetEnvironmentVariable. Its existing exact -File/live self guard
still runs before reset. It continues to alter only its own Process environment;
no parent, user or machine environment changes, allowlist additions or guesses.

The first work after rebuilding the safe environment records a names-only array
to post-reset-environment-names.json and result data, then requires exact equality
with the unchanged safe name set (Windows case-insensitive spelling, normalized
to uppercase). The same exact-set check uses the existing durable names-only
pre-Node snapshot immediately before unchanged CI607. Both guards reject extra
or missing names. A guard/write failure uses the existing catch/final-seal-attempt
path and never reaches Node; it is negative, not capture acceptance. CI607 still
adds only its three empty Node control variables to its independently owned child.

DriverF722, original58 input/ordered IDs, subject, parser, Node1838/1774 authorities,
permissions, fence and CI607 remain unchanged. The233253 and235238 negatives are
preserved with exact raw/proof hashes in environment-removal-sourceonly.json.
No source capture, Node, compiler or native job and no new environment probe ran;
no grant or expected was created. Runtime behavior of this source successor still
requires Body source review and a separately controlled Root execution grant.
