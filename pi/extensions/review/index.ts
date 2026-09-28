import { existsSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentBeforeSettleEvent, TurnEndEvent, SessionBoundaryDraft, ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { automaticEnabled, delivered, message, selectFeedback, SETTINGS_TYPE, type Snapshot } from "./inbox.ts";

// Resolve the symlink so the globally installed adapter uses its matching Lua CLI.
const cli = resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), "../../../nvim/scripts/review.lua");

export default function reviewExtension(pi: ExtensionAPI) {
  let deliveriesThisRun = 0;
  let lastError = "";
  let checking = false;

  function notify(ctx: ExtensionContext, text: string, error = false) {
    if (ctx.hasUI) ctx.ui.notify(text, error ? "warning" : "info");
    else if (error) console.error(text);
  }

  async function snapshot(ctx: ExtensionContext): Promise<Snapshot | undefined> {
    // Absent logs are inert: no folder creation and no Neovim startup.
    let directory = process.env.NVIM_REVIEW_DIR;
    if (directory && !directory.startsWith("/")) throw new Error("NVIM_REVIEW_DIR must be absolute");
    if (!directory) {
      const result = await pi.exec("git", ["rev-parse", "--path-format=absolute", "--git-path", "agent-review"], {
        cwd: ctx.cwd, timeout: 5000, signal: ctx.signal,
      });
      if (result.code !== 0) return undefined; // Not a Git worktree.
      directory = result.stdout.trim();
    }
    if (!existsSync(join(directory, "events.jsonl"))) return undefined;
    const result = await pi.exec("nvim", ["--headless", "-u", "NONE", "-l", cli, "snapshot"], {
      cwd: ctx.cwd, timeout: 10000, signal: ctx.signal,
    });
    if (result.code !== 0) throw new Error(result.stderr || "Review CLI failed");
    const data = JSON.parse(result.stdout) as Snapshot;
    if (data.version !== 1 || !Array.isArray(data.events) || !Array.isArray(data.threads)
      || typeof data.root !== "string" || typeof data.log !== "string") throw new Error("Invalid review snapshot");
    data.log = realpathSync(data.log);
    return data;
  }

  async function check(ctx: ExtensionContext, manual: boolean, pending: readonly SessionBoundaryDraft[] = []) {
    const data = await snapshot(ctx);
    if (!data) return undefined;
    const seen = delivered([...ctx.sessionManager.getBranch(), ...pending], data.log);
    const selected = selectFeedback(data, seen, manual);
    if (selected.threads.length === 0) return undefined;
    return message(data, selected, cli, manual);
  }

  function report(ctx: ExtensionContext, error: unknown) {
    const text = `Review check failed (will retry): ${String(error)}`;
    if (text !== lastError) notify(ctx, text, true);
    lastError = text;
  }

  pi.on("session_start", () => { deliveriesThisRun = 0; lastError = ""; });
  pi.on("agent_start", () => { deliveriesThisRun = 0; });

  // Both boundaries share the same branch-aware delivery IDs. Returning entries
  // lets Pi atomically attach the message to this boundary rather than steering
  // a running tool or racing a queued message against a separate receipt.
  const boundary = async (event: TurnEndEvent | AgentBeforeSettleEvent, ctx: ExtensionContext) => {
    if (checking || event.outcome !== "completed" || !event.context.canContinue
      || deliveriesThisRun >= 5 || !automaticEnabled(ctx.sessionManager.getBranch())) return;
    checking = true;
    try {
      const feedback = await check(ctx, false, event.entries);
      lastError = "";
      if (!feedback) return;
      deliveriesThisRun++;
      return { entries: [...event.entries, { type: "custom_message" as const, ...feedback }], continue: true };
    } catch (error) { report(ctx, error); }
    finally { checking = false; }
  };
  pi.on("turn_end", boundary);
  pi.on("agent_before_settle", boundary);

  pi.registerCommand("review", {
    description: "Handle worktree review feedback; /review on|off|status controls automatic checks",
    getArgumentCompletions: (prefix) => {
      const items = ["on", "off", "status"].filter((s) => s.startsWith(prefix));
      return items.length ? items.map((value) => ({ value, label: value })) : null;
    },
    handler: async (args, ctx) => {
      const action = args.trim();
      if (action === "on" || action === "off") {
        pi.appendEntry(SETTINGS_TYPE, { enabled: action === "on" });
        notify(ctx, `Automatic review checks ${action} for this session branch.`);
        return;
      }
      if (action === "status") {
        notify(ctx, `Automatic review checks: ${automaticEnabled(ctx.sessionManager.getBranch()) ? "on" : "off"}. No idle auto-wake.`);
        return;
      }
      if (action) { notify(ctx, "Usage: /review [on|off|status]", true); return; }
      if (checking) { notify(ctx, "Review check already running."); return; }
      checking = true;
      try {
        const feedback = await check(ctx, true);
        if (feedback) pi.sendMessage(feedback, { triggerTurn: true, deliverAs: "followUp" });
        else notify(ctx, "No unresolved human review threads in this worktree.");
        lastError = "";
      } catch (error) { report(ctx, error); }
      finally { checking = false; }
    },
  });
}
