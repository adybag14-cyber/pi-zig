import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const input = readFileSync('C:/Users/adyba/pi-zig-native-url-errors-20261015/src/extensions/fixtures/url-errors-node24.input.txt', 'utf8');
(new Function(input))();
const builtins = process.binding('natives');
const builtinSources = Object.fromEntries(['internal/url','internal/errors'].map(name => [name, {sha256:createHash('sha256').update(builtins[name]).digest('hex'),source:builtins[name]}]));
writeFileSync(process.argv[2],JSON.stringify({ runtime:process.version, count:urlErrorRows.length, rows:urlErrorRows, builtinSources },null,2)+'\n');
console.log(JSON.stringify({cases:urlErrorRows.length,runtime:process.version,builtinURL:builtinSources['internal/url'].sha256}));
