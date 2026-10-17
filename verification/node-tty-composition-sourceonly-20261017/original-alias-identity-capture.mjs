// Reference controller only: observe the unchanged ORIGINAL public caller.
// This is never loaded by the application or used as a production provider.
import * as actual from './original-alias-identity.mjs';
process.stdout.write(JSON.stringify({
  packet: 'actual-node-builtin-alias-identities',
  namespaces: actual.namespaces,
  defaults: actual.defaults,
  requires: actual.requires,
  constructors: actual.constructors,
}) + '\n');
