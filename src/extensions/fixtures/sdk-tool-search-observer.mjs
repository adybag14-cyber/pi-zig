// Actual c268 tool-search bodies in separate fresh Source/native Engines.
// Both modules use the genuine retained TypeBox graph; no ranker/tool substitute
// is installed in production. Overrides below are ordinary observable inputs.
function searchAssert(value, message) { if (!value) throw new Error("tool-search: " + message); }
function searchSame(actual, expected, message) { searchAssert(Object.is(actual, expected), message); }
function searchList(actual, expected, message) {
  searchAssert(actual.length === expected.length, message + " length");
  for (let i = 0; i < expected.length; i++) searchSame(actual[i], expected[i], message + " item " + i);
}
function searchRestore(object, name, descriptor) {
  if (descriptor) Object.defineProperty(object, name, descriptor); else delete object[name];
}
function searchThrown(body) {
  try { body(); } catch (reason) { return reason; }
  throw new Error("tool-search: expected ordinary throw");
}
function searchMetadata(name, description, exposure = "deferred") {
  return {name, description, exposure, parameters:{type:"object",properties:{}}};
}
function searchApi(all, active = []) {
  const api = {
    active, all, changes:[],
    getActiveTools() { searchSame(this, api, "getActiveTools receiver"); return this.active; },
    getAllTools() { searchSame(this, api, "getAllTools receiver"); return this.all; },
    setActiveTools(value) { searchSame(this, api, "setActiveTools receiver"); this.changes.push(value); this.active = value; },
  };
  return api;
}
function observeToolSearchShapes(S) {
  for (const [name, length] of [["tokenize",1],["createToolSearchDocument",2],["createToolSearchToolDefinition",0],["createToolSearchExtension",0]]) {
    const fn = S[name];
    searchSame(fn.name, name, "ordinary name"); searchSame(fn.length, length, "ordinary length");
    searchAssert(Object.hasOwn(fn, "prototype"), "ordinary callable has its real prototype");
  }
  searchSame(S.TOOL_SEARCH_TOOL_NAME, "tool_search", "name constant");
  searchSame(S.DEFAULT_TOOL_SEARCH_LIMIT, 8, "limit constant");
  searchSame(S.Bm25Ranker.name, "Bm25Ranker", "real class name");
  searchSame(S.Bm25Ranker.length, 0, "defaulted constructor length");
  const rank = Object.getOwnPropertyDescriptor(S.Bm25Ranker.prototype, "rank");
  searchAssert(rank.writable && !rank.enumerable && rank.configurable, "class method descriptor");
  searchSame(rank.value.name, "rank", "class method name"); searchSame(rank.value.length, 3, "class method length");
  searchAssert(!Object.hasOwn(rank.value, "prototype"), "actual method is not a constructor");
  searchAssert(searchThrown(() => S.Bm25Ranker()) instanceof TypeError, "class requires new");
  const value = S.createToolSearchToolDefinition();
  searchList(Reflect.ownKeys(value), ["name","label","description","promptSnippet","parameters","exposure","reachesTools","execute"], "definition literal fields");
  for (const field of Reflect.ownKeys(value)) {
    const d = Object.getOwnPropertyDescriptor(value, field);
    searchAssert(d.writable && d.enumerable && d.configurable && "value" in d, "literal descriptor " + field);
  }
  searchSame(value.parameters, S.toolSearchSchema, "same actual schema");
  searchSame(value.description, S.TOOL_SEARCH_DESCRIPTION, "same static description");
  searchSame(value.exposure, "model-only", "exposure"); searchSame(value.reachesTools(), "all", "reaches all tools");
  searchSame(value.reachesTools.name, "reachesTools", "arrow name"); searchSame(value.reachesTools.length, 0, "arrow length");
  searchAssert(!Object.hasOwn(value.reachesTools, "prototype"), "real reaches arrow");
  searchSame(value.execute.name, "execute", "async method name"); searchSame(value.execute.length, 2, "async method length");
  searchAssert(toolSearchIsAsync(value.execute), "real VM async brand");
  searchSame(Object.getPrototypeOf(value.execute), Object.getPrototypeOf(async function(){}), "intrinsic async prototype");
  searchAssert(!Object.hasOwn(value.execute, "prototype"), "real async nonconstructor");
  for (const extension of [S.default, S.createToolSearchExtension()]) {
    searchSame(extension.name, "", "anonymous extension arrow"); searchSame(extension.length, 1, "extension arity");
    searchAssert(!Object.hasOwn(extension, "prototype"), "extension is a real arrow");
  }
}
function observeToolSearchSchemaAndClass(S) {
  const schema = S.toolSearchSchema;
  searchSame(schema.type, "object", "actual Type.Object");
  searchSame(schema.properties.query.type, "string", "actual Type.String");
  searchSame(schema.properties.limit.type, "number", "actual Type.Number");
  searchSame(schema.properties.limit.description, "Maximum number of tools to return. Defaults to 8.", "schema intrinsic template");
  searchList(schema.required, ["query"], "actual optional limit");
  let setters = 0, reads = [];
  function Target() {}
  Target.prototype = {set k1(_) {setters++;}, set b(_) {setters++;}};
  const value = Reflect.construct(S.Bm25Ranker, [{get k1(){reads.push("k1");return 2;},get b(){reads.push("b");return 0;}}], Target);
  searchSame(Object.getPrototypeOf(value), Target.prototype, "actual newTarget prototype");
  searchList(Object.keys(value), ["k1","b"], "actual emitted fields");
  searchSame(value.k1, 2, "k1 value"); searchSame(value.b, 0, "b value");
  searchSame(setters, 0, "own class fields precede constructor Set"); searchList(reads, ["k1","b"], "ordered options getters");
  const normal = new S.Bm25Ranker({k1:null,b:undefined});
  searchSame(normal.k1, 1.2, "nullish k1"); searchSame(normal.b, .75, "nullish b");
}
function observeToolSearchTokenize(S) {
  searchList(S.tokenize("getHTTPResponse issues searches foxes classes boxes studies"), ["get","http","response","issue","search","fox","class","box","study"], "real camel/acronym/stemming algorithm");
  searchList(S.tokenize("a An WITH CamelCase HTTPServer foo_bar 123"), ["camel","case","http","server","foo","bar","123"], "stop words and separators");
  searchList(S.tokenize(""), [], "empty text");
  searchList(S.tokenize("a an and are as at be by for from in is it of on or that the this to with"), [], "all actual stop words");
}
function observeToolSearchTokenChain(S, H) {
  const trace = [], marker = {};
  const input = { get replace() {
    trace.push("replace1:get");
    const fn = function(pattern, replacement) {
      searchAssert(pattern instanceof RegExp && pattern.source === "([a-z0-9])([A-Z])" && pattern.global, "first real literal");
      searchSame(replacement, "$1 $2", "first replacement"); trace.push("replace1:call");
      return {holder:H.make(1), get replace() {
        searchSame(H.count(0), 1, "first callee before second getter"); trace.push("replace2:get");
        const next = function(pattern2, replacement2) {
          searchAssert(pattern2 instanceof RegExp && pattern2.source === "([A-Z]+)([A-Z][a-z])" && pattern2.global, "second fresh literal");
          searchSame(replacement2, "$1 $2", "second replacement");
          return {get toLowerCase() {
            searchSame(H.count(1), 1, "second receiver before lower getter"); searchSame(H.count(2), 1, "second callee before lower getter");
            return function() { return {split(pattern3) {
              searchAssert(pattern3 instanceof RegExp && pattern3.source === "[^a-z0-9]+", "split literal");
              return {filter(callback) {
                searchSame(callback.name, "", "actual filter arrow"); searchSame(callback.length, 1, "filter arity");
                searchSame(callback("cat"), true, "filter invokes actual stop set"); searchSame(callback("and"), false, "stop word filter");
                return {map(stem) { searchSame(stem.name, "stem", "actual stem declaration"); searchSame(stem("studies"), "study", "actual stem body"); return marker; }};
              }};
            }}; };
          }};
        };
        next.holder = H.make(2); return next;
      }};
    };
    fn.holder = H.make(0); return fn;
  }};
  searchSame(S.tokenize(input), marker, "transfers raw final method value");
  searchList(trace, ["replace1:get","replace1:call","replace2:get"], "real receiver chain");
}
function observeToolSearchFilterPredicate(S, H) {
  const old = Object.getOwnPropertyDescriptor(Set.prototype, "has"), original = Set.prototype.has;
  let retained;
  const input = {replace(){return this;},toLowerCase(){return this;},split(){return this;},
    filter(callback){retained=callback;return this;},map(){return [];}};
  S.tokenize(input);
  Object.defineProperty(Set.prototype, "has", {configurable:true,get(){
    searchSame(H.count(0), 1, "length comparison operand retired before Set.has");
    return original;
  }});
  try {
    searchSame(retained({get length(){const value=H.make(0);value.valueOf=()=>1;return value;}}), true, "actual retained filter callback");
  } finally {Object.defineProperty(Set.prototype,"has",old);}
}
function observeToolSearchDocument(S) {
  const schema = {description:"root",properties:{child:{description:"leaf",items:{description:"item"}}},
    anyOf:[{description:"alternative"}],oneOf:[{description:"one"}],allOf:[{description:"all"}]};
  const value = S.createToolSearchDocument({name:"read_file",description:"read source",parameters:schema},
    {name:"workspace",description:"files",instructions:"safe reads"});
  searchList(Object.keys(value), ["name","text"], "document literal fields");
  searchSame(value.name, "read_file", "raw tool name");
  searchSame(value.text, "read_file read file read source root child leaf item alternative one all workspace files safe reads", "real recursive schema document");
  searchSame(S.createToolSearchDocument({name:"blank",description:"",parameters:null}).text, "blank blank", "empty parts filtered");
}
function observeToolSearchDocumentOrder(S, H) {
  let reads = 0; const trace = [];
  const tool = {
    get name(){ trace.push("name:"+ ++reads); return reads === 2 ? {get replaceAll(){
      trace.push("replace:get"); const fn=function(a,b){searchList([a,b],["_"," "],"replaceAll args");return "words";};fn.holder=H.make(0);return fn;
    }} : "snake_case"; },
    get description(){searchSame(H.count(0),1,"replace callee before description");trace.push("description");return "desc";},
    get parameters(){trace.push("parameters");return null;},
  };
  searchSame(S.createToolSearchDocument(tool).text,"snake_case words desc","live name reads");
  searchList(trace,["name:1","name:2","replace:get","description","parameters","name:3"],"ordered document expressions");
  const old=Object.getOwnPropertyDescriptor(Array,"isArray");let arrayCalls=0;
  Object.defineProperty(Array,"isArray",{configurable:true,value(value){arrayCalls++;return false;}});
  try {
    S.createToolSearchDocument({name:"x",description:"d",parameters:()=>{}});
    searchSame(arrayCalls,0,"function schema is skipped before any Array.isArray call");
  } finally {Object.defineProperty(Array,"isArray",old);}
}
function observeToolSearchSchemaIteratorClose(S) {
  const entries = Object.getOwnPropertyDescriptor(Object,"entries"), reason={}, trace=[];
  Object.defineProperty(Object,"entries",{configurable:true,value(){
    return {[Symbol.iterator](){return {next(){trace.push("next");return {done:false,value:{
      [Symbol.iterator](){let step=0;return {next(){trace.push("pair:"+step);return {done:false,value:step++===0?"child":{get description(){throw reason;}}};},
        return(){trace.push("pair:return");return {done:true};}};}
    }};},return(){trace.push("outer:return");return {done:true};}};}};
  }});
  try {
    const result=searchThrown(()=>S.createToolSearchDocument({name:"x",description:"d",parameters:{properties:{}}}));
    searchSame(result,reason,"body reason survives real close");
    searchList(trace,["next","pair:0","pair:1","pair:return","outer:return"],"real destructuring and outer IteratorClose");
  } finally {Object.defineProperty(Object,"entries",entries);}
}
function observeToolSearchSchemaPairRetirement(S,H,done) {
  const entriesDescriptor=Object.getOwnPropertyDescriptor(Object,"entries");
  const pushDescriptor=Object.getOwnPropertyDescriptor(Array.prototype,"push");
  const order=toolSearchOrder;
  function pair(second) {
    if(!done) return {
      [Symbol.iterator]() { return this; },
      holder:order.make(1),
      get next() {
        let step=0;
        const fn=function(){return {done:false,value:step++===0?"child":null};};
        fn.holder=order.make(0);return fn;
      },
      get return() {
        searchList(order.read(),[0],"cached next retires before normal return getter");
        return function(){return {done:true};};
      },
    };
    if(second) return {
      [Symbol.iterator]() { return this; },
      holder:order.make(2),
      get next() {
        const fn=function(){return {done:true};};
        fn.holder=order.make(3);return fn;
      },
    };
    return {
      [Symbol.iterator]() { return this; },
      get next() {
        let step=0;
        return function(){return {done:false,value:order.make(step++)};};
      },
    };
  }
  Object.defineProperty(Object,"entries",{configurable:true,value(){
    return {[Symbol.iterator](){
      let row=0;
      return {next(){
        if(row<(done?2:1))return {done:false,value:pair(row++===1)};
        return {done:true};
      }};
    }};
  }});
  // Discard the first row's name so its only remaining owner is the actual
  // destructuring lexical slot. This is a live Source Array.push override.
  Object.defineProperty(Array.prototype,"push",{configurable:true,writable:true,value:function(){return this.length;}});
  try {
    S.createToolSearchDocument({name:"x",description:"d",parameters:{properties:{}}});
    searchList(order.read(),done?[2,0,1,3]:[0,1],
      done?"done receiver then previous bindings then cached next":"normal cached next then iterator receiver");
  } finally {
    Object.defineProperty(Object,"entries",entriesDescriptor);
    Object.defineProperty(Array.prototype,"push",pushDescriptor);
  }
}
function observeToolSearchRanking(S) {
  const ranker=new S.Bm25Ranker();
  const matches=ranker.rank("cat",[{name:"a",text:"cat cat dog"},{name:"b",text:"cat"},{name:"c",text:"dog"}],8);
  searchList(matches.map(x=>x.name),["b","a"],"actual BM25 order");
  const idf=Math.log(1+(3-2+.5)/(2+.5));
  searchAssert(Math.abs(matches[0].score-idf*(2.2/(1+1.2*(.25+.75/(5/3)))))<1e-12,"actual short-document score");
  searchAssert(Math.abs(matches[1].score-idf*(4.4/(2+1.2*(.25+.75*3/(5/3)))))<1e-12,"actual repeated-term score");
  searchList(ranker.rank("cat cat",[{name:"first",text:"cat"},{name:"second",text:"cat"}],1).map(x=>x.name),["first"],"unique terms and stable tie");
  searchList(ranker.rank("and",[{name:"x",text:"cat"}],8),[],"stop-only early return");
  searchList(ranker.rank("cat",[],8),[],"empty documents early return");
  searchList(ranker.rank("cat",[{name:"x",text:"cat"}],0),[],"zero limit early return");
}
function observeToolSearchIdfCapture(S,H) {
  const mapDesc=Object.getOwnPropertyDescriptor(Array.prototype,"map"), originalMap=Array.prototype.map;
  const mapGlobal=Object.getOwnPropertyDescriptor(globalThis,"Map"), NativeMap=Map;
  let captured, maps=0;
  Object.defineProperty(Array.prototype,"map",{configurable:true,writable:true,value:function(callback,...rest){
    if(this.length===1&&this[0]==="cat") captured=callback;
    return Reflect.apply(originalMap,this,[callback,...rest]);
  }});
  globalThis.Map=function(...args){const value=new NativeMap(...args);if(++maps===1)value.holder=H.make(1);return value;};
  try {
    new S.Bm25Ranker().rank("cat",(()=>{const docs=[{name:"x",text:"cat"}];docs.holder=H.make(0);return docs;})(),1);
    searchAssert(typeof captured==="function","actual idf map callback retained");
    searchSame(H.count(0),0,"captured actual documents parameter survives return");searchSame(H.count(1),0,"captured term-count local survives return");
    searchSame(captured("cat")[0],"cat","closed callback still runs its actual body");
    captured=undefined;
    searchSame(H.count(0),1,"actual parameter ref retires when callback drops");searchSame(H.count(1),1,"independent counts cell retires");
  } finally {Object.defineProperty(Array.prototype,"map",mapDesc);Object.defineProperty(globalThis,"Map",mapGlobal);}
}
function observeToolSearchScoreCapture(S,H) {
  let captured;
  const result=S.Bm25Ranker.prototype.rank.call((()=>{const value=new S.Bm25Ranker();value.holder=H.make(0);return value;})(),"cat",
    (()=>{const docs=[{name:"x",text:"cat"}];docs.holder=H.make(1);docs.forEach=function(callback){captured=callback;};return docs;})(),1);
  searchList(result,[],"actual forEach result controls pushes");
  searchSame(H.count(0),0,"scorer retains only actual this capture");searchSame(H.count(1),1,"unused documents parameter retires despite escaped scorer");
  searchSame(captured({name:"later"},0),undefined,"closed scorer uses its real Maps and arrays");
  captured=undefined;searchSame(H.count(0),1,"closed receiver cell drops after scorer");
}
async function observeToolSearchActivation(S) {
  const api=searchApi([searchMetadata("issues_list","List project issues"),searchMetadata("issue_create","Create an issue","codemode"),
    searchMetadata("already","Issues already active"),searchMetadata("model_tool","Issues model metadata","model-only")],["already"]);
  const definition=S.createToolSearchToolDefinition({tools:api}), result=await definition.execute("id",{query:"issues"});
  searchAssert(result.details.loaded.length===2&&result.details.loaded.includes("issues_list")&&result.details.loaded.includes("issue_create"),"actual searchable inactive matches");
  searchList(api.active,["already",...result.details.loaded],"actual activation appends matches");
  searchSame(api.changes.length,1,"one actual activation call");
  searchAssert(result.content[0].text.startsWith("Loaded 2 tools. They are available from your next call:\n"),"real response formatting");
  const second=await definition.execute("id",{query:"issues",limit:8});
  searchSame(second.content[0].text,"No matching tools found.","active matches excluded on next call");searchList(second.details.loaded,[],"no duplicate activation");
}
async function observeToolSearchLiveTools(S,H) {
  const api=searchApi([searchMetadata("cat","cat")]);let reads=0;
  const first={get getActiveTools(){throw Error("first predicate value must not be called");}};
  const definition=S.createToolSearchToolDefinition({get tools(){return ++reads===1?first:api;}});
  const result=await definition.execute("id",{query:"cat"});
  searchSame(reads,2,"options.tools is read twice");searchList(result.details.loaded,["cat"],"second actual tools input consumed");
  let filter;
  const emptyApi={getActiveTools(){const value=[];value.holder=H.make(0);return value;},
    getAllTools(){return {filter(callback){filter=callback;return [];}};},setActiveTools(){throw Error("no match");}};
  await S.createToolSearchToolDefinition({tools:emptyApi}).execute("id",{query:"cat"});
  searchSame(H.count(0),0,"actual active local retained by escaped filter");searchSame(filter(searchMetadata("late","late")),true,"closed candidate filter remains live");
  filter=undefined;searchSame(H.count(0),1,"active cell retires separately after callback drops");
}
async function observeToolSearchValidation(S) {
  const execute=S.createToolSearchToolDefinition().execute;
  const actualPromise=execute("id",{query:"cat"});
  searchAssert(actualPromise instanceof Promise,"actual intrinsic Promise");searchSame((await actualPromise).content[0].text,"No matching tools found.","ordinary no-tools result");
  for(const query of [""," \t\r\n "]) {
    let reason;try{await execute("id",{query});}catch(value){reason=value;}
    searchSame(reason.message,"query must not be empty","actual query validation");
  }
  for(const limit of [0,-1,1.2,NaN,Infinity,"1"]) {
    let reason;try{await execute("id",{query:"cat",limit});}catch(value){reason=value;}
    searchSame(reason.message,"limit must be a positive integer","actual integer validation");
  }
  for(const value of [null,undefined]) {
    let reason;try{await execute("id",value);}catch(error){reason=error;}
    searchAssert(reason instanceof TypeError,"actual parameter BindingPattern failure");
  }
}
async function observeToolSearchBindingAndPredicates(S,H) {
  const descriptors=["query","limit"].map(name=>[name,Object.getOwnPropertyDescriptor(Number.prototype,name)]);
  let boxed, visits=[];
  Object.defineProperty(Number.prototype,"query",{configurable:true,get(){boxed=this;this.holder=H.make(0);visits.push("query");return {trim(){searchSame(H.count(0),1,"boxed binding receiver retired before trim");return "cat";}};}});
  Object.defineProperty(Number.prototype,"limit",{configurable:true,get(){searchSame(this,boxed,"one boxed BindingPattern receiver");visits.push("limit");boxed=undefined;return 1;}});
  try {await S.createToolSearchToolDefinition().execute("id",7);searchList(visits,["query","limit"],"ordered binding getters");}
  finally {for(const [name,descriptor]of descriptors)searchRestore(Number.prototype,name,descriptor);}
  const number=Object.getOwnPropertyDescriptor(Number,"isInteger");
  Object.defineProperty(Number,"isInteger",{configurable:true,value(){return H.make(1);}});
  const definition=S.createToolSearchToolDefinition({get tools(){searchSame(H.count(1),1,"integer return operand retired before tools getter");return undefined;}});
  try {await definition.execute("id",{query:"cat",limit:1});}
  finally {Object.defineProperty(Number,"isInteger",number);}
}
async function observeToolSearchZeroAwaitLifetime(S,H) {
  const execute=S.createToolSearchToolDefinition().execute, originalPromise=Promise;
  const descriptor=Object.getOwnPropertyDescriptor(Object.prototype,"then"), promiseDescriptor=Object.getOwnPropertyDescriptor(globalThis,"Promise");
  let adoptions=0;
  Object.defineProperty(Object.prototype,"then",{configurable:true,get(){
    if(Object.hasOwn(this,"content")) {
      adoptions++;searchSame(H.count(0),0,"unused id argument retained through adoption");searchSame(H.count(1),0,"destructured original argument retained");
      searchSame(H.count(2),0,"query local retained through adoption");
    }
    return undefined;
  }});
  globalThis.Promise=function(){throw Error("zero-Await async must use intrinsic Promise");};
  let result;
  try {
    result=execute(H.make(0),{holder:H.make(1),get query(){const value=H.make(2);value.trim=()=>"cat";return value;},limit:1});
    searchAssert(result instanceof originalPromise,"intrinsic async return");searchSame(adoptions,1,"synchronous final adoption");
    searchSame(H.count(0),1,"caller and native unused id roots retired");searchSame(H.count(1),1,"original argument retired after call");searchSame(H.count(2),1,"local retired only after adoption");
  } finally {Object.defineProperty(globalThis,"Promise",promiseDescriptor);searchRestore(Object.prototype,"then",descriptor);}
  searchSame((await result).content[0].text,"No matching tools found.","real fulfilled value");
}
function observeToolSearchOptionCapture(S,H) {
  let definition=S.createToolSearchToolDefinition({holder:H.make(0)}), reaches=definition.reachesTools;
  searchSame(H.count(0),0,"execute keeps actual options parameter ref");
  delete definition.execute;
  searchSame(H.count(0),1,"unused reaches arrow does not retain options parameter");
  searchSame(reaches(),"all","independent reaches arrow remains actual");
}
async function observeToolSearchTemplates(S,H) {
  const rank=Object.getOwnPropertyDescriptor(S.Bm25Ranker.prototype,"rank"), concat=Object.getOwnPropertyDescriptor(String.prototype,"concat");
  const trace=[], name={[Symbol.toPrimitive](hint){trace.push(hint);return "rendered";}};
  Object.defineProperty(S.Bm25Ranker.prototype,"rank",{configurable:true,writable:true,value(){return [{name,score:1}];}});
  Object.defineProperty(String.prototype,"concat",{configurable:true,value(){throw Error("template used live concat");}});
  try {
    const api=searchApi([searchMetadata("ordinary","metadata")]);
    const result=await S.createToolSearchToolDefinition({tools:api}).execute("id",{query:"cat"});
    searchList(trace,["string"],"eager intrinsic name ToString");
    searchSame(result.content[0].text,"Loaded 1 tool. They are available from your next call:\n- rendered: ","actual nested template");
    searchSame(result.details.loaded[0],name,"names remain raw outside the template");
    let later=0; const reason={};
    const bad={[Symbol.toPrimitive](hint){searchSame(hint,"string","abrupt template hint");throw reason;}};
    S.Bm25Ranker.prototype.rank=()=>[{name:bad,score:1}];
    const failing=searchApi([searchMetadata("ordinary","metadata")]);
    const original=failing.setActiveTools;failing.setActiveTools=function(value){later++;return original.call(this,value);};
    let caught;try{await S.createToolSearchToolDefinition({tools:failing}).execute("id",{query:"cat"});}catch(value){caught=value;}
    searchSame(caught,reason,"template abrupt identity");searchSame(later,1,"activation precedes response template");
  } finally {Object.defineProperty(S.Bm25Ranker.prototype,"rank",rank);Object.defineProperty(String.prototype,"concat",concat);}
}
async function observeToolSearchDescriptionRetirement(S,H) {
  const rank=Object.getOwnPropertyDescriptor(S.Bm25Ranker.prototype,"rank");let phase=false;
  const metadata={name:"cat",exposure:"deferred",parameters:null,get description(){
    if(!phase)return "metadata";
    return {holder:H.make(0),get trim(){
      const fn=function(){return {holder:H.make(2),get split(){
        searchSame(H.count(1),1,"trim callee before split getter");
        const split=function(pattern){searchAssert(pattern instanceof RegExp&&pattern.source==="\\r?\\n","fresh line regexp");
          return {holder:H.make(4),get 0(){const value=H.make(5);value[Symbol.toPrimitive]=hint=>{
            searchSame(hint,"string","line template hint");searchSame(H.count(2),1,"split receiver retired before field conversion");
            searchSame(H.count(3),1,"split callee retired before field conversion");searchSame(H.count(4),1,"index receiver retired before field conversion");return "first";};return value;}};
        };split.holder=H.make(3);return split;
      }};};fn.holder=H.make(1);return fn;
    }};
  }};
  Object.defineProperty(S.Bm25Ranker.prototype,"rank",{configurable:true,writable:true,value(){phase=true;return [{name:"cat",score:1}];}});
  try {
    const result=await S.createToolSearchToolDefinition({tools:searchApi([metadata])}).execute("id",{query:"cat"});
    searchSame(result.content[0].text,"Loaded 1 tool. They are available from your next call:\n- cat: first","actual line rendering");
    searchSame(H.count(0),1,"description owner retires at actual AF terminal");searchSame(H.count(5),1,"converted line value retires");
  } finally {Object.defineProperty(S.Bm25Ranker.prototype,"rank",rank);}
}
function observeToolSearchExtension(S,H) {
  const trace=[], registrations=[];
  const pi={get registerTool(){
    trace.push("register:get");const fn=function(value){searchSame(this,pi,"actual extension receiver");registrations.push(value);return H.make(0);};fn.holder=H.make(1);return fn;
  }};
  searchSame(S.createToolSearchExtension()(pi),undefined,"extension returns actual void");
  searchList(trace,["register:get"],"one actual registration");searchSame(H.count(0),1,"register result retires before return");searchSame(H.count(1),1,"register callee retires before return");
  searchSame(registrations[0].defaultActive,false,"real final inactive field");
  searchSame(Object.keys(registrations[0]).at(-1),"defaultActive","spread precedes final own definition");
  searchAssert(toolSearchIsAsync(registrations[0].execute),"actual executor retained through spread");
  S.default(pi);searchSame(registrations.length,2,"one real default extension");
}
async function observeToolSearchPrivateData(S,H,kind) {
  let reason;
  if(kind==="token") {
    const caught=searchThrown(()=>S.tokenize({get replace(){reason=H.freshPrivateData();throw reason;}}));
    searchSame(caught,reason,"token getter DATA identity");
  } else if(kind==="schema") {
    const caught=searchThrown(()=>S.createToolSearchDocument({name:"x",description:"d",parameters:{get description(){reason=H.freshPrivateData();throw reason;}}}));
    searchSame(caught,reason,"recursive schema DATA identity");
  } else if(kind==="rank") {
    const docs={length:1,get map(){reason=H.freshPrivateData();throw reason;}};
    searchSame(searchThrown(()=>new S.Bm25Ranker().rank("cat",docs,1)),reason,"rank DATA identity");
  } else if(kind==="execute") {
    const execute=S.createToolSearchToolDefinition({get tools(){reason=H.freshPrivateData();throw reason;}}).execute;
    let caught;try{await execute("id",{query:"cat"});}catch(value){caught=value;}
    searchSame(caught,reason,"ordinary AF rejected DATA identity");
  } else {
    const extension=S.createToolSearchExtension();
    searchSame(searchThrown(()=>extension({get registerTool(){reason=H.freshPrivateData();throw reason;}})),reason,"extension DATA identity");
  }
  searchAssert(H.isUnmarkedPrivateData(reason),"successful native private DATA stays ordinary");
}
async function observeToolSearchCurrentFatal(S,H) {
  H.freshPrivateData();
  const execute=S.createToolSearchToolDefinition({get tools(){H.visit(2);return undefined;}}).execute;
  Object.defineProperty(globalThis,"Number",{configurable:true,get(){H.visit(1);return {};}});
  try {await execute("id",{query:{get trim(){return H.raiseNativeFatal();}},limit:1});H.record.guestReached=true;H.visit(3);}
  catch(reason){H.record.guestReached=true;H.visit(3);throw reason;}
}
async function observeToolSearchCalleeStop(S,H,cancel) {
  const execute=S.createToolSearchToolDefinition({get tools(){H.visit(2);return undefined;}}).execute;
  Object.defineProperty(globalThis,"Number",{configurable:true,get(){H.visit(1);return {};}});
  const query={get trim(){const fn=()=>"cat";fn.holder=H.make(0);return fn;}};
  if(cancel)H.armCancel(0);else H.armFatal(0);
  try {await execute("id",{query,limit:1});H.record.guestReached=true;H.visit(3);}
  catch(reason){H.record.guestReached=true;H.visit(3);throw reason;}
}
function observeToolSearchRankFatal(S,H) {
  H.freshPrivateData();
  const ranker=new S.Bm25Ranker();
  const docs={length:1,get map(){return H.raiseNativeFatal();},get forEach(){H.visit(1);return ()=>{};}};
  try {ranker.rank("cat",docs,1);H.record.guestReached=true;H.visit(3);}
  catch(reason){H.record.guestReached=true;H.visit(3);throw reason;}
}
async function observeToolSearchExplicitThrow(S,H,kind) {
  const execute=S.createToolSearchToolDefinition({get tools(){H.visit(1);return undefined;}}).execute;
  globalThis.Error=function(){return toolSearchExplicitReason;};
  try {await execute("id",{query:kind==="query"?"":"cat",limit:kind==="query"?1:0});H.record.guestReached=true;H.visit(3);}
  catch(reason){H.record.guestReached=true;H.visit(3);throw reason;}
}
