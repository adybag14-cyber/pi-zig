// Prepared original-only input; no candidate imports or custom implementation.
// A future separately granted pinned Node24 strip-types caller can collect this
// raw observation. This file is not an execution/controller/expected-data grant.
import { fetchWithRetry } from './authority/management-http.ts';
import { observeManagementHttp } from './observe-management-http.mjs';
export const observation = await observeManagementHttp(fetchWithRetry);
