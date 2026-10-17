// Genuine original-reference caller only; supply actual Pi8efd constructors.
// No replacement Agent/SDK body or native flags/private tags are implemented.
export async function observeAwaitRejectionData(Agent, AgentSession) {
  if (typeof Agent !== "function" || typeof AgentSession !== "function") throw new TypeError("actual original constructors required");
  const reasons = [["object", () => ({ owned: "reason" })], ["Error", () => new Error("owned ordinary reason")], ["string", () => "owned string"], ["undefined", () => undefined]];
  const rows = [];
  for (const [kind, makeReason] of reasons) {
    const reason = makeReason(), calls = [];
    const receiver = {
      _state: {},
      handleRunFailure(actual, aborted) { calls.push(["catch", Object.is(actual, reason), aborted]); },
      finishRun() { calls.push(["finally"]); },
    };
    const value = await Agent.prototype.runWithLifecycle.call(receiver, () => Promise.reject(reason));
    rows.push(["runWithLifecycle", kind, value === undefined, calls]);
  }
  for (const method of ["prompt", "continue", "abort", "waitForIdle"]) {
    for (const [kind, makeReason] of reasons) {
      const reason = makeReason(), calls = [], rejected = () => Promise.reject(reason);
      const receiver = {
        _state: { messages: [{ role: "user" }] },
        normalizePromptInput() { calls.push("normalize"); return []; },
        runPromptMessages() { calls.push("runPromptMessages"); return rejected(); },
        runContinuation() { calls.push("runContinuation"); return rejected(); },
        isIdle: false,
        _getIdleWaitPromise() { calls.push("idle"); return rejected(); },
        abortRetry() { calls.push("abortRetry"); },
        abortCompaction() { calls.push("abortCompaction"); },
        abortBranchSummary() { calls.push("abortBranchSummary"); },
        agent: { abort() { calls.push("agent.abort"); } },
        waitForIdle() { calls.push("waitForIdle"); return rejected(); },
      };
      const prototype = method === "prompt" || method === "continue" ? Agent.prototype : AgentSession.prototype;
      let caught = false, same = false;
      try { await prototype[method].call(receiver); }
      catch (actual) { caught = true; same = Object.is(actual, reason); }
      rows.push([method, kind, caught, same, calls]);
    }
  }
  return { authority: "actual-Pi1.3-8efd-Await-ordinary-data", rows };
}
