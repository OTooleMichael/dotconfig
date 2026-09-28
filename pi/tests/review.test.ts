import { afterAll, afterEach, describe, expect, mock, test } from "bun:test";
import { execFile } from "node:child_process";
import { mkdtempSync, mkdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import { CHECK_TOOL, delivered, MESSAGE_TYPE, REQUEST_TYPE, reviewTarget, selectFeedback, type Snapshot } from "../extensions/review/inbox.ts";

// Pi supplies this module to extensions. Use that same installed dependency in
// the standalone Bun test host, rather than adding a second package installation.
const piDirectory = dirname(realpathSync(Bun.which("pi")!));
const ai = await import(Bun.resolveSync("@earendil-works/pi-ai", piDirectory));
mock.module("@earendil-works/pi-ai", () => ai);
const { default: extension } = await import("../extensions/review/index.ts");

const inheritedReviewDir = process.env.NVIM_REVIEW_DIR;
delete process.env.NVIM_REVIEW_DIR;
afterAll(() => {
  if (inheritedReviewDir === undefined) delete process.env.NVIM_REVIEW_DIR;
  else process.env.NVIM_REVIEW_DIR = inheritedReviewDir;
});
const exec = promisify(execFile);
const temp: string[] = [];
afterEach(() => { for (const path of temp.splice(0)) rmSync(path, { recursive: true, force: true }); });
const cli = resolve(import.meta.dir, "../../nvim/scripts/review.lua");

function sample(): Snapshot {
  const comment = { id: "c1", type: "comment" as const, author: "human", body: "Please fix" };
  return { version: 1, root: "/repo", log: "/repo/.git/agent-review/events.jsonl", events: [comment],
    threads: [{ id: "c1", status: "open", comment, replies: [] }] };
}

describe("delivery policy", () => {
  test("delivers new human events once, scoped to log and branch", () => {
    const data = sample();
    expect(selectFeedback(data, new Set()).eventIds).toEqual(["c1"]);
    const entry = { type: "custom_message", customType: MESSAGE_TYPE,
      details: { version: 1, log: data.log, eventIds: ["c1"] } };
    expect(selectFeedback(data, delivered([entry], data.log)).threads).toEqual([]);
    expect(delivered([entry], "/other").size).toBe(0);
    expect(delivered([], data.log).size).toBe(0); // Navigate to before delivery.
    expect(selectFeedback(data, new Set(["c1"]), true).threads).toHaveLength(1);
  });
  test("agent replies don't trigger; addressed requests stay handled across sessions", () => {
    const data = sample();
    data.events.push({ id: "a1", type: "reply", author: "agent", thread: "c1", body: "Done" });
    expect(selectFeedback(data, new Set(["c1"])).threads).toEqual([]);
    data.events.push({ id: "s1", type: "status", author: "agent", thread: "c1", status: "addressed" });
    data.threads[0].status = "addressed";
    expect(selectFeedback(data, new Set()).threads).toEqual([]);
    data.events.push({ id: "h2", type: "reply", author: "human", thread: "c1", body: "Not quite" });
    expect(selectFeedback(data, new Set()).eventIds).toEqual(["h2"]);
  });
  test("resolved threads wait for explicit reopen", () => {
    const data = sample();
    data.threads[0].status = "resolved";
    data.events.push({ id: "s1", type: "status", author: "human", thread: "c1", status: "resolved" });
    expect(selectFeedback(data, new Set(), true).threads).toEqual([]);
    data.threads[0].status = "open";
    data.events.push({ id: "s2", type: "status", author: "human", thread: "c1", status: "open" });
    expect(selectFeedback(data, new Set()).eventIds).toEqual(["s2"]);
  });
});

async function harness() {
  const root = mkdtempSync(join(tmpdir(), "pi-review-")); temp.push(root);
  await exec("git", ["init", "-q", root]);
  let serial = 0;
  const append = async (event: object, cwd = root) => {
    const file = join(root, `event-${serial++}.json`);
    writeFileSync(file, JSON.stringify(event));
    const result = await exec("nvim", ["--headless", "-u", "NONE", "-l", cli, "append", file], { cwd });
    return JSON.parse(result.stderr || result.stdout);
  };
  const handlers = new Map<string, Function>();
  const commands = new Map<string, any>();
  const tools = new Map<string, any>();
  const entries: any[] = [], sent: any[] = [], notices: string[] = [];
  const ctx: any = { cwd: root, hasUI: true, sessionManager: { getBranch: () => entries },
    ui: { notify: (text: string) => notices.push(text) } };
  const api = {
    registerTool: (tool: any) => tools.set(tool.name, tool),
    on: (name: string, fn: Function) => handlers.set(name, fn),
    registerCommand: (name: string, command: any) => commands.set(name, command),
    appendEntry: (customType: string, data: unknown) => entries.push({ type: "custom", customType, data }),
    sendMessage: (msg: any, options: unknown) => {
      sent.push({ msg, options }); entries.push({ type: "custom_message", ...msg });
    },
    exec: async (command: string, args: string[], options: any) => {
      try {
        const result = await exec(command, args, { cwd: options.cwd, timeout: options.timeout });
        return { ...result, code: 0, killed: false };
      } catch (error: any) { return { stdout: error.stdout ?? "", stderr: error.stderr ?? "", code: 1, killed: false }; }
    },
  } as any;
  extension(api);
  const invoke = async (directory: string) => {
    const result = await tools.get(CHECK_TOOL).execute("call", { directory }, undefined, undefined, ctx);
    entries.push({ type: "message", message: { role: "toolResult", toolName: CHECK_TOOL, ...result } });
    return result;
  };
  const boundary = async (name = "turn_end", outcome = "completed", canContinue = true, pending: any[] = []) => {
    const result = await handlers.get(name)!({ outcome, context: { canContinue }, entries: pending }, ctx);
    if (result?.entries) entries.push(...result.entries);
    return result;
  };
  return { root, ctx, append, entries, sent, notices, boundary, handlers, invoke, reload: () => extension(api), command: (args = "") => commands.get("review").handler(args, ctx) };
}

test("actual CLI snapshot and safe-boundary loop, pause/resume, manual wake", async () => {
  const h = await harness();
  expect(await h.boundary()).toBeUndefined(); // Missing log is inert.
  const c = await h.append({ type: "comment", author: "human", path: "source.lua", scope: "file", body: "Please fix" });
  expect(await h.boundary("turn_end", "aborted")).toBeUndefined();
  expect(await h.boundary("turn_end", "error")).toBeUndefined();
  expect(await h.boundary("turn_end", "completed", false)).toBeUndefined();
  expect((await h.boundary()).continue).toBe(true);
  expect(await h.boundary("agent_before_settle")).toBeUndefined();
  await h.append({ type: "reply", author: "agent", thread: c.id, body: "Working" });
  expect(await h.boundary()).toBeUndefined();
  await h.command("off");
  await h.append({ type: "reply", author: "human", thread: c.id, body: "Another detail" });
  expect(await h.boundary()).toBeUndefined();
  await h.command("on");
  expect((await h.boundary("agent_before_settle")).continue).toBe(true);
  await h.command();
  expect(h.sent).toHaveLength(1);
  expect(h.sent[0].msg.customType).toBe(REQUEST_TYPE);
  expect(h.sent[0].msg.content).toContain("Infer the correct worktree");
  await h.invoke(h.root);
  expect(await h.boundary()).toBeUndefined();
  expect(h.sent[0].options).toEqual({ triggerTurn: true, deliverAs: "followUp" });
  const result = await exec("nvim", ["--headless", "-u", "NONE", "-l", cli, "snapshot"], { cwd: h.root });
  expect(result.stderr).toBe("");
  expect(JSON.parse(result.stdout).threads).toHaveLength(1);
}, 15000);

test("caps automatic delivery and recovers on the next run", async () => {
  const h = await harness();
  const c = await h.append({ type: "comment", author: "human", path: "f", scope: "file", body: "Review" });
  for (let i = 0; i < 5; i++) {
    await h.append({ type: "reply", author: "human", thread: c.id, body: `Detail ${i}` });
    expect((await h.boundary()).continue).toBe(true);
  }
  await h.append({ type: "reply", author: "human", thread: c.id, body: "Deferred detail" });
  expect(await h.boundary()).toBeUndefined();
  await h.handlers.get("agent_start")!();
  expect((await h.boundary()).continue).toBe(true);
}, 15000);

test("non-Git session is inactive", async () => {
  const h = await harness();
  const outside = mkdtempSync(join(tmpdir(), "not-a-repo-")); temp.push(outside);
  h.ctx.cwd = outside;
  expect(await h.boundary()).toBeUndefined();
  expect(h.notices).toHaveLength(0);
});

test("corrupt log doesn't continue or swallow feedback; retries after repair", async () => {
  const h = await harness();
  const c = await h.append({ type: "comment", author: "human", path: "f", scope: "file", body: "Review" });
  const log = join(h.root, ".git/agent-review/events.jsonl");
  const good = await Bun.file(log).text();
  writeFileSync(log, "broken");
  expect(await h.boundary()).toBeUndefined();
  expect(h.notices).toHaveLength(1);
  writeFileSync(log, good);
  expect((await h.boundary()).entries[0].details.eventIds).toEqual([c.id]);
}, 15000);

test("context-selected worktree overrides cwd, persists across reload, and follows branch navigation", async () => {
  const h = await harness();
  await h.append({ type: "comment", author: "human", path: "main.lua", scope: "file", body: "Wrong tree" });
  await exec("git", ["-C", h.root, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-qm", "init"]);
  const worktree = h.root + "-review"; temp.push(worktree);
  await exec("git", ["-C", h.root, "worktree", "add", "-b", "review", worktree]);
  mkdirSync(join(worktree, "src"));
  const c = await h.append({ type: "comment", author: "human", scope: "worktree", body: "Correct tree: keep the scope small" }, worktree);

  await h.command();
  const beforeSelection = h.entries.length;
  expect(await h.boundary()).toBeUndefined(); // Don't check the old/default tree while deciding.
  const result = await h.invoke(join(worktree, "src")); // Agent supplies its inferred directory.
  expect(result.content[0].text).toContain("Correct tree");
  expect(result.content[0].text).not.toContain("Wrong tree");
  expect(result.details.target.root).toBe(realpathSync(worktree));
  expect(h.ctx.cwd).toBe(h.root); // Selection doesn't change Pi's cwd.
  expect(await h.boundary()).toBeUndefined(); // Tool delivery is deduplicated too.

  h.reload();
  await h.command("status");
  expect(h.notices.at(-1)).toContain(realpathSync(worktree));
  await h.append({ type: "reply", thread: c.id, author: "human", body: "Later feedback" }, worktree);
  const next = await h.boundary();
  expect(next.entries[0].content).toContain("Later feedback");
  expect(next.entries[0].content).not.toContain("Wrong tree");

  h.entries.splice(beforeSelection); // Navigate to before the selection tool result.
  expect(reviewTarget(h.entries).target).toBeUndefined();
  expect(reviewTarget(h.entries).pending).toBe(true);
  expect(await h.boundary()).toBeUndefined();
  await h.invoke(h.root); // /review can retarget when the conversation moves.
  expect(reviewTarget(h.entries).target?.root).toBe(realpathSync(h.root));
}, 15000);

test("selects an empty worktree from a non-Git session and detects later comments", async () => {
  const h = await harness();
  const outside = mkdtempSync(join(tmpdir(), "review-session-home-")); temp.push(outside);
  h.ctx.cwd = outside;
  await h.command();
  expect(h.sent[0].msg.content).toContain(outside);
  expect(await h.boundary()).toBeUndefined();
  const result = await h.invoke(h.root);
  expect(result.content[0].text).toContain("No unresolved human review threads");
  expect(reviewTarget(h.entries).target?.root).toBe(realpathSync(h.root));
  const c = await h.append({ type: "comment", author: "human", path: "f", scope: "file", body: "Arrived later" });
  expect((await h.boundary()).entries[0].details.eventIds).toEqual([c.id]);
}, 15000);

test("failed selections don't change the target or resume old automatic checks", async () => {
  const h = await harness();
  await h.invoke(h.root);
  const original = reviewTarget(h.entries).target;
  await h.command();
  await expect(h.invoke("relative/path")).rejects.toThrow("absolute");
  const outside = mkdtempSync(join(tmpdir(), "not-a-worktree-")); temp.push(outside);
  await expect(h.invoke(outside)).rejects.toThrow();
  expect(reviewTarget(h.entries).target).toEqual(original);
  expect(reviewTarget(h.entries).pending).toBe(true);
  expect(await h.boundary()).toBeUndefined();
}, 15000);

test("shared review directory override", async () => {
  const h = await harness();
  const dir = join(h.root, "shared"); mkdirSync(dir);
  const previous = process.env.NVIM_REVIEW_DIR;
  try {
    process.env.NVIM_REVIEW_DIR = dir;
    await h.append({ type: "comment", author: "human", path: "f", scope: "file", body: "Shared" });
    expect((await h.boundary()).entries[0].details.log).toBe(realpathSync(join(dir, "events.jsonl")));
  } finally {
    if (previous === undefined) delete process.env.NVIM_REVIEW_DIR; else process.env.NVIM_REVIEW_DIR = previous;
  }
}, 15000);
