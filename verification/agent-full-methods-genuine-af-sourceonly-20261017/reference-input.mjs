// PREPARED ONLY. Imports the actual original Agent, never a candidate backend.
import {Agent} from '@earendil-works/pi-agent-core';
import {observeAgentFullMethods} from './observer.mjs';
process.stdout.write(JSON.stringify(await observeAgentFullMethods(Agent))+'\n');
