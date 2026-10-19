// Authored pinned-Node capture entrypoint. Run exactly one control per fresh
// Node process so the original module's lazy circular-error cell starts empty.
// This source unit does not authorize or claim execution of this entrypoint.
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { format, inspect } from "node:util";
import { runInThisContext } from "node:vm";

if (process.version !== "v24.13.0") throw new Error("The pinned Source Node v24.13.0 is required");
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const authority = readFileSync(new URL("../node-inspect-entry-sourceonly-20261018/authority/inspect.js", import.meta.url));
if (digest(authority) !== "380aa09fae68e3279d0fb2469a24d75931a8098c84354347bf7130a38852b597")
    throw new Error("Source inspector authority bytes changed");
const observer = readFileSync(new URL("../../src/extensions/fixtures/native-node-inspect-observer.mjs", import.meta.url), "utf8");
if (digest(observer) !== "271e138c70f43b1adc4a56a052ee7e0330129010b8d2076288a5d9439c976bb8")
    throw new Error("Source formatter observer bytes changed");
const allowed = ["observeInspectFormatShape","observeInspectFormatPlaceholders","observeInspectFormatConversions","observeInspectFormatInspection","observeInspectFormatRest","observeInspectFormatCaptured","observeInspectFormatJson","observeInspectFormatCalibration"];
const selected = process.argv[2];
if (process.argv.length !== 3 || !allowed.includes(selected))
    throw new Error("Select exactly one declared formatter observer for this fresh process");
const body = "(function(format,inspect){\"use strict\";\n" + observer +
    "\n" + selected + "(format,inspect);\n})";
const observe = runInThisContext(body, {filename:"actual-node-inspect-format-source-observer.js"});
observe(format, inspect);
process.stdout.write(JSON.stringify({node:process.version,authoritySha256:digest(authority),observerSha256:digest(observer),declared:1,results:[{name:selected,passed:true}]},null,2)+"\n");
