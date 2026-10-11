# Original config documentation-path Source oracle

Verification only. `oracle.mjs` dynamically imports the byte-identical production
`config.js` after verifying every original module, reference TypeScript and
licensed dependency. The original config imports its original relative paths,
child-process and text helpers. The child-process helper is imported but never
called; this oracle does not import the native backend or execute a child process.

The controlled input is the same `PI_PACKAGE_DIR=C:/sdk-agent-start-package`
used by Source560. Each OS executes actual `getReadmePath`, `getDocsPath` and
`getExamplesPath`; their output provides precise environment projection for
the three paths inside the two captured default prompt strings. No expected
string or algorithm is synthesized from native output. Original Source560
captures and all nonpath assertions remain unchanged.
