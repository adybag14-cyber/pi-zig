// Exact selected Node24.13 async_hooks.js bodies; test-only original reference.
(function(async_wrap) {
'use strict';
const {async_hook_fields, async_id_fields, execution_async_resources} = async_wrap;
const {pushAsyncContext: pushAsyncContext_, popAsyncContext: popAsyncContext_, clearAsyncIdStack} = async_wrap;
const {kInit,kBefore,kAfter,kDestroy,kCheck,kExecutionAsyncId,kAsyncIdCounter,kTriggerAsyncId,kDefaultTriggerAsyncId,kStackLength} = async_wrap.constants;
function newAsyncId() {
  return ++async_id_fields[kAsyncIdCounter];
}

function getDefaultTriggerAsyncId() {
  const defaultTriggerAsyncId = async_id_fields[kDefaultTriggerAsyncId];
  // If defaultTriggerAsyncId isn't set, use the executionAsyncId
  if (defaultTriggerAsyncId < 0)
    return async_id_fields[kExecutionAsyncId];
  return defaultTriggerAsyncId;
}

function clearDefaultTriggerAsyncId() {
  async_id_fields[kDefaultTriggerAsyncId] = -1;
}

function hasHooks(key) {
  return async_hook_fields[key] > 0;
}

function enabledHooksExist() {
  return hasHooks(kCheck);
}

function initHooksExist() {
  return hasHooks(kInit);
}

function afterHooksExist() {
  return hasHooks(kAfter);
}

function destroyHooksExist() {
  return hasHooks(kDestroy);
}

function hasAsyncIdStack() {
  return hasHooks(kStackLength);
}

function pushAsyncContext(asyncId, triggerAsyncId, resource) {
  const offset = async_hook_fields[kStackLength];
  execution_async_resources[offset] = resource;
  if (offset * 2 >= async_wrap.async_ids_stack.length)
    return pushAsyncContext_(asyncId, triggerAsyncId);
  async_wrap.async_ids_stack[offset * 2] = async_id_fields[kExecutionAsyncId];
  async_wrap.async_ids_stack[offset * 2 + 1] = async_id_fields[kTriggerAsyncId];
  async_hook_fields[kStackLength]++;
  async_id_fields[kExecutionAsyncId] = asyncId;
  async_id_fields[kTriggerAsyncId] = triggerAsyncId;
}

function popAsyncContext(asyncId) {
  const stackLength = async_hook_fields[kStackLength];
  if (stackLength === 0) return false;

  if (enabledHooksExist() && async_id_fields[kExecutionAsyncId] !== asyncId) {
    // Do the same thing as the native code (i.e. crash hard).
    return popAsyncContext_(asyncId);
  }

  const offset = stackLength - 1;
  async_id_fields[kExecutionAsyncId] = async_wrap.async_ids_stack[2 * offset];
  async_id_fields[kTriggerAsyncId] = async_wrap.async_ids_stack[2 * offset + 1];
  execution_async_resources.pop();
  async_hook_fields[kStackLength] = offset;
  return offset > 0;
}

function executionAsyncId() {
  return async_id_fields[kExecutionAsyncId];
}

function triggerAsyncId() {
  return async_id_fields[kTriggerAsyncId];
}
return {newAsyncId,getDefaultTriggerAsyncId,clearDefaultTriggerAsyncId,enabledHooksExist,initHooksExist,afterHooksExist,destroyHooksExist,hasAsyncIdStack,pushAsyncContext,popAsyncContext,executionAsyncId,triggerAsyncId,clearAsyncIdStack};
})
