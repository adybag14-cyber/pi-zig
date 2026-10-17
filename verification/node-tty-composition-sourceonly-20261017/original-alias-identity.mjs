// Original public Node24 callers; prepared only, no captured output/goldens.
import * as tty from 'node:tty';
import * as ttyBare from 'tty';
import * as util from 'node:util';
import * as utilBare from 'util';
import * as readline from 'node:readline';
import * as readlineBare from 'readline';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
export const namespaces = tty === ttyBare && util === utilBare && readline === readlineBare;
export const defaults = tty.default === ttyBare.default && util.default === utilBare.default && readline.default === readlineBare.default;
export const requires = require('tty') === tty.default && require('node:tty') === tty.default && require('util') === util.default && require('node:util') === util.default && require('readline') === readline.default && require('node:readline') === readline.default;
export const constructors = tty.WriteStream === ttyBare.WriteStream && tty.ReadStream === ttyBare.ReadStream;
