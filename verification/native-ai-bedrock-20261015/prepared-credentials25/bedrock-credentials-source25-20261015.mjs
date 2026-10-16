// Genuine credential-provider/Bedrock Source probes. Only owned fixture files
// and loopback HTTP are permitted. Stimuli are fake; results/errors are observed.
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash, createPrivateKey, createPublicKey, verify } from 'node:crypto';
const [outputPath,inputPath,workspaceRoot]=process.argv.slice(2);
const spec=JSON.parse(fs.readFileSync(inputPath,'utf8'));
const root=join(workspaceRoot,`bedrock-auth-${process.pid}`);
fs.mkdirSync(root,{recursive:true});
const fixedNow=Date.parse(spec.fixedNow);
Date.now=()=>fixedNow;
const awsNames=['AWS_PROFILE','AWS_DEFAULT_PROFILE','AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_SESSION_TOKEN','AWS_BEARER_TOKEN_BEDROCK','AWS_AUTH_SCHEME_PREFERENCE','AWS_WEB_IDENTITY_TOKEN_FILE','AWS_ROLE_ARN','AWS_ROLE_SESSION_NAME','AWS_CONTAINER_CREDENTIALS_RELATIVE_URI','AWS_CONTAINER_CREDENTIALS_FULL_URI','AWS_CONTAINER_AUTHORIZATION_TOKEN','AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE','AWS_ENDPOINT_URL_STS','AWS_ENDPOINT_URL_SSO','AWS_ENDPOINT_URL_SSO_OIDC','AWS_ENDPOINT_URL_SIGNIN'];
for(const name of awsNames)delete process.env[name];
process.env.HOME=root;process.env.USERPROFILE=root;
process.env.AWS_CONFIG_FILE=join(root,'empty-config');process.env.AWS_SHARED_CREDENTIALS_FILE=join(root,'empty-credentials');
fs.writeFileSync(process.env.AWS_CONFIG_FILE,'');fs.writeFileSync(process.env.AWS_SHARED_CREDENTIALS_FILE,'');
process.env.AWS_EC2_METADATA_DISABLED='true';process.env.AWS_MAX_ATTEMPTS='1';
const blocked=[];
for(const module of [http,https]){
 const original=module.request;
 module.request=function(...args){const first=args[0];const host=typeof first==='string'||first instanceof URL?new URL(first).hostname:first?.hostname??first?.host??'';if(!['127.0.0.1','localhost','[::1]','::1'].includes(String(host).split(':')[0])){blocked.push(String(host));throw new Error('Fixture blocked non-loopback HTTP destination')}return original.apply(this,args)};
}
const runtime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/';
const ini=await import(pathToFileURL(runtime+'@aws-sdk/credential-provider-ini/dist-cjs/index.js').href);
const nodeCredentials=await import(pathToFileURL(runtime+'@aws-sdk/credential-provider-node/dist-cjs/index.js').href);
const tokens=await import(pathToFileURL(runtime+'@aws-sdk/token-providers/dist-cjs/index.js').href);
const sdk=await import(pathToFileURL(runtime+'@aws-sdk/client-bedrock-runtime/dist-cjs/index.js').href);
const source=await import('file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/api/bedrock-converse-stream.ts');
const originalSend=sdk.BedrockRuntimeClient.prototype.send;
const normalize=value=>JSON.parse(JSON.stringify(value,(key,item)=>['timestamp','durationMs'].includes(key)?0:item instanceof Uint8Array?Array.from(item):item));
const errorValue=error=>({name:error?.name,message:error?.message,tryNextLink:error?.tryNextLink,code:error?.code});
const credentialValue=value=>({accessKeyId:value.accessKeyId,secretAccessKey:value.secretAccessKey,sessionToken:value.sessionToken,expiration:value.expiration?.toISOString(),accountId:value.accountId,credentialScope:value.credentialScope});
const hash=(algorithm,value)=>createHash(algorithm).update(value).digest('hex');
const tokenPath=(home,id)=>join(home,'.aws','sso','cache',hash('sha1',id)+'.json');
const write=(path,value)=>{fs.mkdirSync(join(path,'..'),{recursive:true});fs.writeFileSync(path,typeof value==='string'?value:JSON.stringify(value,null,2))};
const ownedFiles=directory=>fs.existsSync(directory)?fs.readdirSync(directory,{withFileTypes:true}).flatMap(entry=>{const path=join(directory,entry.name);return entry.isDirectory()?ownedFiles(path):[{path,contents:fs.readFileSync(path,'utf8')}]}):[];
const iso=offset=>new Date(fixedNow+offset).toISOString();
const roleCredentials={accessKeyId:'FAKE_SSO_ACCESS',secretAccessKey:'fake-sso-secret',sessionToken:'fake-sso-session',expiration:fixedNow+3600000,accountId:'123456789012'};
const rows=[];
for(const test of spec.cases){
 for(const name of awsNames)delete process.env[name];
 const home=join(root,test.name);fs.mkdirSync(home,{recursive:true});
 process.env.HOME=home;process.env.USERPROFILE=home;
 const config=join(home,'config'),credentials=join(home,'credentials');
 process.env.AWS_CONFIG_FILE=config;process.env.AWS_SHARED_CREDENTIALS_FILE=credentials;
 process.env.AWS_LOGIN_CACHE_DIRECTORY=join(home,'login-cache');
 const profile='fixture',session='session-'+test.name,start='https://fixture.awsapps.invalid/start/'+test.name;
 const requests=[];let resolved,commandInput;
 const server=http.createServer(async(req,res)=>{const parts=[];for await(const part of req)parts.push(part);const text=Buffer.concat(parts).toString('utf8');const headers=Object.fromEntries(Object.entries(req.headers).filter(([key])=>['authorization','x-amz-sso_bearer_token','dpop','content-type','x-amz-date','x-amz-content-sha256','x-amz-security-token','host'].includes(key)));const record={method:req.method,url:`http://${req.headers.host}${req.url}`,path:req.url,headers,body:text?JSON.parse(text):null};
  if(headers.dpop){const [h,p,s]=headers.dpop.split('.');const header=JSON.parse(Buffer.from(h,'base64url')),payload=JSON.parse(Buffer.from(p,'base64url'));record.dpop={header,payload,signatureValid:verify('sha256',Buffer.from(`${h}.${p}`),{key:createPublicKey(createPrivateKey(spec.fakeDpopPem)),dsaEncoding:'ieee-p1363'},Buffer.from(s,'base64url'))}}
  requests.push(record);res.setHeader('content-type','application/json');res.setHeader('x-amzn-requestid','fixture-auth-request');
  if(req.url.startsWith('/federation/credentials')){res.end(JSON.stringify({roleCredentials}));return}
  if(req.url==='/token'){if(test.kind==='sso_refresh_fallback'){res.statusCode=400;res.end(JSON.stringify({error:'invalid_grant',message:'fixture refresh rejected'}))}else res.end(JSON.stringify({accessToken:'fake-sso-refreshed',refreshToken:'fake-refresh-2',expiresIn:3600,tokenType:'Bearer'}));return}
  if(req.url.includes('token')){if(test.kind==='login_refresh_denied'){res.statusCode=403;res.end(JSON.stringify({__type:'AccessDeniedException',error:'TOKEN_EXPIRED',message:'fixture denied'}))}else res.end(JSON.stringify({accessToken:{accessKeyId:'FAKE_LOGIN_REFRESH_ACCESS',secretAccessKey:'fake-login-refresh-secret',sessionToken:'fake-login-refresh-session'},refreshToken:'fake-login-refresh-2',expiresIn:3600}));return}
  // Actual Bedrock client path, including absent-vs-empty bearer selection.
  const events=[{messageStart:{role:'assistant'}},{messageStop:{stopReason:'end_turn'}}];
  const crc=bytes=>{let n=0xffffffff;for(const byte of bytes){n^=byte;for(let i=0;i<8;i++)n=(n>>>1)^((n&1)?0xedb88320:0)}return(n^0xffffffff)>>>0};
  const h=(name,value)=>{const a=Buffer.from(name),b=Buffer.from(value),n=Buffer.alloc(2);n.writeUInt16BE(b.length);return Buffer.concat([Buffer.from([a.length]),a,Buffer.from([7]),n,b])};
  const frames=events.map(event=>{const [name,payload]=Object.entries(event)[0],headers=Buffer.concat([h(':message-type','event'),h(':event-type',name),h(':content-type','application/json')]),data=Buffer.from(JSON.stringify(payload)),pre=Buffer.alloc(12);pre.writeUInt32BE(16+headers.length+data.length);pre.writeUInt32BE(headers.length,4);pre.writeUInt32BE(crc(pre.subarray(0,8)),8);const body=Buffer.concat([pre,headers,data]),tail=Buffer.alloc(4);tail.writeUInt32BE(crc(body));return Buffer.concat([body,tail])});res.setHeader('content-type','application/vnd.amazon.eventstream');res.end(Buffer.concat(frames));
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const endpoint=`http://127.0.0.1:${server.address().port}`;
 process.env.AWS_ENDPOINT_URL_SSO=endpoint;process.env.AWS_ENDPOINT_URL_SSO_OIDC=endpoint;process.env.AWS_ENDPOINT_URL_SIGNIN=endpoint;
 let configText='[profile fixture]\nregion=eu-west-2\n',credentialText='';
 if(test.kind.startsWith('sso')){
  configText+='sso_account_id=123456789012\nsso_role_name=FixtureRole\n';
  const modern=test.kind.includes('session')||test.kind.includes('refresh');
  if(modern){configText+=`sso_session=${session}\n`;if(test.kind!=='sso_session_missing')configText+=`[sso-session ${session}]\nsso_start_url=${start}\nsso_region=eu-west-2\n`}
  else configText+=`sso_start_url=${start}\nsso_region=eu-west-2\n`;
  if(test.kind==='sso_invalid_config')configText='[profile fixture]\nsso_account_id=123456789012\n';
  const token={accessToken:'fake-sso-access',expiresAt:iso(test.kind==='sso_legacy_expired'?-1000:test.kind.includes('refresh')?180000:3600000)};
  if(test.kind.includes('refresh'))Object.assign(token,{clientId:'fake-client',clientSecret:'fake-client-secret',refreshToken:'fake-refresh'});
  write(tokenPath(home,modern?session:start),test.kind==='sso_cache_badjson'?'{bad':token);
 }else if(test.kind.startsWith('login')){
  configText+=`login_session=${session}\n`;
  const token={accessToken:{accessKeyId:'FAKE_LOGIN_ACCESS',secretAccessKey:'fake-login-secret',sessionToken:'fake-login-session',accountId:'123456789012',expiresAt:iso(test.kind.includes('refresh')?test.kind==='login_refresh_denied'?-1000:180000:3600000)},clientId:'fake-client',refreshToken:'fake-login-refresh',dpopKey:spec.fakeDpopPem};
  if(test.kind==='login_missing_fields')delete token.refreshToken;
  write(join(process.env.AWS_LOGIN_CACHE_DIRECTORY,hash('sha256',session)+'.json'),token);
 }else if(test.kind.startsWith('process')){
  const processInput=join(home,'process-output.json'),processScript=join(home,'process-fixture.mjs');
  write(processScript,"import{readFileSync}from'node:fs';const value=JSON.parse(readFileSync(process.argv[2],'utf8'));process.stdout.write(value.raw??JSON.stringify(value.output));\n");
  write(processInput,test.kind==='process_invalid_json'?{raw:'{bad'}:{output:{Version:test.kind==='process_version_invalid'?2:1,AccessKeyId:'FAKE_PROCESS_ACCESS',SecretAccessKey:'fake-process-secret',SessionToken:'fake-process-session',Expiration:iso(test.kind==='process_expired'?-1000:3600000)}});
  configText+=`credential_process="${process.execPath}" "${processScript}" "${processInput}"\n`;
 }else if(test.kind==='profile_static'||test.kind.startsWith('facade'))credentialText='[fixture]\naws_access_key_id=FAKE_PROFILE_ACCESS\naws_secret_access_key=fake-profile-secret\naws_session_token=fake-profile-session\n';
 write(config,configText);write(credentials,credentialText);
 const beforeFiles={config:configText,credentials:credentialText};
 const beforeOwnedFiles=ownedFiles(home);
 const init={profile,filepath:credentials,configFilepath:config,ignoreCache:true,clientConfig:{endpoint,region:'eu-west-2',maxAttempts:1}};
 const callerClientConfig={profile,region:async()=>'eu-west-2'};
 let result,error,events;
 try{
  if(test.kind.startsWith('facade')){
   const options={region:'eu-west-2',env:{AWS_BEDROCK_FORCE_HTTP1:'1',AWS_EC2_METADATA_DISABLED:'true'}};
   if(test.kind==='facade_explicit_profile')options.profile=profile;
   if(test.kind==='facade_scoped_profile')options.env.AWS_PROFILE=profile;
   if(test.kind==='facade_ambient_profile_static_override'){process.env.AWS_PROFILE=profile;Object.assign(options.env,{AWS_ACCESS_KEY_ID:'FAKE_SCOPED_ACCESS',AWS_SECRET_ACCESS_KEY:'fake-scoped-secret'})}
   if(test.kind==='facade_explicit_profile'||test.kind==='facade_scoped_profile')Object.assign(options.env,{AWS_ACCESS_KEY_ID:'FAKE_SCOPED_ACCESS',AWS_SECRET_ACCESS_KEY:'fake-scoped-secret'});
   if(test.kind==='facade_empty_bearer_env')process.env.AWS_BEARER_TOKEN_BEDROCK='';
   if(test.kind==='facade_absent_bearer_sigv4')options.profile=profile;
   const actualWire=test.kind==='facade_empty_bearer_env'||test.kind==='facade_absent_bearer_sigv4';
   sdk.BedrockRuntimeClient.prototype.send=actualWire?originalSend:async function(command){commandInput=normalize(command.input);resolved=credentialValue(await this.config.credentials());return{$metadata:{requestId:'fixture-auth-request',httpStatusCode:200},stream:(async function*(){yield{messageStart:{role:'assistant'}};yield{messageStop:{stopReason:'end_turn'}}})()}};
   const model={id:'anthropic.claude-sonnet-4-6',name:'Claude Sonnet 4.6',api:'bedrock-converse-stream',provider:'amazon-bedrock',baseUrl:endpoint,reasoning:true,input:['text'],contextWindow:200000,maxTokens:8192,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}};
   const output=source.stream(model,{messages:[{role:'user',content:'auth fixture',timestamp:0}]},options);events=[];for await(const event of output)events.push(normalize(event));result=normalize(await output.result());
  }else if(test.kind==='token_env_empty'||test.kind==='token_env_absent'){
   if(test.kind==='token_env_empty')process.env.AWS_BEARER_TOKEN_BEDROCK='';result=normalize(await tokens.fromEnvSigningName({signingName:'bedrock'})());
  }else if(test.kind==='default_missing')result=credentialValue(await nodeCredentials.defaultProvider(init)({callerClientConfig}));
  else result=credentialValue(await ini.fromIni(init)({callerClientConfig}));
 }catch(failure){error=errorValue(failure)}finally{sdk.BedrockRuntimeClient.prototype.send=originalSend;server.closeAllConnections();await new Promise(resolve=>server.close(resolve))}
 const cacheFiles=[];for(const directory of [join(home,'.aws','sso','cache'),process.env.AWS_LOGIN_CACHE_DIRECTORY])if(fs.existsSync(directory))for(const file of fs.readdirSync(directory))cacheFiles.push({path:join(directory,file),contents:fs.readFileSync(join(directory,file),'utf8')});
 rows.push({name:test.name,kind:test.kind,now:fixedNow,home,endpoint,beforeFiles,beforeOwnedFiles,requests,commandInput,resolved,result,error,events,cacheFiles});
}
if(blocked.length)throw new Error('Non-loopback HTTP attempted by fixture');
fs.writeFileSync(outputPath,JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',actualNode:{version:process.version,executable:process.execPath},cases:rows.length,blocked,workspace:root,rows},null,2)+'\n');
