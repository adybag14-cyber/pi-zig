// Authored Source capture only. Root must grant a separate Node invocation
// with --expose-internals and seal the pinned binary/environment first.
import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";
import {createRequire} from "node:module";
import {runInThisContext} from "node:vm";

if (process.version !== "v24.13.0") throw new Error("Pinned Source Node v24.13.0 required");
const require = createRequire(import.meta.url);
const {codes} = require("internal/errors");
const {validateString, validateAbortSignal} = require("internal/validators");
const assert = require("internal/assert");
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const authority = readFileSync(new URL("./authority/selected-node-source.json", import.meta.url));
if (digest(authority) !== "90c87aca5e0b3b81114785934084c3ae5d0e057503767c0e6c069535453c6fcb")
    throw new Error("Retained Node argument source excerpt bytes changed");
const observer = readFileSync(new URL("../../src/extensions/fixtures/native-node-argument-observer.mjs", import.meta.url), "utf8");
const names = [
    "observeArgumentShape", "observeArgumentPrimitiveMessages", "observeArgumentExpectedLists",
    "observeArgumentValueRange", "observeArgumentInternalAssert", "observeArgumentValidators",
    "observeArgumentAbortSignal", "observeArgumentConstructorReads", "observeArgumentPrimitiveInOperand",
    "observeArgumentHiddenRest", "observeArgumentHiddenSuperTarget", "observeArgumentHiddenLimits",
    "observeArgumentHiddenThrow", "observeArgumentCapturedApplyAndRest", "observeArgumentExpectedIteratorClose",
    "observeArgumentInspectThrow",
];
const source = "(function(actual){\"use strict\";\n" + observer +
    "\nconst controls = [" + names.join(",") + "];\nreturn controls.map(control => {control(actual); return {name:control.name,passed:true};});\n})";
const observe = runInThisContext(source, {filename:"actual-node-argument-source-observer.js"});
const results = observe({codes, validateString, validateAbortSignal, assert});
process.stdout.write(JSON.stringify({
    node:process.version, authoritySha256:digest(authority), observerSha256:digest(observer),
    declared:names.length, results,
}, null, 2) + "\n");
