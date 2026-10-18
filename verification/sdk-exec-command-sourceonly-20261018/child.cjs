// An actual user command subject, never an implementation host/bridge.
'use strict';
const mode = process.argv[2];
if (mode === 'sleep') {
  setTimeout(() => process.exit(0), 20000);
} else if (mode === 'cwd') {
  process.stdout.write(process.cwd());
} else {
  process.stdout.write('out:A\n'); process.stderr.write('err:A\n');
  setTimeout(() => { process.stdout.write('out:B\n'); process.exit(mode === 'nonzero' ? 7 : 0); }, 15);
}
