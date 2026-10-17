import * as api from './reference-source/node.ts';
import * as sqlite from 'node:sqlite';
import {observeNodeSqlite} from './observer.mjs';
// The future owner supplies a fresh contained database path explicitly.
export const observeOriginal = ownedFile => observeNodeSqlite(api, sqlite, ownedFile);
