// Authored capture entrypoint. Root grants pinned Node execution separately.
import fs from "node:fs";
import crypto from "node:crypto";
import vm from "node:vm";
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
if (process.version !== "v24.13.0") throw new Error("Pinned Node v24.13.0 is required");
const hash = data => crypto.createHash("sha256").update(data).digest("hex");
const authorityBytes = fs.readFileSync(new URL("./authority/selected-node-source.json", import.meta.url));
const authority = JSON.parse(authorityBytes.toString("utf8"));
const pins = new Map([
    ["lib/internal/url.js", "b5587882ecfc9965e27c910b0964103ca16c9fbd3caf0a5b6ad5d3f567caa19f"],
    ["lib/internal/errors.js", "3b085f06a00a5c6805009e79fa3c9be1dfb3e6bf80625fb5d57e21f55e4dc27d"],
    ["lib/internal/util.js", "ebd5e67c4b31e484b157239f7a7e38cbe29f175afb53d2b95e19acc2520d43b5"],
    ["src/node_url.cc", "c909ab8932d45fdacc4193c443e6377e940370f10249334d1b254291bed4f4c3"],
]);
for (const [path, expected] of pins) {
    const documents = authority.documents.filter(item => item.url === "https://raw.githubusercontent.com/nodejs/node/v24.13.0/" + path);
    if (!documents.length || documents.some(item => item.content_sha256 !== expected)) throw new Error("Pinned Node authority changed: " + path);
}
const observer = fs.readFileSync(new URL("../../src/extensions/fixtures/native-node-file-url-observer.mjs", import.meta.url));
vm.runInThisContext(observer.toString("utf8"), {filename:"actual-node-file-url-observer.mjs"});
const internal = require("internal/url");
const {codes} = require("internal/errors");
const actual = {
    isURL: internal.isURL,
    fileURLToPath: internal.fileURLToPath,
    toPathIfFileURL: internal.toPathIfFileURL,
    URL: internal.URL,
    platform: process.platform,
    errors: {
        ERR_INVALID_ARG_TYPE: codes.ERR_INVALID_ARG_TYPE,
        ERR_INVALID_URL_SCHEME: codes.ERR_INVALID_URL_SCHEME,
        ERR_INVALID_FILE_URL_PATH: codes.ERR_INVALID_FILE_URL_PATH,
        ERR_INVALID_FILE_URL_HOST: codes.ERR_INVALID_FILE_URL_HOST,
    },
    inspectModule: require("internal/util/inspect"),
};
const names = [
    "observeUrlStructure", "observeUrlIdentity", "observeUrlReadOrder",
    "observeUrlRepeatedGate", "observeUrlWindowsChoice", "observeUrlCapturedIntrinsics",
    "observeUrlFailures", "observeUrlEncodedSeparators", "observeUrlUNC",
    "observeUrlPrivateRegex", "observeUrlSymbolAndShapes",
    "observeUrlHostClass", "observeUrlFunctionMessages",
];
const observations = [];
for (const name of names) { globalThis[name](actual); observations.push({name, passed:true}); }
process.stdout.write(JSON.stringify({
    runtime:process.version, executable:process.execPath, declared:names.length,
    authority_sha256:hash(authorityBytes), observer_sha256:hash(observer), observations,
}) + "\n");
