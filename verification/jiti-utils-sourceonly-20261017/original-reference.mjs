// Prepared original Source capture only. Actual package graph prerequisites
// and strict owned runner/permissions/pre-post/absence are separately required.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {isAbsolute} from 'node:path';
import {createInterface} from 'node:readline';
import tty from 'node:tty';
import nodeCrypto from 'node:crypto';
import {createPhysicalJitiFixtures,observeJitiUtils} from '../../src/extensions/fixtures/jiti-utils-2_7.input.mjs';
const [entry,originalUtils,colorsEntry,fixtureRoot,profile='actual-default']=process.argv.slice(2);
if(process.version!=='v24.14.0'||[entry,originalUtils,colorsEntry,fixtureRoot].some(value=>!value||!isAbsolute(value)))throw Error('actual pinned Node/package/Source/yocto paths and fresh owned root required');
const fence=createInterface({input:process.stdin,crlfDelay:Infinity});const line=await new Promise(resolve=>fence.once('line',resolve));fence.close();
if(line!=='ADMIT-JITI-UTILS-ACTUAL-SOURCE')throw Error('owned actual Source admission required');
const bytes=readFileSync(originalUtils);if(createHash('sha256').update(bytes).digest('hex')!=='c0b823df0e6f848236eac75bc6081cba55a9c2ec076d5af240750a081989c954')throw Error('original jiti2.7 utils authority differs');
if(!['actual-default','guest-colors-enabled','guest-fips-true','guest-fips-throw'].includes(profile))throw Error('explicit bounded reference profile required');
// Separate fresh processes only. These are guest mutations of real imported
// namespaces for causal branches, not terminal/FIPS capability observations.
const colorDescriptor=Object.getOwnPropertyDescriptor(tty.WriteStream.prototype,'hasColors');
const fipsDescriptor=Object.getOwnPropertyDescriptor(nodeCrypto,'getFips');
let fipsCalls=0;
if(profile==='guest-colors-enabled')Object.defineProperty(tty.WriteStream.prototype,'hasColors',{configurable:true,writable:true,value(){return true}});
if(profile==='guest-fips-true')Object.defineProperty(nodeCrypto,'getFips',{configurable:true,writable:true,value(){fipsCalls++;return 1}});
if(profile==='guest-fips-throw')Object.defineProperty(nodeCrypto,'getFips',{configurable:true,writable:true,value(){fipsCalls++;throw new Error('controlled actual getFips mutation')}});
try{
const {createJiti}=await import(pathToFileURL(entry).href);
const jiti=createJiti(originalUtils,{fsCache:false,moduleCache:false,tryNative:false,interopDefault:false});
const subject=await jiti.import(originalUtils);
const colors=await import(pathToFileURL(colorsEntry).href);
createPhysicalJitiFixtures(fixtureRoot);
const rows=await observeJitiUtils(subject,colors,fixtureRoot);
process.stdout.write(JSON.stringify({source:'jiti2.7/fd3bb289b75ed207edfb686d671ed50144f7e90f',node:process.version,utilsSha256:createHash('sha256').update(bytes).digest('hex'),profile,fipsCalls,rows})+'\n');
}finally{Object.defineProperty(tty.WriteStream.prototype,'hasColors',colorDescriptor);Object.defineProperty(nodeCrypto,'getFips',fipsDescriptor)}
