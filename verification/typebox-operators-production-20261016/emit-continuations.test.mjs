// Prepared pure tooling controls. Importing this file never loads TypeBox/Acorn.
import test from 'node:test';
import assert from 'node:assert/strict';
import {emitContinuations} from './emit-continuations.mjs';
const source='type/engine/instantiate.mjs';
function fixture(records,id=0){
 const owner=`f${id}`,frame={key:owner,base:6,count:2,ranges:[{start:0,count:2}],descriptorCount:0};
 const f={id,name:'Example',module:{file:source},node:{start:0,end:20},originalSlots:6,slots:8,arrow:false,usesReceiver:false,usesArgs:true,usesEnv:true,unit:{owner,records}};
 return{functions:[f],branches:[],tries:[],frames:new Map([[owner,frame]])};
}
function compile(packet){return emitContinuations(packet.functions,packet.branches,packet.tries,packet.frames,{expectedCount:1})}
function call(overrides={}){return{kind:'call',owner:'f0',callable:'native_values[0]',receiver:'native_values[1]',args:'native_values[__TYPEBOX_NATIVE_ARG_f0_0__..__TYPEBOX_NATIVE_ARG_f0_2__]',range:{owner:'f0',start:0,count:2,empty:false},result:2,construct:false,...overrides}}
test('TypeBox heap authoring real calls become typed yields with original slots',()=>{
 const result=compile(fixture([call(),{kind:'returned',value:'native_values[2]'}]));
 assert.match(result.native,/\.call =/);assert.match(result.native,/\.result = 2/);assert.equal(result.provenance[0].actualCallSites,1);
 assert.match(result.native,/noinline fn typebox_pc_/);assert.doesNotMatch(result.native,/rt\.invoke\(/);
});
test('TypeBox heap authoring original empty arguments use zero-length heap slice',()=>{
 const result=compile(fixture([call({args:'&.{}',range:{owner:'f0',start:0,count:0,empty:true}})]));
 assert.match(result.native,/\.args = native_values\[0\.\.0\]/);
});
test('TypeBox heap authoring selected-only branch preserves predicate and chosen paths',()=>{
 const packet=fixture([{kind:'branch_result',id:0,result:3},{kind:'returned',value:'native_values[3]'}]);
 packet.branches=[{unit:{owner:'f0',records:[{kind:'if',test:'s.truthy(native_values[0])'},{kind:'branch_value',value:'native_values[1]'},{kind:'else'},{kind:'branch_value',value:'native_values[2]'},{kind:'endif'}]}}];
 const result=compile(packet);assert.equal((result.native.match(/s.truthy/g)??[]).length,1);assert.match(result.native,/native_values\[3\] = native_values\[1\]/);assert.match(result.native,/native_values\[3\] = native_values\[2\]/);
});
test('TypeBox heap authoring actual single try finally gets typed completion boundary',()=>{
 const packet=fixture([{kind:'try',id:0},{kind:'emit',text:'try rt.bind(s, env, "cleanup", c.pi_js_undefined());'},{kind:'end_finally'}],662);
 packet.tries=[{unit:{owner:'f662',records:[{kind:'returned',value:'native_values[0]'}]}}];
 const result=compile(packet);assert.match(result.native,/enter_finally/);assert.match(result.native,/finish_finally/);assert.match(result.native,/\.returned = native_values\[0\]/);
});
test('TypeBox heap authoring arrow lexical receiver stays separate from method receiver',()=>{
 const packet=fixture([{kind:'returned',value:'receiver'}]);packet.functions[0].arrow=true;packet.functions[0].usesReceiver=true;
 const result=compile(packet);assert.match(result.native,/const receiver = roots\[1\]/);assert.equal(result.provenance[0].originalFlags.arrow,true);
});
test('TypeBox heap authoring constructor remains explicit fallback operation',()=>{
 const result=compile(fixture([call({construct:true})]));assert.match(result.native,/\.construct = true/);assert.equal(result.provenance[0].constructCallSites,1);
});
test('TypeBox heap authoring quoted cleanup and call names are inert literals',()=>{
 const result=compile(fixture([{kind:'emit',text:'native_values[0] = try s.text("rt.invoke() JS_FreeValueRT engine.gpa.free");'}]));
 assert.match(result.native,/s.text/);
});
for(const [name,mutate] of [
 ['foreign call owner',r=>r.owner='f1'],
 ['result outside original slots',r=>r.result=6],
 ['foreign argument owner',r=>r.range.owner='f1'],
 ['argument range outside allocation',r=>r.range.count=3],
 ['argument expression differs',r=>r.args='native_values[0..2]'],
 ['noncanonical empty arguments',r=>{r.range={owner:'f0',start:0,count:0,empty:true};r.args='native_values[0..0]'}],
 ['nonboolean constructor flag',r=>r.construct='false'],
 ['unevaluated callable expression',r=>r.callable='try rt.get(s, env, "target")'],
 ['receiver outside original operand area',r=>r.receiver='native_values[6]'],
])test(`TypeBox heap authoring rejects ${name}`,()=>{const r=call();mutate(r);assert.throws(()=>compile(fixture([r])))});
test('TypeBox heap authoring rejects free native local across a yield',()=>assert.throws(()=>compile(fixture([{kind:'emit',text:'native_values[0] = optional_9;'}]))));
test('TypeBox heap authoring rejects free local in numeric slice end',()=>assert.throws(()=>compile(fixture([{kind:'emit',text:'_ = native_values[0..optional_9];'}]))));
test('TypeBox heap authoring rejects native temporary declarations',()=>assert.throws(()=>compile(fixture([{kind:'emit',text:'var temporary = native_values[0];'}]))));
test('TypeBox heap authoring rejects caller storage cleanup',()=>assert.throws(()=>compile(fixture([{kind:'emit',text:'engine.gpa.free(native_values);'}]))));
test('TypeBox heap authoring rejects JS root cleanup',()=>assert.throws(()=>compile(fixture([{kind:'emit',text:'c.JS_FreeValueRT(engine.runtime, native_values[0]);'}]))));
test('TypeBox heap authoring rejects incomplete typed conditionals',()=>assert.throws(()=>compile(fixture([{kind:'if',test:'true'}]))));
test('TypeBox heap authoring rejects cyclic original branch references',()=>{
 const packet=fixture([{kind:'branch_result',id:0,result:0}]);packet.branches=[{unit:{owner:'f0',records:[{kind:'branch_jump',id:0}]}}];assert.throws(()=>compile(packet));
});
test('TypeBox heap authoring rejects foreign branch owner',()=>{
 const packet=fixture([{kind:'branch_result',id:0,result:0}]);packet.branches=[{unit:{owner:'f1',records:[{kind:'branch_value',value:'c.pi_js_undefined()'}]}}];assert.throws(()=>compile(packet));
});
test('TypeBox heap authoring rejects unknown control record',()=>assert.throws(()=>compile(fixture([{kind:'iterator'}]))));
test('TypeBox heap authoring rejects an unrecorded synchronous call',()=>assert.throws(()=>compile(fixture([{kind:'emit',text:'native_values[0] = try rt.invoke(s, native_values[1], c.pi_js_undefined(), native_values[0..0]);'}]))));
test('TypeBox heap authoring rejects changed finite callback census',()=>{
 const packet=fixture([]);assert.throws(()=>emitContinuations(packet.functions,[],[],packet.frames));
});
