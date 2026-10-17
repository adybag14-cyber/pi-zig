// Prepared pure authoring controls, unrun. No TypeBox Source/native authority.
import {admitPreparedCallStep,outlineCallPreparations} from './outline-call-setup.mjs';
function assert(value,message){if(!value)throw Error('Static prepared-call regression: '+message)}
function fixture({empty=false,construct=false}={}){
 const arguments_ = empty?'&.{}':'native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f0_1__]';
 const resultIndex=empty?1:2,callLine=empty?1:2;
 const region={start:0,calleeEnd:1,end:callLine,callLine,resultIndex,resultSlot:`native_values[${resultIndex}]`,callable:'native_values[0]',callReceiver:'c.pi_js_undefined()',arguments:arguments_,argumentRange:{owner:'f0',start:0,count:empty?0:1,empty},construct,helper:0,descriptor:0,sourceStart:0,sourceEnd:10,sourceHash:'synthetic-static-control-not-Source'};
 const lines=['native_values[0] = try rt.get(s, env, "callee");'];
 if(!empty)lines.push('native_values[__TYPEBOX_NATIVE_ARG_f0_0__] = c.pi_js_undefined();');
 lines.push(`${region.resultSlot} = try rt.${construct?'construct':'invoke'}(s, native_values[0], ${construct?'':'c.pi_js_undefined(), '}${arguments_});`);
 const unit={kind:'callback',id:0,owner:'f0',source:'synthetic-static-control-not-Source',scoped:true,lines,regions:[region],flags:{receiver:false,args:false,env:true}};
 const frame={key:'f0',base:resultIndex+1,count:empty?0:1,ranges:empty?[]:[{start:0,count:1}],descriptorCount:2,descriptors:[{helper:'call_setup_0',offset:0,count:2}]};
 return{unit,region,frame};
}
export function checkCallStepAuthoring(reportCase=()=>{}){
 let cases=0;const pass=name=>{cases++;reportCase(name)};
 const own=fixture(),original=JSON.stringify({lines:own.unit.lines,regions:own.unit.regions,flags:own.unit.flags,base:own.frame.base,count:own.frame.count,ranges:own.frame.ranges});
 const outlined=outlineCallPreparations([own.unit],new Map([['f0',own.frame]]),[],{preparedCallSteps:true});
 assert(JSON.stringify({lines:own.unit.lines,regions:own.unit.regions,flags:own.unit.flags,base:own.frame.base,count:own.frame.count,ranges:own.frame.ranges})===original,'original recorded stream/frame changed');
 assert(own.unit.emittedBody.endsWith('try invokePrepared(s, native_values, __TYPEBOX_NATIVE_SETUP_f0_0__, __TYPEBOX_NATIVE_ARG_f0_0__, __TYPEBOX_NATIVE_ARG_f0_1__, 2);'),'original call boundary/indexes not retained');
 assert(outlined.steps.length===1&&outlined.steps[0].resultIndex===2&&outlined.steps[0].argumentCount===1&&outlined.provenance.length===1,'separate step/preparation provenance differs');
 pass('invoke step retains original owner slot slice boundary and metadata');
 const shared=outlined.native.slice(0,outlined.native.indexOf('noinline fn call_setup_0'));
 assert(shared.includes('noinline fn invokePrepared')&&shared.includes('noinline fn constructPrepared'),'two distinct noinline steps missing');
 assert(shared.includes('values[result] = try rt.invoke(s, values[descriptor], values[descriptor + 1], values[first_arg..end_arg]);'),'invoke does not store result after successful original call');
 assert(shared.includes('values[result] = try rt.construct(s, values[descriptor], values[first_arg..end_arg]);'),'construct does not store result after successful original call');
 assert(!/\b(?:own|alloc|deinit|free|destroy|defer|errdefer|JS_DupValue|JS_FreeValue)\b/.test(shared),'shared call step acquires ownership/cleanup');
 pass('two noinline steps only call and store existing Scope-owned success');
 const empty=fixture({empty:true}),emptyOutput=outlineCallPreparations([empty.unit],new Map([['f0',empty.frame]]),[],{preparedCallSteps:true});
 assert(empty.unit.emittedBody.endsWith('try invokePrepared(s, native_values, __TYPEBOX_NATIVE_SETUP_f0_0__, 0, 0, 1);')&&empty.frame.count===0&&empty.frame.ranges.length===0&&emptyOutput.steps[0].absoluteArgumentStart===0&&emptyOutput.steps[0].absoluteArgumentEnd===0,'empty case reads/allocates/invents arguments');
 pass('empty original arguments become zero-zero slice without slots');
 const construction=fixture({construct:true}),constructionOutput=outlineCallPreparations([construction.unit],new Map([['f0',construction.frame]]),[],{preparedCallSteps:true});
 assert(construction.unit.emittedBody.includes('try constructPrepared(')&&constructionOutput.steps[0].construct,'synthetic dormant constructor route lost');
 pass('dormant constructor route is distinct synthetic authoring only');
 const nestedLines=[
  'native_values[0] = try rt.get(s, env, "object");',
  'native_values[1] = try rt.key(s, native_values[0], c.pi_js_undefined());',
  'native_values[2] = try rt.get(s, env, "inner");',
  'native_values[3] = try rt.invoke(s, native_values[2], c.pi_js_undefined(), &.{});',
  'native_values[__TYPEBOX_NATIVE_ARG_f0_0__] = native_values[3];',
  'native_values[4] = try rt.invoke(s, native_values[1], native_values[0], native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f0_1__]);',
 ];
 const inner={start:2,calleeEnd:3,end:3,callLine:3,resultIndex:3,resultSlot:'native_values[3]',callable:'native_values[2]',callReceiver:'c.pi_js_undefined()',arguments:'&.{}',argumentRange:{owner:'f0',start:0,count:0,empty:true},construct:false,sourceStart:2,sourceEnd:3,sourceHash:'synthetic'};
 const outer={start:0,calleeEnd:2,end:5,callLine:5,resultIndex:4,resultSlot:'native_values[4]',callable:'native_values[1]',callReceiver:'native_values[0]',arguments:'native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f0_1__]',argumentRange:{owner:'f0',start:0,count:1,empty:false},construct:false,sourceStart:0,sourceEnd:5,sourceHash:'synthetic'};
 const nestedUnit={...own.unit,lines:nestedLines,regions:[inner,outer]},nestedFrame={key:'f0',base:5,count:1,ranges:[{start:0,count:1}]};
 const nested=outlineCallPreparations([nestedUnit],new Map([['f0',nestedFrame]]),[],{preparedCallSteps:true});
 const outerHelper=nested.native.slice(nested.native.indexOf('noinline fn call_setup_0'),nested.native.indexOf('noinline fn call_setup_1'));
 const saved=outerHelper.indexOf('native_values[__TYPEBOX_NATIVE_SETUP_f0_0__] = native_values[1]'),prepared=outerHelper.indexOf('try call_setup_1('),actual=outerHelper.indexOf('try invokePrepared(s, native_values, __TYPEBOX_NATIVE_SETUP_f0_2__, 0, 0, 3);');
 assert(saved>=0&&prepared>saved&&actual>prepared&&actual<outerHelper.indexOf('native_values[__TYPEBOX_NATIVE_ARG_f0_0__] = native_values[3]'),'nested callee/argument/real call order changed');
 assert(nested.steps.length===2&&nestedFrame.descriptorCount===4&&!nested.provenance[0].abiNeeds.receiver,'nested descriptors/lexical receiver changed');
 pass('nested actual call stays after own preparation inside original outer preparation');
 const negatives=[
  ['out-of-bounds result rejects',x=>{x.region.resultIndex=x.frame.base;x.region.resultSlot=`native_values[${x.frame.base}]`},'original operand slot'],
  ['negative result rejects',x=>{x.region.resultIndex=-1},'original operand slot'],
  ['result spelling mismatch rejects',x=>{x.region.resultSlot='native_values[02]'},'original operand slot'],
  ['foreign frame owner rejects',x=>{x.frame.key='f1'},'owner/frame identity'],
  ['foreign argument owner rejects',x=>{x.region.argumentRange.owner='f1'},'argument owner/range'],
  ['foreign emitted slice endpoint rejects',x=>{x.region.arguments='native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f1_1__]'},'emitted argument slice'],
  ['argument range beyond original area rejects',x=>{x.region.argumentRange.start=1},'one exact original slice'],
  ['fusion of adjacent original slices rejects',x=>{x.frame.count=2;x.frame.ranges=[{start:0,count:1},{start:1,count:1}];x.region.argumentRange.count=2},'one exact original slice'],
  ['unsupported raw argument expression rejects',x=>{x.region.arguments='other_values'},'emitted argument slice'],
  ['false empty argument metadata rejects',x=>{x.region.argumentRange.empty=true},'original empty arguments'],
  ['descriptor pair beyond existing area rejects',x=>{x.frame.descriptorCount=1},'descriptor pair'],
  ['descriptor allocation mismatch rejects',x=>{x.frame.descriptors[0].offset=2},'descriptor pair'],
  ['original call line mismatch rejects',x=>{x.unit.lines[x.region.callLine]='native_values[2] = try rt.other(s);'},'original recorded call'],
 ];
 for(const [name,change,message] of negatives){const x=fixture();change(x);let rejected=false;try{admitPreparedCallStep(x.unit,x.region,x.frame)}catch(error){rejected=String(error).includes(message)}assert(rejected,name);pass(name)}
 return{scope:'Pure static call-step admission/ordering controls only; no TypeBox Source/native constructor or frame qualification',cases};
}
if(process.argv[2]==='--call-step-controls'){
 if(process.argv.length!==4||process.argv[3]!=='--owned-start')throw Error('Call-step controls require exact owned-start arguments');
 const {readFileSync}=await import('node:fs');
 if(readFileSync(0,'utf8')!=='TYPEBOX_CALL_STEP_CONTROLS_OWNED_START\n')throw Error('Call-step controls owned-start token required');
 console.log('TAP version 13');let count=0;
 const result=checkCallStepAuthoring(name=>console.log(`ok ${++count} - ${name}`));
 if(result.cases!==18||count!==18)throw Error('Call-step controls exact count differs');
 console.log('1..18');
}
