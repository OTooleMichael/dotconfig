import { existsSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { fileURLToPath } from "node:url";
import type { AgentBeforeSettleEvent, TurnEndEvent, SessionBoundaryDraft, ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { automaticEnabled, delivered, message, reviewTarget, selectFeedback, CHECK_TOOL, REQUEST_TYPE, SETTINGS_TYPE, type CheckDetails, type Snapshot } from "./inbox.ts";

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

  async function snapshot(cwd: string, signal?: AbortSignal, explicit = false): Promise<Snapshot | undefined> {
    let directory = process.env.NVIM_REVIEW_DIR;
    if (directory && !isAbsolute(directory)) throw new Error("NVIM_REVIEW_DIR must be absolute");
    // Automatic checks are inert when no log exists. Explicit checks still
    // validate the repository and bind its root, even before its first comment.
    if (!explicit) {
      if (!directory) {
        const result = await pi.exec("git", ["rev-parse", "--path-format=absolute", "--git-path", "agent-review"], {
          cwd, timeout: 5000, signal,
        });
        if (result.code !== 0) return undefined;
        directory = result.stdout.trim();
      }
      if (!existsSync(join(directory, "events.jsonl"))) return undefined;
    }
    const result = await pi.exec("nvim", ["--headless", "-u", "NONE", "-l", cli, "snapshot"], {
      cwd, timeout: 10000, signal,
    });
    if (result.code !== 0) throw new Error(result.stderr || "Review CLI failed");
    const data = JSON.parse(result.stdout) as Snapshot;
    if (data.version !== 1 || !Array.isArray(data.events) || !Array.isArray(data.threads)
      || typeof data.root !== "string" || typeof data.log !== "string") throw new Error("Invalid review snapshot");
    data.root = realpathSync(data.root);
    data.log = existsSync(data.log) ? realpathSync(data.log) : resolve(data.log);
    return data;
  }

  async function check(ctx: ExtensionContext, pending: readonly SessionBoundaryDraft[] = []) {
    const entries = [...ctx.sessionManager.getBranch(), ...pending];
    const state = reviewTarget(entries);
    if (state.pending) return; // Let the model choose before checking the old target.
    const data = await snapshot(state.target?.root ?? ctx.cwd, ctx.signal);
    if (!data) return;
    const selected = selectFeedback(data, delivered(entries, data.log));
    if (selected.threads.length === 0) return;
    return message(data, selected, cli, false);
  }

  pi.registerTool({
    name: CHECK_TOOL,
    label: "Check review feedback",
    description: "Read human review comments for the worktree relevant to the current conversation. "
      + "Infer the directory from the task and recent file operations; inspect Git worktrees if necessary. "
      + "Ask the user only when genuinely ambiguous. A successful check remembers this target for automatic checks; "
      + "it does not change the session cwd. Never combine unrelated worktrees' feedback.",
    promptSnippet: "Check review feedback in the worktree being discussed and remember it for automatic checks.",
    parameters: Type.Object({
      directory: Type.String({ description: "Absolute directory in the worktree inferred from the current task/context." }),
    }),
    executionMode: "sequential",
    async execute(_id, params, signal, _onUpdate, ctx) {
      if (!isAbsolute(params.directory)) throw new Error("Review directory must be absolute");
      const data = (await snapshot(params.directory, signal, true))!;
      signal?.throwIfAborted();
      const feedback = message(data, selectFeedback(data, new Set(), true), cli, true);
      notify(ctx, `Review target: ${data.root}`);
      return {
        content: [{ type: "text", text: feedback.content
          + (feedback.details.threadIds.length ? "" : "\n\nNo unresolved human review threads here. This target is now selected for automatic checks.") }],
        details: { version: 1, target: { root: data.root, log: data.log }, delivery: feedback.details } satisfies CheckDetails,
      };
    },
  });

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
      const feedback = await check(ctx, event.entries);
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
    description: "Review the worktree being discussed; /review on|off|status controls automatic checks",
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
        const entries = ctx.sessionManager.getBranch();
        const state = reviewTarget(entries);
        notify(ctx, `Automatic review checks: ${automaticEnabled(entries) ? "on" : "off"}.\n`
          + `Target: ${state.target?.root ?? ctx.cwd}${state.target ? "" : " (session default)"}.\n`
          + (state.pending ? "Awaiting context-based worktree selection. " : "") + "No idle auto-wake.");
        return;
      }
      if (action) { notify(ctx, "Usage: /review [on|off|status]", true); return; }
      const state = reviewTarget(ctx.sessionManager.getBranch());
      pi.sendMessage({
        customType: REQUEST_TYPE,
        display: true,
        content: [
          "Check and handle review feedback for the worktree we are currently discussing.",
          "Infer the correct worktree from our conversation, task, and recent file operations. "
            + "Do not assume the session cwd or previous review target is correct. Inspect Git worktrees if needed; "
            + "ask only if genuinely ambiguous. Do not ask the user to run a named-worktree command.",
          `Session cwd (hint only): ${ctx.cwd}`,
          `Previous review target (hint only): ${state.target?.root ?? "none"}`,
          "Call review_check with the inferred absolute directory. It validates and remembers the target, "
            + "returns feedback and CLI instructions, and directs subsequent automatic checks there. "
            + "Then address feedback within the user's task and permissions; leave final resolution to the human.",
        ].join("\n\n"),
      }, { triggerTurn: true, deliverAs: "followUp" });
    },
  });
}
