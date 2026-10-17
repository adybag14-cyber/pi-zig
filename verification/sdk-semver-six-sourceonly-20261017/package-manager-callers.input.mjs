// Genuine original class controls. The Root capture owner supplies the real
// imported PackageAPI/SettingsAPI plus a fresh owned physical callerRoot.
// No class method, transport, semver namespace or settings method is replaced.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
export async function observePackageSemverCallers({ PackageAPI, SettingsAPI, callerRoot }) {
  mkdirSync(callerRoot, { recursive: false });
  const manager = new PackageAPI.DefaultPackageManager({ cwd: callerRoot, agentDir: join(callerRoot, 'agent'), settingsManager: SettingsAPI.SettingsManager.inMemory() });
  const rows = [];
  for (const source of ['npm:fixture', 'npm:fixture@1.2.3', 'npm:fixture@v1.2.3', 'npm:fixture@^1.2.3', 'npm:@scope/fixture@~0.2', 'npm:fixture@latest', 'npm:fixture@01.2.3', 'npm:fixture@1.2.3-alpha']) {
    rows.push({ name: 'actual-parse-'+source, value: manager.parseSource(source) });
  }
  const installedPath = join(callerRoot, 'installed'); mkdirSync(installedPath);
  for (const version of ['1.2.3', '1.3.0-alpha', '1.3.0', 'bad', '1.2.3+build']) {
    writeFileSync(join(installedPath, 'package.json'), JSON.stringify({ name: 'fixture', version }));
    for (const source of ['npm:fixture', 'npm:fixture@^1.2.3', 'npm:fixture@1.2.3-alpha', 'npm:fixture@>=1.0.0 <2']) {
      const parsed = manager.parseSource(source);
      rows.push({ name: 'actual-installed-'+version+'-'+source, value: await manager.installedNpmMatchesConfiguredVersion(parsed, installedPath) });
    }
  }
  return { scope: 'Actual original valid/validRange/satisfies call sites only; no npm-view network/gt/max/sort caller claim', rows };
}
