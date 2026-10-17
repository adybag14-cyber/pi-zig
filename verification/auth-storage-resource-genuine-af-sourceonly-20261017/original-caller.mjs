// ORIGINAL caller only. Supply the exact genuine upstream module URLs and the
// pinned shared observer URL. No reimplementation, expected output or loader.
const [authURL, resourceURL, observerURL] = process.argv.slice(2);
if (!authURL || !resourceURL || !observerURL) throw new Error("exact original module and observer URLs required");
const auth = await import(authURL);
const resources = await import(resourceURL);
const observer = await import(observerURL);
const result = { auth: await observer.observeAuthStorage(auth.AuthStorage), reload: await observer.observeResourceReload(resources.DefaultResourceLoader) };
process.stdout.write(JSON.stringify(result) + "\n");
