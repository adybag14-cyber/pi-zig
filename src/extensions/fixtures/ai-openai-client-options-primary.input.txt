// Controlled caller/observer only. Every environment/key/header/log value here
// is owned dummy data. No host process.env value is read or reported.
export function observeClientOptionCases(create,merge){
 const rows=[],target=globalThis;
 const originals=Object.fromEntries(['process','console','fetch','Deno'].map(key=>[key,Object.getOwnPropertyDescriptor(target,key)]));
 const arrayOriginal=Object.getOwnPropertyDescriptor(Array,'isArray');
 const configs=[
  {name:'owned dummy env defaults'},
  {name:'env whitespace trimmed',env:{OPENAI_ORG_ID:'  fixture-org  ',OPENAI_PROJECT_ID:'\tfixture-project\t'}},
  {name:'undefined and null env',env:{OPENAI_ADMIN_KEY:undefined,OPENAI_ORG_ID:null,OPENAI_PROJECT_ID:undefined}},
  {name:'null process env',nullEnv:true},
  {name:'undefined baseURL uses env',baseURL:undefined},
  {name:'null baseURL uses fixed default',baseURL:null},
  {name:'undefined apiKey uses env',apiKey:undefined},
  {name:'null apiKey keeps admin ctor credential',apiKey:null},
  {name:'missing credentials before body defaults',apiKey:null,env:{OPENAI_ADMIN_KEY:null,OPENAI_API_KEY:null}},
  {name:'custom headers and provider precedence',env:{OPENAI_CUSTOM_HEADERS:'X-Env: fixture-env\nX-Case: fixture-env'},headers:{'X-Case':'fixture-option'}},
  {name:'undefined header preserves custom env',env:{OPENAI_CUSTOM_HEADERS:'X-Env: fixture-env'},headers:{'X-Env':undefined}},
  {name:'null header keeps nullable tombstone',env:{OPENAI_CUSTOM_HEADERS:'Authorization: fixture-env-auth'},headers:{Authorization:null}},
  {name:'default value coerces after payload boundary'},
  {name:'custom env coerces before payload boundary',env:{OPENAI_CUSTOM_HEADERS:'X-Env: fixture-env'}},
  {name:'malformed custom header name',env:{OPENAI_CUSTOM_HEADERS:'bad name: fixture-value'}},
  {name:'malformed custom header value',env:{OPENAI_CUSTOM_HEADERS:'X-Env: fixture\rvalue'}},
  {name:'raw organization env getter',throwEnv:'OPENAI_ORG_ID'},
  {name:'raw project trim getter',throwTrim:'OPENAI_PROJECT_ID'},
  {name:'raw custom env getter',throwEnv:'OPENAI_CUSTOM_HEADERS'},
  {name:'raw header value before payload',env:{OPENAI_CUSTOM_HEADERS:'X-Env: fixture-env'},throwHeader:true},
  {name:'raw header value after payload',throwHeader:true},
  {name:'explicit fetch precedes default getter',throwFetch:true},
  {name:'null fetch reads global default twice',fetch:null},
  {name:'global fetch raw getter before custom env',fetch:undefined,throwFetch:true},
  {name:'invalid log level uses owned logger',env:{OPENAI_LOG:'fixture-invalid-log'}},
  {name:'off log level captured',env:{OPENAI_LOG:'off'}},
  {name:'Deno env optional fallback',deno:true},
  {name:'nonstring env fails trim',env:{OPENAI_ORG_ID:123}},
  {name:'custom duplicate casing and proto assignment',env:{OPENAI_CUSTOM_HEADERS:'__proto__: fixture-text\nX-Env: first\nx-env: last\nignored line'}},
  {name:'live Array.isArray getter during custom merge',env:{OPENAI_CUSTOM_HEADERS:'X-Env: fixture-env'},arrayGetter:true},
  {name:'null process throws before ctor body',nullProcess:true},
  {name:'truthy nonstring key commits null after validation',apiKey:{fixture:'owned-key'},env:{OPENAI_ADMIN_KEY:null}}
 ];
 const own=(value,key)=>Object.prototype.hasOwnProperty.call(value,key);
 try{for(const config of configs){
  const trace=[],raw=new Error('fixture raw constructor failure');let phase='constructor',payload=false;
  Object.defineProperty(Array,'isArray',arrayOriginal);
  if(config.arrayGetter)Object.defineProperty(Array,'isArray',{configurable:true,get(){trace.push('Array.isArray getter');return function(value){trace.push('Array.isArray call');return arrayOriginal.value(value)}}});
  const values={OPENAI_BASE_URL:'http://127.0.0.1:1/fixture-env',OPENAI_API_KEY:'fixture-env-key',OPENAI_ADMIN_KEY:'fixture-admin-key',OPENAI_ORG_ID:'fixture-org',OPENAI_PROJECT_ID:'fixture-project',OPENAI_WEBHOOK_SECRET:'fixture-webhook',OPENAI_LOG:'',OPENAI_CUSTOM_HEADERS:'',...config.env};
  const env=new Proxy(values,{get(object,key){trace.push(['env',String(key)]);if(key===config.throwEnv)throw raw;if(key===config.throwTrim)return {get trim(){trace.push(['trim getter',String(key)]);throw raw}};return object[key]}});
  const process={get env(){trace.push('process.env');return config.nullEnv?null:env}};
  Object.defineProperty(target,'process',{configurable:true,get(){trace.push('process');return config.nullProcess?null:config.deno?undefined:process}});
  Object.defineProperty(target,'Deno',{configurable:true,value:config.deno?{env:{get(name){trace.push(['Deno.env.get',name]);return values[name]}}}:undefined});
  const logger={error(...args){trace.push(['logger.error',...args])},warn(...args){trace.push(['logger.warn',...args])},info(...args){trace.push(['logger.info',...args])},debug(...args){trace.push(['logger.debug',...args])}};
  Object.defineProperty(target,'console',{configurable:true,get(){trace.push('console');return logger}});
  const defaultFetch=function fixtureDefaultFetch(){throw Error('fixture transport must not execute')};
  Object.defineProperty(target,'fetch',{configurable:true,get(){trace.push('global fetch');if(config.throwFetch)throw raw;return defaultFetch}});
  const explicitFetch=function fixtureExplicitFetch(){throw Error('fixture transport must not execute')};
  const headerValue={toString(){trace.push(['header coercion',phase]);if(config.throwHeader)throw raw;return 'fixture-value-'+phase}};
  const provided={apiKey:own(config,'apiKey')?config.apiKey:'fixture-provided-key',baseURL:own(config,'baseURL')?config.baseURL:'http://127.0.0.1:1/fixture-provided',fetch:own(config,'fetch')?config.fetch:explicitFetch,defaultHeaders:{'User-Agent':'fixture-owned-agent','X-Value':headerValue,...config.headers}};
  try{
   const client=create(provided);
   payload=true;phase='payload';values.OPENAI_ORG_ID='fixture-mutated-org';values.OPENAI_CUSTOM_HEADERS='X-Env: fixture-mutated';
   const built=client.headersPrepared?{values:client.defaultHeaders,nulls:client.headerNulls}:merge([client.defaultHeaders]);
   rows.push({name:config.name,payload,baseURL:client.baseURL,apiKey:client.apiKey,adminAPIKey:client.adminAPIKey,organization:client.organization,project:client.project,webhookSecret:client.webhookSecret,logLevel:client.logLevel,fetchIdentity:client.fetch===explicitFetch?'provided':client.fetch===defaultFetch?'global':'other',loggerIdentity:client.logger===logger,headersPrepared:client.headersPrepared,headers:[...built.values.entries()],nulls:[...built.nulls],trace});
  }catch(error){rows.push({name:config.name,payload,error:{name:error?.name,message:error?.message,rawSame:error===raw},trace})}
 }}finally{Object.defineProperty(Array,'isArray',arrayOriginal);for(const key of Object.keys(originals)){if(originals[key])Object.defineProperty(target,key,originals[key]);else delete target[key]}}
 return rows;
}
