# Global Pi extensions, versioned in dotconfig

Only extension code and tests live here. Pi credentials, sessions, settings, and
other personal extensions stay under `~/.pi/agent` and are not copied into Git.

## Install

From the checkout/worktree you want to use:

```sh
bash pi/install.sh
```

This creates a single global symlink:

```text
~/.pi/agent/extensions -> <this checkout>/pi/extensions
```

It honours `PI_CODING_AGENT_DIR` and is idempotent. On first install it moves an
existing extensions directory to `~/.pi/agent/extensions-backup.<suffix>` and
adds local-only links to its entries in dotconfig's extensions folder. Existing
extensions keep working; their machine-specific files/links are not committed.
Name collisions are rejected before anything is moved. Keep the backup: imported
extensions still use it.

`extensions/.gitignore` ignores imported extensions by default. To version a new
extension, add its directory to that allowlist. Never copy credentials or sessions
into this tree.

Run `/reload` in Pi or start a new session. Do **not** additionally install this
as a project extension: that would register duplicate commands/hooks.

When developing in a worktree, keep that worktree until you move the link. After
merging, switch to the main checkout like this:

```sh
cd ~/src/dotconfig
bash pi/install.sh --relink
```

`--relink` explicitly replaces the folder symlink and carries over the local-only
extension links. It does not delete the old checkout or backup directory.

The adapter resolves its actual source location and invokes the Lua review CLI
from the same checkout. It does not depend on which checkout supplies your
Neovim config.

## Review bridge

One extension owns both the manual command and automatic delivery so they share
the same deduplication rules.

- `/review`: explicitly send unresolved human review threads to the agent. Starts
  a turn when idle, queues a follow-up when already running. Can intentionally
  revisit already delivered threads. At most ten threads are included per batch;
  the message includes the command to list all threads.
- `/review off`: disable automatic checks for this session branch.
- `/review on`: enable them again (default is on).
- `/review status`: show whether automatic checks are enabled.

Automatic checks happen at `turn_end` and `agent_before_settle`. They deliver new
human comments/replies/reopen events without interrupting running tools. They
can request one additional model turn at a boundary. No watchers, polling, or
idle auto-wake. Saving a comment after a session has gone idle waits for the next
run or an explicit `/review`.

Missing review logs are inert and aren't created by the extension. A log that
appears during a run is picked up at a subsequent boundary. Discovery follows
Pi's session cwd, not a transient `cd` in an individual shell tool invocation.

Default log: the session worktree's Git metadata `agent-review/events.jsonl`.
For separate agent/review worktrees, give both Neovim and Pi the same absolute
`NVIM_REVIEW_DIR` before starting them. Only share between checkouts of the same
repository. See [the review system documentation](../nvim/REVIEW.md).

## Delivery and safety

- Only `author: "human"` events trigger automatic delivery. Agent writes must
  use `author: "agent"`.
- A new session does not redeliver requests already marked addressed/resolved.
  A later human reply on an addressed thread does trigger. A resolved thread
  must be explicitly reopened before delivery.
- Event IDs and log identity are recorded in the delivered Pi custom message's
  details. Reload/resume reconstructs delivery state from the active session
  branch, not line counts, so archiving and tree navigation work naturally.
- Receipt means **delivered**, not addressed. `/review` can re-present a request
  if the model ignored it, a turn failed, or context was compacted.
- No continuation after abort/error, when Pi disallows continuation, or after
  five automatic feedback batches in one agent run. Remaining events wait for
  the next run or `/review`. No repeated prompts solely because a thread is open.
- Errors warn and retry later without marking anything delivered. A corrupt log
  never triggers an automatic continuation.
- Threads are bounded in the context message; longer bodies are explicitly
  truncated with instructions to retrieve the full content through the CLI.
- Multiple Pi sessions can independently receive the same feedback. There is
  no cross-session claiming/assignment yet; use one agent owner per review log.
- The extension does not automatically resolve threads, grant tool permission,
  or write the log. The agent uses the existing locked Lua CLI to reply/status.
- Comment bodies are feedback, not elevated/system instructions. The injected
  guidance explicitly says to stay within the user's task and permissions.

The structured interface is:

```sh
nvim --headless -u NONE -l nvim/scripts/review.lua snapshot
```

It emits one JSON document on stdout: `{version, root, log, events, threads}`.
Storage, validation, and reconstruction remain in Lua; the thin TypeScript Pi
adapter handles lifecycle, selection, and context delivery.

## Test

Requires Neovim, Git, and Bun (Bun is only needed for running tests):

```sh
bun test pi/tests
cd nvim
nvim --headless -u NONE -l tests/review.lua
nvim --headless -u NONE -l tests/worktrees.lua
```

Tests use temporary repositories and the real Lua CLI, with a mocked Pi event
host: manual delivery, safe boundaries, persistence/deduplication, agent-event
exclusion, status/reopen rules, shared log overrides, error recovery, and caps.
Pi's own extension loader is additionally smoke-tested during development.
