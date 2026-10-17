// PREPARED ONLY: actual original package, no candidate or replacement Agent.
import {Agent} from '@earendil-works/pi-agent-core';
import {observeAgentRouting} from './observer.mjs';
process.stdout.write(JSON.stringify(await observeAgentRouting(Agent))+'\n');
