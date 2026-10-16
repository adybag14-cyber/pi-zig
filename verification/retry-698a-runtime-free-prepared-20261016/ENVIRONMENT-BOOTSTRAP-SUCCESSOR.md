# Exact owned-child startup normalization

The second Source160 attempt root-source160-5cc-20261016-200028 remains an immutable
pre-Git/Node negative. It passed the launcher claim and stopped on strict environment
equality. No Source160 observation or expected output was produced.

Root authorized one bounded cleared-environment PowerShell diagnostic. PID62300
exited1 with terminal kernel proof, bounded pipes and independent absence0. It
recorded only safe variable names, expected/actual hashes and path classifications.
All19 names and16 values matched. Exactly PATH, PATHEXT and PSModulePath differed.
The diagnostic deliberately refused at PATH before changing anything, so its after
snapshot is unchanged. There was no second diagnostic, Node, Git or capture child.

Offline hash matching established each exact startup form, without reading or
logging a parent environment value:

| Field | Observed normalized-form SHA256 |
| --- | --- |
| PATH |CAB991D3F039CF7E5375242F409AFA0011F4D9F59598F6752B53030940CB1EB6 |
| PATHEXT |95B1B7026CEB29E67AF26926AB564DB1449147D32CF597A794AFC87A78C8AB81 |
| PSModulePath |0571E25FA3B08FEFB7B6EC2FFA5DF970C76F7F2CD1F4AE9F53A48905123B233E |

The observed forms are the PowerShell home prepended to the original PATH, .CPL
appended to .EXE, and owned-profile Documents/PowerShell/Modules plus the standard
program-files PowerShell module root prepended to the original two system module
locations. These additions are discarded, not adopted as the execution policy.

Only four intended child entry scripts invoke the bootstrap. Their first statements
dot-source the common definitions by literal path concatenation and call the pure
bootstrap before any cmdlet. The launcher and external observer never normalize
the invoking parent environment. The bootstrap requires exact -File intent,
NoProfile/NonInteractive, an allowed script in the sealed control directory,
contained config/run/journal and no reparse escape. It verifies all19 names and the
other16 exact values first, then accepts each of the three fields only if already
exact or equal to its one observed startup form. Any arbitrary addition is rejected.
Only then does it restore the existing three reviewed constants and recheck19.

Bootstrap uses only language primitives, pure .NET path/env/JSON/hash/file APIs and
three local pure helpers. Get-S160Environment now uses IO.Path.Combine, avoiding
Join-Path autoload. Each child writes an exclusive hashes-only bootstrap receipt
in its existing owned launcher journal, retained by final artifact sealing.

Static checks cover known/exact forms, arbitrary additions, all four front-end AST
orders, absence of cmdlet calls in bootstrap and rejection of a parent invocation
before environment access. Parser checks pass. The corrected reset path has not
been executed; Root's fresh reviewed capture grant is still required. Claim,
ownership, grant lifetime, Source1970/Node1774, original96BE, caller160 and old273
protections remain. Diagnostic receipts remain under contained evidence and are
environment measurements only, not Source/native qualification.
