// Actual c268 bodies with TypeScript-only syntax erased. Raw authority blobs
// accompany this fixture. No extension runner or tool execution is fabricated.
(function () {
  "use strict";
  function defineTool(tool) { return tool; }
  function isBashToolResult(e) { return e.toolName === "bash"; }
  function isPowerShellToolResult(e) { return e.toolName === "powershell"; }
  function isReadToolResult(e) { return e.toolName === "read"; }
  function isEditToolResult(e) { return e.toolName === "edit"; }
  function isWriteToolResult(e) { return e.toolName === "write"; }
  function isGrepToolResult(e) { return e.toolName === "grep"; }
  function isFindToolResult(e) { return e.toolName === "find"; }
  function isLsToolResult(e) { return e.toolName === "ls"; }
  function isToolCallEventType(toolName, event) { return event.toolName === toolName; }
  function wrapToolDefinition(definition, ctxFactory) {
    return {
      name: definition.name,
      label: definition.label,
      description: definition.description,
      parameters: definition.parameters,
      outputSchema: definition.outputSchema,
      constrainedSampling: definition.constrainedSampling,
      prepareArguments: definition.prepareArguments,
      executionMode: definition.executionMode,
      execute: (toolCallId, params, signal, onUpdate, ctx) =>
        definition.execute(toolCallId, params, signal, onUpdate, ctx ?? (ctxFactory?.(toolCallId, signal))),
    };
  }
  function wrapRegisteredTool(registeredTool, runner) {
    return wrapToolDefinition(registeredTool.definition, (toolCallId, signal) =>
      runner.createToolContext(toolCallId, signal));
  }
  function wrapRegisteredTools(registeredTools, runner) {
    return registeredTools.map((tool) => wrapRegisteredTool(tool, runner));
  }
  return {
    defineTool, isBashToolResult, isPowerShellToolResult, isReadToolResult,
    isEditToolResult, isWriteToolResult, isGrepToolResult, isFindToolResult,
    isLsToolResult, isToolCallEventType, wrapRegisteredTool, wrapRegisteredTools,
  };
})()
