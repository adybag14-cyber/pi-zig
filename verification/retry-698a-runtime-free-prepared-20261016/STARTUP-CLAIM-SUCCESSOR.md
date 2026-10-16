# Source-only correction after first Root Source160 attempt

The first attempt `root-source160-ccf-20261016-194000` is preserved in contained
evidence with its launcher journal, logs, terminal and independent absence0.
Supervisor74344 exited before Git or Node. Root's issued/expires calls produced
a300.0003682s duration, exceeding the unchanged strict300s grant limit. This was
a Root grant construction error. Construct future issued/expires from one captured
timestamp; neither the supervisor nor launcher permits an epsilon or stale grant.

The attempt also exposed a concrete startup collision. Cleared PowerShell startup
created run/profile, run/temp and the exact AppData/Local/Microsoft/PowerShell
directory chain, plus StartupProfileData-NonInteractive (87,736 bytes), before
the supervisor's previous blanket existing-run check. The old evidence is not
adopted or changed; future attempts require a fresh run ID.

The launcher now claims the fresh directory before starting PowerShell. New-Item
without Force refuses an existing/raced directory. The claim file is created with
FileMode.CreateNew, exclusive sharing and flushed before close. It binds schema,
scope, run ID/path, candidate, exact grant SHA, fresh nonce, full launcher identity,
creation time and the exact startup-state policy. Claim path and SHA are explicit
supervisor arguments bound by the existing intended-argv checks.

The supervisor retains all grant/tool/freshness checks, verifies the claim hash,
run/candidate/grant/nonce/time and exact live parent identity, and permits only
the claim plus those exact observed startup directories and optional named
PowerShell startup-data file. The file is bounded to1MiB and its actual bytes/SHA
are recorded. No other file, directory or reparse point is accepted. This generated
owned profile cache is mutable runtime state, not Source authority or executable
control code. All later terminal state remains covered by artifact sealing.

An acceptance marker also uses exclusive CreateNew; it is rejected as unexpected
state on replay, and simultaneous attempts cannot both claim acceptance. Claim
and acceptance SHA are pinned in immutable config and checked in full before/post
seals. The launcher still rejects every existing run or journal at entry. The
supervisor accepts only a matching fresh launcher claim, never a generic existing
profile directory. Original96BE, Source160 caller/IDs, accepted273 and old attempt
proofs remain unchanged. No child launch was used to author or check this fix.
