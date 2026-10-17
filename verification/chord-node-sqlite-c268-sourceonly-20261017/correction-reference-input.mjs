import * as api from './reference-source/node.ts';
import * as sqlite from 'node:sqlite';
import {observeCorrections} from './correction-observer.mjs';
export const observeOriginalCorrections=()=>observeCorrections(api,sqlite,()=>new Error('owned rejected data'));
