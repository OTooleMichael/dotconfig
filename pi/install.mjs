import { lstatSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, renameSync, rmdirSync, symlinkSync, unlinkSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

function stat(path) {
  try { return lstatSync(path); }
  catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
}

function importsFrom(legacy, source, relinking) {
  if (!legacy) return [];
  return readdirSync(legacy).filter((name) => {
    if (name.startsWith(".")) return false;
    if (relinking && name === "review") return false;
    const destination = join(source, name);
    if (!stat(destination)) return true;
    if (realpathSync(join(legacy, name)) === realpathSync(destination)) return false;
    throw new Error(`Extension name collision; nothing moved: ${name}`);
  });
}

function install() {
  const args = process.argv.slice(2);
  if (args.some((arg) => arg !== "--relink")) throw new Error("Usage: node pi/install.mjs [--relink]");
  const source = realpathSync(join(dirname(fileURLToPath(import.meta.url)), "extensions"));
  const agent = resolve(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi/agent"));
  const target = join(agent, "extensions");
  const current = stat(target);
  const relinking = current?.isSymbolicLink() ?? false;
  if (relinking && realpathSync(target) === source) {
    console.log(`Already installed: ${target} -> ${source}`);
    return;
  }
  if (relinking && !args.includes("--relink")) {
    throw new Error(`Already linked elsewhere: ${target}\nUse --relink to move it to this checkout.`);
  }
  if (current && !relinking && !current.isDirectory()) throw new Error(`Expected a directory: ${target}`);

  let legacy = current ? realpathSync(target) : undefined;
  const names = importsFrom(legacy, source, relinking); // Preflight before moving anything.
  const created = [];
  let backup;
  const pending = `${target}.link-${randomUUID()}`;
  mkdirSync(agent, { recursive: true });
  try {
    if (current?.isDirectory()) {
      backup = mkdtempSync(join(agent, "extensions-backup."));
      rmdirSync(backup);
      renameSync(target, backup);
      legacy = backup;
    }
    for (const name of names) {
      const destination = join(source, name);
      // Resolve local links so removing an old worktree won't break imports.
      symlinkSync(realpathSync(join(legacy, name)), destination);
      created.push(destination);
    }
    symlinkSync(source, pending);
    renameSync(pending, target); // Atomically replace the previous folder symlink.
  } catch (error) {
    if (stat(pending)) unlinkSync(pending);
    for (const path of created.reverse()) unlinkSync(path);
    if (backup && !stat(target)) renameSync(backup, target);
    throw error;
  }
  if (backup) console.log(`Preserved existing extensions at: ${backup}`);
  console.log(`Installed: ${target} -> ${source}\nRun /reload in Pi, or start a new session.`);
}

try { install(); }
catch (error) { console.error(error.message); process.exitCode = 1; }
