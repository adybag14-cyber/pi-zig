Error.stackTraceLimit=1;
const constructorLocations=[];
function locationCase(id,run,functions){
  let observed;
  Error.prepareStackTrace=(error,frames)=>{observed=frames.map(frame=>({name:frame.getFunctionName(),file:frame.getFileName(),line:frame.getLineNumber(),column:frame.getColumnNumber(),native:frame.isNative(),constructor:frame.isConstructor(),originalFunction:functions.some(fn=>frame.getFunction()===fn)}));return'constructor-location'};
  const error=run();const stack=error.stack;
  constructorLocations.push({id,stack,frames:observed,second:error.stack});
}
function named(){return new Error('named')}
function spaced(){return new       Error('spaced')}
function noArguments(){return new Error()}
function noParentheses(){return new Error}
const holder={Error};
function property(){return new holder.Error('property')}
function computed(){return new holder['Error']('computed')}
function multiline(){return new
  Error('multiline')}
function argument(){return new Error(String(1))}
function spread(){return new Error(...['spread'])}
function target(){return new (function choose(){return Error}())('target')}
function parenthesized(){return new (holder.Error)('parenthesized')}
locationCase('named',named,[named]);
locationCase('spaced',spaced,[spaced]);
locationCase('noArguments',noArguments,[noArguments]);
locationCase('noParentheses',noParentheses,[noParentheses]);
locationCase('property',property,[property]);
locationCase('computed',computed,[computed]);
locationCase('multiline',multiline,[multiline]);
locationCase('argument',argument,[argument]);
locationCase('spread',spread,[spread]);
locationCase('target',target,[target]);
locationCase('parenthesized',parenthesized,[parenthesized]);
Error.stackTraceLimit=2;
let observedNewTarget;
function NewTarget(){observedNewTarget=new.target===NewTarget;return new Error('new-target')}
function newTargetCaller(){return new NewTarget()}
locationCase('newTarget',newTargetCaller,[NewTarget,newTargetCaller]);
constructorLocations.push({id:'newTargetIdentity',value:observedNewTarget});
globalThis.constructorLocationResult=constructorLocations;
