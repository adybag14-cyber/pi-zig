// Prepared original Node24 fs.globSync + actual Pi caller observations.
// Fixture creation and explicit native/source seams belong to a future sealed
// harness. This script contains no matcher, traversal or expected result.
const {fs,path,root,input,expandPackageGlob}=GlobAPI;
const rows=[];
for(const test of input.cases){
 const trace=[];
 const cwd=test.cwdSuffix?path.join(root,test.cwdSuffix):root;
 const pattern=test.absolutePattern?path.join(root,test.pattern):test.pattern;
 const options=test.observeOptions?{
  get exclude(){trace.push('exclude');return undefined},
  get cwd(){trace.push('cwd');return cwd},
  get withFileTypes(){trace.push('withFileTypes');return false}
 }:{cwd};
 const matches=fs.globSync(pattern,options);
 const expanded=expandPackageGlob(pattern,cwd);
 rows.push({id:test.id,matches:matches.map(x=>x.replaceAll(root,'<root>')),expanded:expanded.map(x=>x.replaceAll(root,'<root>')),trace});
}
globalThis.node24GlobPackageRows=rows;
globalThis.node24GlobPackageComplete=true;
