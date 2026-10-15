// Actual immutable Source bodies; this observer only supplies owned inputs.
import fs from "node:fs";
import path from "node:path";
import { envApiKeyAuth, lazyOAuth } from "file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/helpers.ts";
import { defaultProviderAuthContext } from "file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/context.ts";
import { abortableSleep, pollOAuthDeviceCodeFlow } from "file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/device-code.ts";
import { run } from "../../src/extensions/native_ai_auth_helpers_fixture.mjs";
const [ownedDirectory, outputPath] = process.argv.slice(2);
if (!ownedDirectory || !outputPath) throw Error("expected owned fixture directory and output path");
fs.mkdirSync(ownedDirectory, { recursive: true });
const ownedPath = path.join(ownedDirectory, "owned-auth-helper-input.txt");
fs.writeFileSync(ownedPath, "owned auth helper fixture only");
const rows = await run({ envApiKeyAuth, lazyOAuth, defaultProviderAuthContext, abortableSleep, pollOAuthDeviceCodeFlow }, ownedPath);
fs.writeFileSync(outputPath, JSON.stringify({
  authority: "actual auth/helpers.ts, auth/context.ts and auth/oauth/device-code.ts from immutable ae7 Source",
  sourceRoot: "C:/Users/adyba/pi-upstream-source-ae7b16d-20261015",
  actualNode: { version: process.version, executable: process.execPath },
  cases: rows.length,
  rows,
}, null, 2));
