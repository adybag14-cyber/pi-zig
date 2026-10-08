
### Registry dispatch and hosted validation follow-up

The hosted run of 565ea055 identified a macOS stale-registry phase dispatch and cold-build timeouts. The native task manager now refreshes its registry at every owner dispatch boundary. A deterministic regression fails on the previous code and passes with the repair on Windows and Linux in Debug and ReleaseSafe. The original full checkpoint-210 receipt still describes its original source image; the additive repair has its own verification record. The CI workflow uses a dedicated exhaustive allocation target, retains the full OS test matrix, and bounds both cold builds and individual tests. Exact-head hosted validation remains required, and native parity remains uncertified.
