// Observer only: execute the immutable installed SDK credential bodies.
// Run only inside Root's granted Source capture slot with pre/post controls.
// The SDK constructor receives explicit null keys, explicit config, an owned
// fake JWT path, and an owned fetch/loopback base. No default profile resolution.
import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import { pathToFileURL } from "node:url";
import { run } from "../../src/extensions/native_ai_anthropic_federation_fixture.mjs";

const [sdkDirectory, fixtureDirectory, outputPath] = process.argv.slice(2);
if (!sdkDirectory || !fixtureDirectory || !outputPath) throw Error("expected SDK directory, owned fixture directory, output path");
const ownedDirectory = path.resolve(fixtureDirectory);
fs.mkdirSync(ownedDirectory, { recursive: true });
const identityPath = path.join(ownedDirectory, "owned-source-identity.jwt");
const { Anthropic } = await import(pathToFileURL(path.join(sdkDirectory, "client.mjs")).href);
let current;
const adapter = {
  // This test driver supplies Pi's documented singleton ownership. The
  // constructor, file reader, exchange provider, error parser and TokenCache
  // bodies are the actual SDK. This capture is SDK-level evidence; the public
  // Pi facade still requires its separate Source stream gate.
  make(config, fetch) {
    const baseURL = "http://127.0.0.1:1";
    const key = JSON.stringify([baseURL, config]);
    if (current?.key !== key || current.fetch !== fetch) {
      const sdk = new Anthropic({ apiKey: null, authToken: null, config, baseURL, fetch, dangerouslyAllowBrowser: true });
      current = { key, fetch, sdk };
    }
    return current.sdk;
  },
  token(client) { return client._authState.tokenCache.getToken(); },
  invalidate(client) { client._authState.tokenCache.invalidate(); },
};
const dependencyCapture = await run(adapter, { path: identityPath, write: value => fs.writeFileSync(identityPath, value) });

// Actual Source SDK HTTP through a server owned by this observer, with fake
// IDs and assertion. Body is captured exactly as received, without rewriting.
const received = [];
const server = http.createServer(async (request, response) => {
  if (request.method !== "POST" || request.url !== "/v1/oauth/token") {
    response.writeHead(404).end();
    return;
  }
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  received.push({ path: request.url, method: request.method, headers: request.headers, body: Buffer.concat(chunks).toString("utf8") });
  response.writeHead(200, { "Content-Type": "application/json", "Request-Id": "owned-source-loopback-request" });
  response.end(JSON.stringify({ access_token: "owned-source-loopback-access", token_type: "Bearer", expires_in: 180 }));
});
await new Promise((resolve, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", resolve);
});
let loopback;
try {
  fs.writeFileSync(identityPath, "  owned.source.loopback.jwt\n");
  const baseURL = `http://127.0.0.1:${server.address().port}`;
  const config = {
    organization_id: "owned-source-org",
    workspace_id: "owned-source-workspace",
    authentication: { type: "oidc_federation", federation_rule_id: "owned-source-rule", identity_token: { source: "file", path: identityPath } },
  };
  const client = new Anthropic({ apiKey: null, authToken: null, config, baseURL, dangerouslyAllowBrowser: true });
  loopback = { tokens: await Promise.all([client._authState.tokenCache.getToken(), client._authState.tokenCache.getToken()]), received };
} finally {
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}
const sdkPackage = JSON.parse(fs.readFileSync(path.join(sdkDirectory, "package.json"), "utf8"));
fs.writeFileSync(outputPath, JSON.stringify({
  authority: "actual installed SDK credential-chain and TokenCache with explicit Pi-shaped config",
  sdkDirectory: path.resolve(sdkDirectory),
  sdkVersion: sdkPackage.version,
  actualNode: { version: process.version, executable: process.execPath, versions: process.versions },
  fixtureDirectory: ownedDirectory,
  diagnosticPolicy: { sourceHeaders: "raw unmodified SDK headers", nativeUserAgent: "pi-zig/Zig-<actual compiler> QuickJS-<actual linked runtime> (<host OS>; <arch>)", comparison: "User-Agent diagnostic value asserted separately; auth/beta/content/session/grant/cache/error fields compared strictly" },
  dependencyCapture,
  loopback,
}, null, 2));
