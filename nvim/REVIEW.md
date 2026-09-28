# Review comments

Use real source buffers (`gf` from Diffview). Restart Neovim after config changes.

| Keys | Action |
| --- | --- |
| `Space rc` | Comment on cursor line / visual range |
| `Space rC` | Comment on file |
| `Space rs` | Worktree-wide steering (`:ReviewSteer`) |
| `Space rv` / `Space rl` / `Space ra` | View comments here / in file / in worktree |

Comment/reply buffer: `:w` publishes, `:q!` discards.
Thread view: `r` replies, `s` changes status, Enter jumps to source, `R` refreshes,
`q` closes. Filter with `:ReviewComments [line|file|all] [open|addressed|resolved]`.

Steering notes appear in the worktree-wide view (`Space ra`), not file/line views,
and support the same replies and statuses. They have no source location or gutter sign.

Unresolved file/range threads have ◆ gutter signs. Range signs hide when the buffer differs
from captured source; jumps still use original line numbers. No automatic relocation.

## Agent CLI

Run from the target worktree:

```sh
CLI="$HOME/src/dotconfig/nvim/scripts/review.lua"
nvim --headless -u NONE -l "$CLI" list open
nvim --headless -u NONE -l "$CLI" reply THREAD_ID /tmp/reply.md agent
nvim --headless -u NONE -l "$CLI" status THREAD_ID addressed agent
nvim --headless -u NONE -l "$CLI" snapshot
```

Agents reply and mark addressed; humans resolve. `help` lists all commands.
`snapshot` emits `{version, root, log, events, threads}` as JSON on stdout.
[Pi integration](../pi/README.md) provides automatic checks and `/review`.

## Storage

`events.jsonl` lives in `git rev-parse --git-path agent-review`, outside tracked
source. For separate agent/review checkouts, set the same absolute
`NVIM_REVIEW_DIR` in both processes (same repository only).

Writes are locked and append-only. Events have generated ID, UTC timestamp,
version 1, author, and type:
- `comment`: scope (`worktree`/`file`/`range`), body; file/range need path,
  ranges require line/end_line. Worktree steering has no file or line attachment.
- `reply`: thread ID, body.
- `status`: thread ID, `open`/`addressed`/`resolved`.

Use the CLI rather than editing JSONL. `archive-resolved` backs up the whole log
then removes resolved threads from the active log. Archives are recovery snapshots,
not logs to concatenate. Remove a stale `write.lock/` only after its writer has
stopped; back up and repair a truncated final record before further writes.

Tests (from `nvim/`): `nvim --headless -u NONE -l tests/review.lua`.
