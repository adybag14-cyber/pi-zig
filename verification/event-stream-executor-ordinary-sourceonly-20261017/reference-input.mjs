// Prepared only. Imports original Source; no candidate/default/host bridge.
import {EventStream} from '@earendil-works/pi-ai';
import {observeWaitingExecutorReturn} from './observer.mjs';
process.stdout.write(JSON.stringify(await observeWaitingExecutorReturn(EventStream))+'\n');
