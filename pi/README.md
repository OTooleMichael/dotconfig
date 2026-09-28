# Pi extensions

From the checkout/worktree you want to use:

```sh
node pi/install.mjs          # or: bun pi/install.mjs
```

This links `~/.pi/agent/extensions` to this checkout's `pi/extensions`.
Existing extensions are backed up under `~/.pi/agent/extensions-backup.*` and
linked through; keep that backup. Credentials, sessions, and settings stay outside
Git. `PI_CODING_AGENT_DIR` is supported.

Run `/reload` in Pi. After merging, run `node pi/install.mjs --relink` from the main
checkout before removing the worktree. Imported personal extensions are ignored;
add new versioned extensions to `extensions/.gitignore`'s allowlist.
Don't also install the same extension project-locally.

## Reviews

- `/review`: ask the agent to infer the relevant worktree from the conversation,
  then call `review_check` to read its feedback (including worktree-wide steering).
- `/review off` / `on` / `status`: control automatic checks for this session branch.

Automatic checks run between turns and before settling, not while tools execute.
They deliver new human comments/replies/reopens once. No idle auto-wake: use
`/review` or start another run. Agent replies don't retrigger checks; humans resolve.
Resolved threads must be reopened. Delivery doesn't guarantee the agent acted.

A successful `review_check` remembers its validated target on the session branch;
automatic checks follow that worktree without changing Pi's cwd. `/review status`
shows the target. A new `/review` asks the agent to reassess it; automatic checks
pause until selection succeeds. Ambiguity should prompt a question, not a guess.
Before selection, checks default to the session cwd. For separate agent/review
checkouts, share `NVIM_REVIEW_DIR`. Use one agent owner per log.
See [review usage](../nvim/REVIEW.md).

Delivery IDs persist on the active Pi branch. Checks stop on abort/error and are
capped at five batches per run, ten threads per batch. Long threads are truncated
with CLI retrieval instructions. Storage and writes remain in the Lua CLI.

Tests (Pi installed): `bun test pi/tests` and the Lua tests in `nvim/tests/`.
