// Guest caller controls for the pinned SDK's real internal/headers export.
// No provider, transport, runtime identity or expected result is implemented.
export function observeHeaderCases(build){
 const rows=[];const record=(name,sources)=>{try{const result=build(sources);rows.push({name,headers:[...result.values.entries()],nulls:[...result.nulls]})}catch(error){rows.push({name,error:{name:error.name,message:error.message}})}};
 record('undefined preserves earlier default',[{Accept:'application/json',Authorization:'Bearer placeholder'},{accept:undefined,authorization:undefined}]);
 record('null removes earlier default',[{Accept:'application/json',Authorization:'Bearer placeholder'},{accept:null,authorization:null}]);
 record('case distinct object keys overwrite',[{'X-Test':'base'},{'X-Test':'first','x-test':'last'}]);
 record('tuple repeated name appends',[{'X-Test':'base'},[['X-Test','first'],['x-test','last']]]);
 record('record array undefined null and values',[{'X-Test':'base'},{'X-Test':[undefined,'first',null,undefined,'last']}]);
 record('empty and undefined arrays preserve default',[{'X-Test':'base'},{'X-Test':[],'x-test':[undefined]}]);
 record('header value trims HTTP whitespace',[{'X-Test':' \tvalue\t '}]);
 record('JSON body header follows defaults',[{'Content-Type':'application/json'},{'content-type':'application/x-custom'},{'content-type':'application/json'}]);
 record('request header follows JSON body',[{'Content-Type':'application/json'},{'content-type':'application/x-custom'},{'content-type':'application/json'},{'content-type':'request-level'}]);
 record('retry and timeout caller precedence',[{'X-Stainless-Retry-Count':'0','X-Stainless-Timeout':'3'},{'x-stainless-retry-count':'caller','x-stainless-timeout':null}]);
 record('client default spread preserves case key order',[{'User-Agent':'sdk-default'},{'User-Agent':'pi-default',...{'user-agent':'model-lower'},...{'User-Agent':'option-upper'}}]);
 record('explicit identity headers stay caller owned',[{'User-Agent':'native-default'},{'user-agent':'caller-owned','x-stainless-lang':'caller-language','x-stainless-package-version':'caller-package','x-stainless-os':'caller-os','x-stainless-arch':'caller-arch','x-stainless-runtime':'caller-runtime','x-stainless-runtime-version':'caller-version'}]);
 record('real Headers source appends normalized entries',[{'X-Test':'base'},new Headers([['X-Test','first'],['x-test','last']])]);
 record('invalid header name',[{'bad name':'value'}]);
 record('invalid header value',[{'X-Test':'line\nvalue'}]);
 record('tuple nonstring header name',[[[1,'value']]]);
 const raw={raw:true},trace=[];const headers={get 'X-Test'(){trace.push('value getter');throw raw}};try{build([{Accept:'base'},headers]);rows.push({name:'raw record getter identity',unexpectedReturn:true})}catch(error){rows.push({name:'raw record getter identity',same:error===raw,trace:[...trace]})}
 const value={toString(){trace.push('toString');return ' first '}};trace.length=0;const result=build([{'X-Test':value}]);rows.push({name:'live value coercion',headers:[...result.values.entries()],trace:[...trace]});
 return rows;
}
