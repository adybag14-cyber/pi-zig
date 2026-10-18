// Inert original-reference input. Root must enforce the full accepted Source
// and Node/controller fence before invoking; this file grants no execution.
const physicalModuleUrl = process.argv[2];
if (typeof physicalModuleUrl !== 'string' || !physicalModuleUrl.startsWith('file:'))
  throw new TypeError('actual physical Source paths module URL required');
const first = await import(physicalModuleUrl);
const second = await import(physicalModuleUrl);
const names = ['canonicalizePath', 'getFileRevision', 'isLocalPath', 'normalizeWindowsShellPath',
  'normalizePath', 'resolvePath', 'getCwdRelativePath', 'formatPathRelativeToCwdOrAbsolute',
  'markPathIgnoredByCloudSync'];
const rows = names.map(name => ({id:name, sameNamespace:first===second,
  sameBinding:first[name]===second[name], name:first[name].name, length:first[name].length,
  functionText:Function.prototype.toString.call(first[name])}));
process.stdout.write(JSON.stringify({moduleUrl:physicalModuleUrl,rows})+'\n');
