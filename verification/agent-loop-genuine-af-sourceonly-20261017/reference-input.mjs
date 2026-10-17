// PREPARED ONLY. Actual original exports, no candidate/default/host bridge.
import * as actual from '@earendil-works/pi-agent-core';
import {observeAgentLoop} from './observer.mjs';
process.stdout.write(JSON.stringify(await observeAgentLoop(actual))+'\n');
