// Prepared static-authoring regression controls; never TypeBox parity authority.
import {outlineCallPreparations} from './outline-call-setup.mjs';
function assert(value,message){if(!value)throw Error('Static call-setup regression: '+message)}
function owner(){return new Map([['f0',{key:'f0',base:5,count:1,ranges:[{start:0,count:1}]}]])}
function unit(lines,regions){return{kind:'callback',id:0,owner:'f0',source:'static-authoring-fixture',scoped:true,lines,regions,flags:{receiver:false,args:false,env:true}}}
function region(start,calleeEnd,end,resultSlot,callable,args,callReceiver='c.pi_js_undefined()'){return{start,calleeEnd,end,callLine:end,resultSlot,callable,arguments:args,callReceiver,construct:false,sourceStart:start,sourceEnd:end,sourceHash:'static-fixture-not-Source'}}
export function checkCallSetupAuthoring(reportCase=()=>{}){
 const lines=[
  'native_values[0] = try rt.get(s, env, "object");',
  'native_values[1] = try rt.key(s, native_values[0], c.pi_js_undefined());',
  'native_values[2] = try rt.get(s, env, "inner");',
  'native_values[3] = try rt.invoke(s, native_values[2], c.pi_js_undefined(), &.{});',
  'native_values[__TYPEBOX_NATIVE_ARG_f0_0__] = native_values[3];',
  'native_values[4] = try rt.invoke(s, native_values[1], native_values[0], native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f0_1__]);',
 ];
 const nested=unit(lines,[region(2,3,3,'native_values[3]','native_values[2]','&.{}'),region(0,2,5,'native_values[4]','native_values[1]','native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f0_1__]','native_values[0]')]);
 const original=JSON.stringify({lines:nested.lines,regions:nested.regions,flags:nested.flags});
 const frames=owner(),result=outlineCallPreparations([nested],frames,['runBranch']);
 assert(JSON.stringify({lines:nested.lines,regions:nested.regions,flags:nested.flags})===original,'original stream/regions/flags changed');
 assert(result.native.includes('noinline fn call_setup_0'),'missing enforced call boundary');
 const outer=result.native.slice(result.native.indexOf('noinline fn call_setup_0'),result.native.indexOf('noinline fn call_setup_1'));
 const stored=outer.indexOf('native_values[__TYPEBOX_NATIVE_SETUP_f0_0__] = native_values[1]'),argument=outer.indexOf('try call_setup_1(');
 assert(stored>=0&&argument>stored,'callee descriptor missing or moved after first argument nested call');
 assert(outer.includes('native_values[3] = try rt.invoke('),'required nested real call disappeared');
 assert(nested.emittedBody.includes('native_values[4] = try rt.invoke(s, native_values[__TYPEBOX_NATIVE_SETUP_f0_0__], native_values[__TYPEBOX_NATIVE_SETUP_f0_1__]'),'outer real call does not use stored descriptor');
 assert(!result.provenance[0].abiNeeds.receiver,'stored method receiver confused with lexical receiver');
 assert(frames.get('f0').descriptorCount===4,'nested descriptors overlap/missing');
 reportCase('nested callee descriptors preserve original call boundaries and flags');
 const escape=unit(['native_values[0] = optional_9;','native_values[1] = try rt.invoke(s, native_values[0], c.pi_js_undefined(), &.{});'],[region(0,1,1,'native_values[1]','native_values[0]','&.{}')]);
 let rejected=false;try{outlineCallPreparations([escape],owner(),[])}catch(error){rejected=String(error).includes('Unclosed native setup local optional_9')}
 assert(rejected,'accidental enclosing optional local was captured');
 reportCase('free enclosing optional local rejects');
 const sliceEscape=unit(['native_values[0] = try rt.invoke(s, env, c.pi_js_undefined(), native_values[0..optional_9]);','native_values[1] = try rt.invoke(s, native_values[0], c.pi_js_undefined(), &.{});'],[region(0,1,1,'native_values[1]','native_values[0]','&.{}')]);
 rejected=false;try{outlineCallPreparations([sliceEscape],owner(),[])}catch(error){rejected=String(error).includes('Unclosed native setup local optional_9')}
 assert(rejected,'numeric-start slice hid a free slice-end local');
 reportCase('numeric-start slice free endpoint rejects');
 const foreignEnd=unit(['native_values[0] = try rt.invoke(s, env, c.pi_js_undefined(), native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f1_1__]);','native_values[1] = try rt.invoke(s, native_values[0], c.pi_js_undefined(), &.{});'],[region(0,1,1,'native_values[1]','native_values[0]','&.{}')]);
 const foreignFrames=owner();foreignFrames.set('f1',{key:'f1',base:9,count:1,ranges:[{start:0,count:1}]});
 rejected=false;try{outlineCallPreparations([foreignEnd],foreignFrames,[])}catch(error){rejected=String(error).includes('foreign/out-of-range owner frame')}
 assert(rejected,'marker-start slice hid a foreign owner slice-end marker');
 reportCase('marker-start slice foreign owner endpoint rejects');
 for(const [name,cleanup] of [['allocator free ownership rejects','engine.gpa.free(native_values);'],['JS_FreeValueRT ownership rejects','c.JS_FreeValueRT(engine.rt, native_values[0]);'],['defer ownership rejects','defer c.pi_js_undefined();'],['errdefer ownership rejects','errdefer c.pi_js_undefined();']]){
  const cleanupEscape=unit([cleanup,'native_values[0] = c.pi_js_undefined();','native_values[1] = try rt.invoke(s, native_values[0], c.pi_js_undefined(), &.{});'],[region(0,2,2,'native_values[1]','native_values[0]','&.{}')]);
  rejected=false;try{outlineCallPreparations([cleanupEscape],owner(),[])}catch(error){rejected=String(error).includes('cannot acquire Scope/JSValue cleanup ownership')}
  assert(rejected,'setup cleanup ownership was accepted: '+cleanup);
  reportCase(name);
 }
 const declared=unit(['var optional_9 = c.pi_js_undefined();','native_values[0] = optional_9;','native_values[0] = try s.text("engine.freeValue(");','native_values[1] = try rt.invoke(s, native_values[0], c.pi_js_undefined(), &.{});'],[region(0,3,3,'native_values[1]','native_values[0]','&.{}')]);
 assert(outlineCallPreparations([declared],owner(),[]).provenance[0].declaredLocals.includes('optional_9'),'region-owned local rejected');
 reportCase('region-owned local and quoted cleanup text remain admissible');
 return{scope:'static authoring boundary/closure controls only; no TypeBox Source/native qualification',cases:9};
}
// Direct-file mode only: the generator's ordinary import remains definitions only.
if(process.argv[2]==='--tooling-controls'){
 if(process.argv.length!==4||process.argv[3]!=='--owned-start')throw Error('Pure tooling controls require exact owned-start arguments');
 const {readFileSync}=await import('node:fs');
 if(readFileSync(0,'utf8')!=='TYPEBOX_TOOLING_CONTROLS_OWNED_START\n')throw Error('Pure tooling controls owned-start token required');
 console.log('TAP version 13');
 let count=0;
 const result=checkCallSetupAuthoring(name=>console.log(`ok ${++count} - ${name}`));
 if(count!==9||result.cases!==9)throw Error('Pure tooling controls exact count mismatch');
 console.log('1..9');
}
