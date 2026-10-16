# Canonical preload file URL

The root-source160-c072-20261016-210504 negative is preserved. Node45940 started
and exited1 before fence-ready because --import received an absolute Windows C:
path, interpreted as unsupported ESM protocol c:. The original160 caller never
ran and no expected exists. Full before/post/recovery source, original1774,
complete1838, candidate, controls and accepted273 seals passed. External metadata,
absence and artifact checks also passed. These receipts remain unchanged.

Only the preload module specifier is now a canonical file URL. The producer resolves
the drive path, escapes each path segment with Uri.EscapeDataString, constructs an
absolute file Uri and requires exact LocalPath round trip with no host/query/fragment.
This preserves literal percent-encoded-looking filenames as data: %20 becomes
%2520, while spaces, # and Unicode are correctly escaped. A naive Uri(path) alone
would interpret literal%20 as a space, so the pure checks include that negative.

The CLI entrypoint, source/output arguments and filesystem permission paths remain
plain Windows paths. Intended argv and execArgv checks use the exact new --import
argument. The preload verifies its file-URL scheme and decoded physical identity,
requires the actual --import specifier to match sealed config, and records the URL
in ready/closure receipts; the controller checks both. The existing four-module
observer still compares real physical paths and file hashes, without broadening
imports or permissions. Original96BE, Source160 caller/IDs, all prior negatives,
authority inventories, runtime-free scope and process/resource framework remain.
Pure URI/argv and parser checks only; no Node or capture ran to test this correction.
