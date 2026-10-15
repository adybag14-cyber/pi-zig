# Upstream refresh authority, 2026-10-15

The fetched `earendil-works/pi` main head is `5ab7fe74c400097b386662205cd93900695b8a71`, committed at `2026-10-15T14:49:50Z`. The latest GitHub release observed in this refresh is `v1.2.0`, published at `2026-10-12T23:03:53Z`. The source packages still declare `1.2.0`; unpublished main behavior must not be described as an already published `1.2.1` release.

Authority is the detached checkout `C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015`. Its Git source archive is `pi-upstream-5ab7fe7-immutable-20261015.tar`, SHA-256 `bb1b83d360c004472059628ea7594fee16232eb3931a58a1f07e2aba67c3df72`, in the external update evidence directory. The previous source checkout remains at `b06c1f2cf1dea6af8748ddeee18c23587d2cb7c6`.

## Behavioral delta from b06c1f2

There are eleven commits touching 42 files. Their net runtime contracts are:

- Anthropic and Bedrock Claude retain error tool-result images. The text-only error result replaces each image run with `(image attached after the tool results)`. After all tool results of that turn, the same user message receives `Images from the error result of tool call <id> (<name>):` and the images. Non-error results and non-vision image downgrades keep their existing paths.
- Anthropic generated thinking metadata permits `off` for normalized `claude-opus-5`, `claude-haiku-5-5`, and `claude-haiku-5.5` even when mid-conversation effort is supported. Normalization strips the optional OpenRouter prefix and dated snapshot suffix. Opus 5.5, Sonnet 5.5, Fable 5.1, and Mythos 5.1 continue to reject disabled thinking.
- Retry recognition includes `The service is temporarily unavailable` through `service.?(?:is.?)?(?:temporarily.?)?unavailable`.
- The final Kimi Coding generator uses Chat Completions at `https://api.kimi.com/coding/v1`, matching the b06c1f2 final contents. The intermediate revert does not survive in the net delta. Catalog publication raises `MINIMUM_PI_VERSION` from `0.80.7` to `1.2.1` because older clients ignore the model API for this provider.
- `@earendil-works/chord/output` becomes the public home of bounded output and progress helpers. It exports `OutputSkip` and `utf8ByteLength`; durable output/truncation imports move there. UTF-8 byte length counts lone surrogates as replacement characters, three bytes each. Existing buffer retention behavior is retained.
- Remote Chord references reject supplied contexts not made by Chord and contexts from another host with `invalid/foreign_ctx`. The check now uses the called reference's binding host, not the supplied context's own host. Expired and aborted checks still apply.
- SQLite durable storage accepts an optional table/index prefix. An explicitly provided prefix must match `[A-Za-z_][A-Za-z0-9_]*` and must not start with `sqlite_`, case-insensitively. Omission preserves the historical unprefixed schema; explicit empty string is invalid. Every migration and runtime query uses the selected identifiers, including schema version and metadata tables. Changing prefixes does not migrate old data. Node and Cloudflare entry points expose the option.
- The Nix wrapper appends Node to PATH. Test-only model references use available Claude Sonnet 4.5 names.

The OpenAI Completions codec, partial JSON parser, dependency pins, and coding-agent read/write/edit renderers are unchanged between these two commits.

## Qualification boundary

The previous native catalog identifies Pi 1.1.0, source `19cb534c3b6e3871458a8fa59e98f0312c50e995`, and typed catalog SHA-256 `439c53478c84ed27a58f8b54e1c3bd45810e5a969515b4e3666a3898d51ee22f`. It remains historical evidence. This refresh must obtain matching official generator output before changing the native catalog provenance. Neither a source refresh nor catalog component success qualifies the full native Pi application or authorizes removal of the compatibility host.
