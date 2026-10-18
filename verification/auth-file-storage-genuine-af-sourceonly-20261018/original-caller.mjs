// ORIGINAL-ONLY preparation: no result/expected capture exists.
// argv: actual c268 auth-storage module URL, THIS packet's shared observer URL,
// and an already-owned empty fixture directory. Real upstream imports only.
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const [subjectURL,observerURL,fixture]=process.argv.slice(2);
if(!subjectURL||!observerURL||!fixture||process.argv.length!==5)throw Error('three explicit original inputs required');
const root=fs.realpathSync(fixture);
if(!path.isAbsolute(root)||!fs.statSync(root).isDirectory()||fs.readdirSync(root).length)throw Error('owned empty directory required');
const subject=await import(subjectURL);
const observer=await import(observerURL);
if(typeof subject.FileAuthStorageBackend!=='function')throw Error('actual original FileAuthStorageBackend export required');
const observations=await observer.observeFileBackend(subject.FileAuthStorageBackend,root);
console.log(JSON.stringify({subjectURL,observerURL,fixtureURL:pathToFileURL(root).href,observations}));
