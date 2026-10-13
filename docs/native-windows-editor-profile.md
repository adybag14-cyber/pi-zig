# Physical custom editor startup qualification

Windows Debug shared integration job115431224398 failed before its fatal
getter assertion: the physical screen already contained the complete fullscreen
history, startup notice, editor box and footer, but no default `>` glyph.
A custom editor is allowed to render without that default glyph.

Both autocomplete fixtures now wait for the actual rendered startup notice and
header, then send their original `/auto-ready` command. The unchanged command
handler checks that the autocomplete wrapper was installed and publishes
`AUTO_FIXTURE_READY:OWNER_INSTALLED`; the observer still requires that response
in a newer frame. Input readiness and owner installation are therefore checked
through the physical console, rather than inferred from the default editor's
glyph. The subsequent autocomplete, focus, fatal getter, original diagnostic,
raw-console restoration and exact owned exit assertions are unchanged.

The separate Windows Debug/ReleaseSafe workflow builds/stages the real CLI,
compiles the same test artifacts, and runs all four physical editor tests and
twenty fatal controls with the original per-test120s and child startup90s,
render5s and fatal-exit5s guards. Candidate hosted results are pending.
