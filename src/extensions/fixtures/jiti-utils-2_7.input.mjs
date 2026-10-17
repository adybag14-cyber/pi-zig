// Genuine caller of the real subject. This records, but authors no observations.
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {join} from 'node:path';
export function createPhysicalJitiFixtures(root){
  if(existsSync(root))throw Error('fresh owned physical fixture root required');
  mkdirSync(join(root,'outer/child'),{recursive:true});
  mkdirSync(join(root,'outer/bad/leaf'),{recursive:true});
  writeFileSync(join(root,'outer/package.json'),JSON.stringify({scope:'outer',version:'owned-fixture'}));
  writeFileSync(join(root,'outer/bad/package.json'),'{invalid-json');
}
export async function observeJitiUtils(subject,colors,root){
  const rows=[];
  const error=value=>({name:value?.name,message:value?.message});
  const observe=async(id,run)=>{try{rows.push({id,value:await run()})}catch(reason){rows.push({id,error:error(reason)})}};
  await observe('function-shape',()=>Object.fromEntries(['isDir','isWritable','hash','readNearestPackageJSON','debug'].map(name=>[name,{name:subject[name].name,length:subject[name].length,prototype:Object.hasOwn(subject[name],'prototype')}])));
  await observe('physical-dir-file-missing',()=>[subject.isDir(root),subject.isDir(join(root,'outer/package.json')),subject.isDir(join(root,'absent'))]);
  await observe('nonstring-fileurl-early-guard',()=>[subject.isDir(null),subject.isDir(new URL('file:///')),subject.isDir('file://'+root)]);
  await observe('physical-access',()=>[subject.isWritable(root),subject.isWritable(join(root,'absent/child'))]);
  await observe('physical-nearest-parent',()=>subject.readNearestPackageJSON(join(root,'outer/child/file.js')));
  await observe('invalid-found-json-stops',()=>({undefined:subject.readNearestPackageJSON(join(root,'outer/bad/leaf/file.js'))===undefined,outerStillPresent:JSON.parse(readFileSync(join(root,'outer/package.json'),'utf8')).scope}));
  for(const [index,value] of ['', 'abc', 'é🌍', '\0x', '\ud800', '\udc00'].entries())await observe('hash-string-'+index,()=>subject.hash(value));
  for(const [index,length] of [0,1,8,32,-1,7.9,null].entries())await observe('hash-slice-'+index,()=>subject.hash('abc',length));
  await observe('hash-length-default-undefined',()=>subject.hash('abc',undefined));
  await observe('debug-disabled',()=>({undefined:subject.debug({opts:{debug:false}},{toString(){throw Error('disabled debug coerced input')}})===undefined}));
  await observe('debug-actual-log',()=>{
    const log=console.log,lines=[];
    console.log=function(...args){lines.push(args);return {ignored:true}};
    try{const result=subject.debug({opts:{debug:true}},'[esm]',true,'at '+process.cwd(),{a:1},undefined);return {undefined:result===undefined,lines}}finally{console.log=log}
  });
  for(const name of ['gray','green','blue','yellow','cyan','red'])await observe('color-'+name,()=>({plain:colors[name]('plain'),nested:colors[name]('a\u001b[39mb'),utf16:Array.from(colors[name]('\ud800\0\udc00'),value=>value.charCodeAt(0))}));
  await observe('raw-value-color',()=>{const value={toString(){return 'owned-value'}};return {same:colors.green(value)===value,string:String(colors.green(value))}});
  return rows;
}
