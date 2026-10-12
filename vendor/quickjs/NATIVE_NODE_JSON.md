# Native Node-host JSON diagnostics

The local `JS_PiJSONStringifyNode` entry point uses the normal QuickJS
serialization traversal with Node-host circular-reference and BigInt diagnostics.
It preserves getter and toJSON invocation order. The circular path is assembled
from that traversal without a second inspection of guest objects. Constructor
names use borrowed internal string values, preserving Unicode and avoiding a
temporary UTF-8 allocation. This helper does not invoke constructor/name getters.

The extension host installs this C entry point as its writable, configurable
JSON.stringify method. Controlled CodeMode host serialization uses the current
host JSON.stringify method and its JSON receiver, so user replacements remain
observable. Inner CodeMode VMs retain the original QuickJS JSON implementation.

Qualification includes twelve original Node circular observations, five further
Unicode/key/BigInt observations, and two actual upstream worker observations of
replaced JSON.stringify. The maintained native-json-pool gate preserves the real
small-block pool and passed every failure index in universes 24,29,44 with no
retained native bytes. These observations qualify the selected serialization
paths; they do not establish universal Node/V8 behavior or complete Pi parity.
