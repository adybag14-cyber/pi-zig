// PREPARED ONLY. Genuine Pi1.3 installed source graph; separate Root admission.
import * as ai from '@earendil-works/pi-ai';
import * as compat from '@earendil-works/pi-ai/compat';
import * as operations from '@earendil-works/pi-ai/utils/model-operations';
import * as sdk from '@earendil-works/pi-coding-agent';
import {Agent} from '@earendil-works/pi-agent-core';
const rows=[];
let reason;try{operations.assertChatModel({type:'image',provider:'owned',id:'owned'})}catch(error){reason=error}
rows.push({id:'canonical-model-error',instance:reason instanceof ai.ModelsError,constructor:reason?.constructor===ai.ModelsError,name:reason?.name,code:reason?.code});
rows.push({id:'sdk-agent-session',type:typeof sdk.AgentSession,name:sdk.AgentSession.name,length:sdk.AgentSession.length,prototypeNames:Reflect.ownKeys(sdk.AgentSession.prototype).map(String),agentPrototypeNames:Reflect.ownKeys(Agent.prototype).map(String)});
rows.push({id:'factory-async-brand',name:sdk.createAgentSession.name,length:sdk.createAgentSession.length,async:Object.getPrototypeOf(sdk.createAgentSession)===Object.getPrototypeOf(async function(){})});
const before=compat.getApiProviders();
const marker={owned:true};
compat.registerApiProvider({api:'owned-sdk-composition',stream(){throw marker},streamSimple(){throw marker}},'owned-sdk-composition');
rows.push({id:'shared-registry-registration',visible:compat.getApiProviders().some(item=>item.api==='owned-sdk-composition'),baseline:before.map(item=>item.api)});
compat.resetApiProviders();
rows.push({id:'shared-registry-reset',removed:!compat.getApiProviders().some(item=>item.api==='owned-sdk-composition'),apis:compat.getApiProviders().map(item=>item.api)});
const context={systemPrompt:'owned',messages:[]};
rows.push({id:'actual-transcript-context',result:ai.normalizeContext(context)});
process.stdout.write(JSON.stringify({authority:'actual-Pi1.3-8efd-SDK-AI-imports',rows})+'\n');
