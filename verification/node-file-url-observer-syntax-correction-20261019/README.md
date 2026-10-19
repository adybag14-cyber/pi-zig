# File-URL observer syntax correction

The retained V10 complete-cohort diagnostic reached the actual file-URL test module's compile-only evaluation and reported `SyntaxError: Unexpected identifier 'real'` before any observer could execute.

The cause is the expected tuple in `observeUrlHostClass`, line 212: its `platform` string opened with a double quote and closed with a single quote. This successor changes that one closing character to a matching double quote. Every observer body, assertion text, case and declaration name is otherwise unchanged.

- Original observer: EFB06CEC7B4B50BBEC4E4D45CCC818D46862855EE0757BF1CC33E392D76F12DE, 15,913 bytes.
- Corrected observer: CFE13BF8A42378B702CC9DA977AF297653DA007CDE8A867755CB138284775558, 15,913 bytes.
- Exact retained negative: `C:/Users/adyba/pi-zig/evidence/root-v10-runtime-diagnostic-v3-retry-20261019-165655/groups/native-node-file-url-paths/runtime.stderr.log`.
- Negative stderr SHA-256: 1E8DEEA867A4594C82643E927D4060403618C9973FFAC44F992F30516CAB4AB5.
- Root's finite source peer compared both complete 284-line files and closed the one-character correction.

The existing build target, filter and nineteen named controls are unchanged. No compiler, Node reference capture, metadata or runtime command was executed for this correction. The preserved failing evidence remains a negative; this source change does not qualify the file-URL group.
