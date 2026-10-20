# V24 template bytecode version correction

The original V24 runtime completed19 tests in this group and failed two assertions in the18-declaration source root. Both expected bytecode format29, although the previously reviewed captured-frame logging metadata unit changed the actual writer/reader discriminator to30.

This correction changes only the two current-writer assertions and the current expected-version number in the reader's literal error message. The test still changes the real writer output to obsolete version28 and requires the exact original rejection message. All18 declarations and every other source byte are preserved.

The complete original source and original runtime stderr are retained unchanged. SDK independently verified the actual BC_VERSION30 definition, reader formatting, and exact three-site inverse. No production algorithm or test oracle was weakened. No build, metadata query, native/Node execution, formatter, or generator was run for this source correction.
