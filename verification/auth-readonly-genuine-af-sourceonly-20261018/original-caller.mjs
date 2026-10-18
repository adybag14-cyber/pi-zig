// Original-only preparation. No capture/output/expected file exists.
// Arguments: exact c268 auth-storage module URL, common observer URL, and an
// already-owned empty physical fixture directory. Actual imports, no facades.
import fs from 'node:fs';
import path from 'node:path';
const [subjectURL,observerURL,fixture]=process.argv.slice(2);
if(process.argv.length!==5||!subjectURL||!observerURL||!fixture)throw Error('three explicit original inputs required');
const root=fs.realpathSync(fixture);
if(!path.isAbsolute(root)||!fs.statSync(root).isDirectory()||fs.readdirSync(root).length)throw Error('owned empty directory required');
const subject=await import(subjectURL),observer=await import(observerURL);
if(typeof subject.ReadOnlyAuthStorage!=='function'||typeof subject.readStoredCredential!=='function')throw Error('actual original exports required');
const observations=await observer.observeReadonly(subject.ReadOnlyAuthStorage,subject.readStoredCredential,root);
console.log(JSON.stringify({subjectURL,observerURL,observations}));
