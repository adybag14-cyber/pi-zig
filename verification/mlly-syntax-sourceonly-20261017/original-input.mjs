// Prepared original user input. Genuine reference binds this name to the real
// unchanged package export mlly1.8.2.hasESMSyntax; native binds the real leaf.
// No cloned/extracted JavaScript implementation is used as a reference.
const hasESMSyntax = globalThis.ActualMllyHasESMSyntax;
const observations = [];
for (const [id, code, options] of [
  ["empty", ""],
  ["const", "const value = 1;"],
  ["static-import", "import value from './value.js';"],
  ["side-effect-import", "import './value.js';"],
  ["export-default", "export default 1;"],
  ["export-type", "export type Value = string;"],
  ["export-async", "export async function value(){}"],
  ["meta", "const url = import.meta.url;"],
  ["dynamic-import", "const value = import('./value.js');"],
  ["comment-default", "/* export const value = 1 */"],
  ["comment-strip", "/* export const value = 1 */", {stripComments:true}],
  ["line-comment-nr", "// export const number = 1\nconst value = 2;", {stripComments:true}],
  ["multiline-comment", "/*\nexport const value = 1\n*/", {stripComments:true}],
  ["string-false-positive", "const text = ' export const value = 1';"],
  ["unicode", "\u2028export const café = 1;"],
  ["commonjs", "module.exports = require('./value');"],
  ["null-code", null],
  ["number-code", 17],
  ["null-options", "export const value = 1", null],
  ["symbol-code", Symbol("source")]
]) {
  try { observations.push({id, result:hasESMSyntax(code, options)}); }
  catch(reason) { observations.push({id, thrownName:reason?.name}); }
}
const trace = [];
const reason = {identity:"raw"};
const code = {[Symbol.toPrimitive](hint){trace.push(["coerce",hint]);return "export const value = 1;";}};
observations.push({id:"coercion", result:hasESMSyntax(code), trace:trace.splice(0)});
try { hasESMSyntax("", {get stripComments(){trace.push("strip-get");throw reason;}}); }
catch(thrown) { observations.push({id:"strip-get-throw", sameReason:thrown === reason, trace:trace.splice(0)}); }

const prototype = RegExp.prototype;
const oldTest = Object.getOwnPropertyDescriptor(prototype,"test");
let originalRegex;
const returnMarker = {raw:"test-result"};
Object.defineProperty(prototype,"test",{configurable:true,get(){
  trace.push(["test-get",this === originalRegex,this.source,this.flags]);
  originalRegex ??= this;
  return function(value){trace.push(["test-call",this === originalRegex,value === code]);return returnMarker;};
}});
try {
  const first = hasESMSyntax(code);
  const second = hasESMSyntax(code);
  observations.push({id:"module-constant-raw-result",firstIsRaw:first === returnMarker,secondIsRaw:second === returnMarker,trace:trace.splice(0)});
} finally { Object.defineProperty(prototype,"test",oldTest); }

let commentsRegex;
const replacementResult = {toString(){trace.push("replacement-toString");return "export const value = 2";}};
const replacingCode = {get replace(){trace.push("replace-get");return function(regex,replacement){
  trace.push(["replace-call",this === replacingCode,regex === commentsRegex,regex.source,regex.flags,replacement]);
  commentsRegex ??= regex;
  return replacementResult;
};}};
const replacementOptions = {get stripComments(){trace.push("strip-get");return {};}};
const firstReplacement = hasESMSyntax(replacingCode,replacementOptions);
const secondReplacement = hasESMSyntax(replacingCode,replacementOptions);
observations.push({id:"comment-constant-and-raw-replacement",firstReplacement,secondReplacement,trace:trace.splice(0)});

const oldInherited = Object.getOwnPropertyDescriptor(Object.prototype,"stripComments");
Object.defineProperty(Object.prototype,"stripComments",{configurable:true,get(){trace.push("inherited-strip-get");return false;}});
try { observations.push({id:"default-options-inherits",result:hasESMSyntax("export const value = 1"),trace:trace.splice(0)}); }
finally { if(oldInherited)Object.defineProperty(Object.prototype,"stripComments",oldInherited);else delete Object.prototype.stripComments; }

observations.push({id:"ordinary-shape",name:hasESMSyntax.name,length:hasESMSyntax.length,
  ownPrototype:Object.hasOwn(hasESMSyntax,"prototype"),
  ownPrototypeConstructor:hasESMSyntax.prototype.constructor === hasESMSyntax});
export {observations};
