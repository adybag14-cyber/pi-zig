# Exact non-subject filesystem closure

The watcher attempt root-source160-35cf-watch-20261016-213552 is preserved.
Root approved its Node fence. Node80964 then exited1 at capture-retry-698a.mjs:8
because existsSync probed verification/.pi-zig-workspace.json without an exact
read grant. Caller160 cases never ran. Missing closure was a consequence of that
uncaught permission error. External closure retained metadata_errors[], absence0
and artifact drift0, including Root's watcher provenance.

The unchanged driver walks five marker paths from its actual directory to the
actual container. The successor grants those exact file paths, retaining the
existing actual-container metadata grant and adding no directory/container/runtime
grant. The four intermediate paths must remain absent. Config and the controller
bind the exact ordered probe/absence list; every full seal checks intermediate
absence at its end and records the result. A file, directory or reparse marker is
unexpected; access errors cannot count as absence. The actual container marker
remains a separately hashed immutable control. Original caller/driver/CaseIDs are
unchanged. No fake marker, redirected discovery or old Source fallback is added.

Static audit of every explicit driver/guard filesystem operation:

| Operation | Actual path set | Read/write authority |
| --- | --- | --- |
| Guard readFileSync(configPath) |owned run/capture-config.json |Existing owned-run read |
| Preload URL and import.meta realpath |Exact sealed guard file |Existing control-folder read and physical module identity |
| Guard realpath(config.run) |Owned run directory |Existing owned-run read |
| Guard allowed-file map, observe and SHA |Guard, driver, caller, actual retry.ts |Existing two control folders +Source snapshot; exact4 module path/hash checks |
| Driver ancestor existsSync |Five exact .pi-zig-workspace.json paths |Exact file grants;4 intermediate absence obligations |
| Driver layout readFileSync |Actual container marker only |Existing exact metadata-file grant/hash |
| Driver realpath(source) |Exact Source698 snapshot |Existing Source snapshot read |
| Driver existsSync(output) |Fresh owned raw-output path |Existing owned-run read/absence |
| Driver provenance readFileSync |Caller-folder provenance.json |Existing caller-folder read; candidate/control seals |
| Driver source/caller SHA reads |Actual retry.ts and original caller module |Existing Source/caller read; original hashes |
| Guard existsSync/readFileSync release |Owned run start-fence-release.json |Existing owned-run read |
| Ready/closure/raw JSON writes |Owned run only |Existing owned-run write |

ESM .mjs entry/caller loading already succeeded in the actual watcher attempt.
The awaited .ts subject's nearest package.json and source bytes are within the
fully granted/sealed Source snapshot. The only import in retry.ts is erased
`import type`; no types.ts/package/runtime resolution is admitted. Builtins require
no npm tree. The guard resolves the container lexically and makes no container
directory realpath/stat/read request. No other explicit filesystem read is present
in the guard/driver, and the original caller module has no filesystem operations
or imports. The module observer/network/runtime controls remain unchanged.

The earlier RAM-refusal negative root-source160-35cf-20261016-212108 is preserved
with its sole recovery-current-manifest drift. Post and recovery-post had both
written that one fallback after missing-before proof. New fallback snapshots use
exclusive phase-specific post-current-manifest.json and
recovery-post-current-manifest.json. They remain negative current inventories,
never substitute before proof, and cannot overwrite an earlier artifact snapshot.

No Node, diagnostic, generator or capture job was used to check this successor.
Pure path/argv/absence/immutable-file checks and static read analysis do not yet
qualify the corrected filesystem permission path; Root's fresh grant is required.
