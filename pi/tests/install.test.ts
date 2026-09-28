import { afterEach, expect, test } from "bun:test";
import { execFile } from "node:child_process";
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
const exec = promisify(execFile);
const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
function fixture() {
  const root = mkdtempSync(join(tmpdir(), "pi-install-")); roots.push(root);
  const agent = join(root, "agent");
  mkdirSync(join(agent, "extensions", "subagent"), { recursive: true });
  writeFileSync(join(agent, "extensions", "subagent", "index.ts"), "existing extension");
  function checkout(name: string) {
    const path = join(root, name, "pi");
    mkdirSync(join(path, "extensions", "review"), { recursive: true });
    copyFileSync(resolve(import.meta.dir, "../install.mjs"), join(path, "install.mjs"));
    return path;
  }
  const run = (path: string, args: string[] = []) => exec(process.execPath, [join(path, "install.mjs"), ...args], {
    env: { ...process.env, PI_CODING_AGENT_DIR: agent },
  });
  return { agent, checkout, run };
}

test("folder symlink preserves existing extension, repeat install, and worktree relink", async () => {
  const f = fixture();
  const first = f.checkout("worktree");
  await f.run(first);
  expect(lstatSync(join(f.agent, "extensions")).isSymbolicLink()).toBe(true);
  expect(realpathSync(join(f.agent, "extensions"))).toBe(realpathSync(join(first, "extensions")));
  const subagent = join(f.agent, "extensions", "subagent", "index.ts");
  expect(readFileSync(subagent, "utf8")).toBe("existing extension");
  await f.run(first);
  const second = f.checkout("main");
  await expect(f.run(second)).rejects.toThrow();
  await f.run(second, ["--relink"]);
  rmSync(first, { recursive: true });
  expect(realpathSync(join(f.agent, "extensions"))).toBe(realpathSync(join(second, "extensions")));
  expect(readFileSync(subagent, "utf8")).toBe("existing extension");
});

test("collision fails before moving original directory", async () => {
  const f = fixture();
  const checkout = f.checkout("checkout");
  mkdirSync(join(checkout, "extensions", "subagent"));
  await expect(f.run(checkout)).rejects.toThrow();
  expect(lstatSync(join(f.agent, "extensions")).isSymbolicLink()).toBe(false);
  expect(existsSync(join(f.agent, "extensions", "subagent", "index.ts"))).toBe(true);
});

test("failed import rolls back the original directory and partial links", async () => {
  const f = fixture();
  const checkout = f.checkout("checkout");
  symlinkSync("/nonexistent/pi-test-extension", join(f.agent, "extensions", "zzz-broken"));
  await expect(f.run(checkout)).rejects.toThrow();
  expect(lstatSync(join(f.agent, "extensions")).isDirectory()).toBe(true);
  expect(readFileSync(join(f.agent, "extensions", "subagent", "index.ts"), "utf8")).toBe("existing extension");
  expect(existsSync(join(checkout, "extensions", "subagent"))).toBe(false);
});
