import assert from "node:assert/strict";
import { test } from "node:test";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readdir, readFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { spawnSync } from "node:child_process";

const script = resolve("scripts/deploy.ps1");
const shell = process.env.POWERSHELL_BIN;
for (const args of [[], ["-DryRun"]]) test(`deployment ${args.length ? "DryRun" : "default"} prints plan without tools or writes`, async () => {
  assert.ok(existsSync(script), "deployment script must exist");
  assert.ok(shell, "Set POWERSHELL_BIN to an actual PowerShell executable");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  const root = process.env.SOBOSUBA_QA_ROOT;
  await mkdir(root, { recursive: true });
  const box = await mkdtemp(join(root, "deploy-"));
  await mkdir(join(box, "scripts"));
  await copyFile(script, join(box, "scripts/deploy.ps1"));
  await copyFile("wrangler.toml", join(box, "wrangler.toml"));
  const before = await readdir(box, { recursive: true });
  const localConfig = await readFile(join(box, "wrangler.toml"), "utf8");
  // There is no node, Wrangler, or dependency installation here; no replacement commands.
  const child = spawnSync(shell, ["-NoProfile", "-NonInteractive", "-File", join(box, "scripts/deploy.ps1"), ...args], {
    cwd: box, env: { ...process.env, PATH: "", WRANGLER_SEND_METRICS: "false" }, windowsHide: true, encoding: "utf8", timeout: 10000 });
  assert.equal(child.status, 0, child.stdout + child.stderr);
  assert.equal(child.stderr, "");
  let previous = -1;
  for (const command of ["wrangler whoami --json", "wrangler d1 list --json", "wrangler d1 create prime-sobo-production",
    "write wrangler.production.toml", "wrangler d1 migrations apply", "wrangler secret put IP_HASH_SECRET", "wrangler deploy", "/v1/health"]) {
    const index = child.stdout.indexOf(command);
    assert.ok(index > previous, `ordered plan missing ${command}: ${child.stdout}`);
    previous = index;
  }
  assert.ok(!/[a-f0-9]{64}/i.test(child.stdout), "no generated secret in plan");
  assert.deepEqual(await readdir(box, { recursive: true }), before);
  assert.equal(await readFile(join(box, "wrangler.toml"), "utf8"), localConfig);
});

test("deployment script requires PowerShell 7.2 or later before Execute can start", () => {
  // Execute uses [Convert]::ToHexString (.NET 5+, PowerShell 7.1+) after D1 creation and
  // migrations, and relies on 7.2+ so `2>$null` stderr from wrangler is not turned into a
  // terminating error by ErrorActionPreference=Stop. An older host must be refused up front.
  assert.ok(shell, "Set POWERSHELL_BIN to an actual PowerShell executable");
  const parse = "$t=$null; $e=$null; $a=[System.Management.Automation.Language.Parser]::ParseFile($env:DEPLOY_SCRIPT,[ref]$t,[ref]$e); " +
    "if ($e.Count -or -not $a.ScriptRequirements -or -not $a.ScriptRequirements.RequiredPSVersion) { exit 2 }; " +
    "$a.ScriptRequirements.RequiredPSVersion.ToString()";
  const child = spawnSync(shell, ["-NoProfile", "-NonInteractive", "-Command", parse], {
    env: { ...process.env, DEPLOY_SCRIPT: script }, windowsHide: true, encoding: "utf8", timeout: 10000 });
  assert.equal(child.status, 0, child.stdout + child.stderr);
  const [major, minor] = child.stdout.trim().split(".").map(Number);
  assert.ok(major > 7 || (major === 7 && minor >= 2), `#requires must be at least 7.2, got ${child.stdout.trim()}`);
});

test("production config is ignored by Git", () => {
  const result = spawnSync("git", ["check-ignore", "server/wrangler.production.toml"], { cwd: resolve(".."), encoding: "utf8", windowsHide: true });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
