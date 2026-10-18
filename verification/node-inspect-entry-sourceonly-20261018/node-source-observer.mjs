// Authored Source capture entrypoint. No capture has been run by this unit.
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { inspect } from "node:util";
import { runInThisContext } from "node:vm";

if (process.version !== "v24.13.0") throw new Error("The pinned Source Node v24.13.0 is required");
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const authority = readFileSync(new URL("./authority/inspect.js", import.meta.url));
if (digest(authority) !== "380aa09fae68e3279d0fb2469a24d75931a8098c84354347bf7130a38852b597")
    throw new Error("Source inspector authority bytes changed");
const observer = readFileSync(new URL("../../src/extensions/fixtures/native-node-inspect-observer.mjs", import.meta.url), "utf8");
const body = "(function(inspect){\"use strict\";\n" + observer +
    "\nconst controls = [" + "observeInspectShape,observeInspectPrimitives,observeInspectNumeric,observeInspectCapturedPrimordials,observeInspectCustomArguments,observeInspectOrdinaryCustomThrow,observeInspectTagCatch,observeInspectInstanceCatch,observeInspectProxyDetails,observeInspectDefaultAssignment" + "];" +
    "\nreturn controls.map(function(control){control(inspect);return {name:control.name,passed:true};});\n})";
const observe = runInThisContext(body, {filename:"actual-node-inspect-source-observer.js"});
const results = observe(inspect);
process.stdout.write(JSON.stringify({node:process.version,authoritySha256:digest(authority),observerSha256:digest(observer),declared:10,results},null,2)+"\n");
