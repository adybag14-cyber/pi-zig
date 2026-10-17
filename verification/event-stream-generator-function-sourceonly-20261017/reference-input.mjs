// Prepared only. Separate original-capture grant required.
import {EventStream} from '@earendil-works/pi-ai';
import {observeEventStreamFactory} from './observer.mjs';
process.stdout.write(JSON.stringify(await observeEventStreamFactory(EventStream))+'\n');
