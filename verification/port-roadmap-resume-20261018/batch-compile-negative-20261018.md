# Native batch compile negative and corrections

The fresh batch at 3ba7cb6a compiled PKCE (158/158 steps, actual11 metadata)
and AF (actual31 metadata) before the Node target failed. The original result
and all raw outputs remain at evidence/root-combined-batch-v2-buildquery-20261018-170501.
Whole-batch source/compiler/control seals, environment restoration and all
five native owner closures succeeded; external49332 was independently absent.
No test execution or transferable partial-batch qualification is claimed.

The actual Node production adapter compared an optional error directly with
error literals, which Zig inferred as an invalid error-union comparison.
Explicitly unwrap the optional error before its two existing comparisons.
No ordinary/fatal completion behavior changes are intended.

Four install-only component registrations omitted test filters and therefore
pulled unrelated production module tests into bounded component targets.
Add explicit filters covering every declared Node11, Auth11 (including all six
successor controls), Anthropic5 and Chalk/Ignore3 case. Their actual binary
metadata must still be independently discovered; no count is presumed.
The unrelated AI negatives remain unqualified work for their own/full suites:
two ChatMessage fixture initializers omit required content, and catalog's
test fixture embed escapes the source root of this component test package.
No failing runtime assertion or legitimate selected test is removed.
