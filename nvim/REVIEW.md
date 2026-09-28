# Local review comments (V0)

All implementation is Lua. Neovim provides both the editor UI and the headless
agent CLI. Restart Neovim after installing/changing the configuration.

## In Neovim

Use actual source buffers (`gf` from Diffview), not historical diff buffers.

| Key | Action |
| --- | --- |
| `Space rc` | Comment on cursor line, or visual selection's line range |
| `Space rC` | Comment on the entire file |
| `Space rv` | View comments covering the cursor line (including file comments) |
| `Space rl` | View current file's comments |
| `Space ra` | View all comments in this worktree's review log |

New comments and replies open a small Markdown split. The location is captured
at creation and displayed in the winbar. Type only your message. `:w` publishes
once and closes the split; `:q!` discards. Empty messages are rejected. On failure,
the buffer stays open so your text is not lost. Unsaved comments are not persisted.

Thread views are read-only Markdown. Move onto a thread, then:

- `r`: write a reply in a separate Markdown split; `:w` appends it.
- `s`: choose open, addressed, or resolved. Reopening is supported.
- Enter: jump to the source location in the other window.
- `R`: refresh after agent activity.
- `q`: close the view.

Commands and filters:

```vim
:ReviewComment
:30,35ReviewComment
:ReviewComment file
:ReviewComments line
:ReviewComments file open
:ReviewComments all
:ReviewComments all addressed
:ReviewComments all resolved
:ReviewRefresh
```

`all` means the entire selected review log, not every repository on the machine.
By default each worktree has its own log.

Unresolved comments get a ◆ gutter sign (warning colour for open, info colour
for addressed). Resolved comments have no sign. Default one-column sign gutters
expand to allow two signs alongside Gitsigns. Refresh occurs on buffer entry,
normal-mode text changes, writes, focus gain, and explicit `:ReviewRefresh`.
There is no background filesystem watcher yet.

## Location and version accuracy

Locations display as `./path/to/file:30-35`, relative to the worktree root.
File comments have no line suffix. UI comments capture HEAD SHA, a hash of the
whole buffer, and nearby source text. Unsaved text is allowed: SHA is historical
context, not an assertion that the buffer matches HEAD.

Range signs only render when the current buffer hash matches the captured hash.
After edits, comments remain visible in views but are not automatically relocated.
Source jumps and line filters use original line numbers (clamped on jump).
File comments remain visible regardless of content changes. Old-side comments,
rename tracking, and checkpoint-relative Gitsigns configuration are not implemented.

## Storage and sharing

Default path, resolved from the target worktree:

```sh
git rev-parse --path-format=absolute --git-path agent-review
```

The directory contains `events.jsonl`, a transient `write.lock/` directory, and
optional `archive/` snapshots. It is outside tracked source. No Markdown file is
persisted. The temporary Markdown buffers are views/editor inputs, not replicas
of the event log.

For separate agent and review checkouts, set **the same absolute directory** in
both environments before launching Neovim/the CLI:

```sh
export NVIM_REVIEW_DIR=/absolute/path/to/shared/agent-review
```

Shared logs should only connect checkouts of the same repository. Paths are
resolved against whichever checkout is viewing them; hashes prevent misleading
range signs on different versions.

## Agent CLI

Run from the target worktree. No plugins or user config are loaded:

```sh
CLI="$HOME/src/dotconfig/nvim/scripts/review.lua"
nvim --headless -u NONE -l "$CLI" path
nvim --headless -u NONE -l "$CLI" list open
nvim --headless -u NONE -l "$CLI" list all zj-session-picker/src/state.rs
nvim --headless -u NONE -l "$CLI" reply THREAD_ID /tmp/reply-body.md agent
nvim --headless -u NONE -l "$CLI" status THREAD_ID addressed agent
nvim --headless -u NONE -l "$CLI" status THREAD_ID resolved human
nvim --headless -u NONE -l "$CLI" append /tmp/event.json
```

Suggested agent instruction:

> Between substantial steps and before finishing, list open review threads.
> Read each thread, make the requested change or explain the issue, append a
> reply, and mark it addressed. Leave final resolution to the human. Use the
> CLI for writes; never edit or replace the JSONL directly.

## Event schema v1

Each line is one JSON object with `version: 1`, generated `id`, UTC `timestamp`,
`type`, and `author`. IDs are stable, opaque strings.

- `comment`: `path` (repo-relative), `scope` (`file` or `range`), `body`;
  ranges require integer `line` and `end_line`. Optional `sha`, `side`,
  `content_hash`, `context` (array of source lines), `context_start`.
- `reply`: `thread` (original comment ID), `body`.
- `status`: `thread`, `status` (`open`, `addressed`, `resolved`).

Comments begin open. Replies do not implicitly change status. Last status event
wins. New comments/replies are immutable; corrections are additional replies.
The CLI `append` accepts an event without generated fields, e.g.:

```json
{"type":"comment","author":"agent","path":"zj-session-picker/src/state.rs","scope":"file","body":"Please review the selection handling."}
```

Writers acquire a directory lock, reread/validate the log, then append a single
JSON line. Concurrent writers wait up to three seconds. Readers see atomic log
replacement during maintenance, but can encounter an incomplete append and
will report it rather than guessing. If a writer crashes, remove its stale
`write.lock/` only after confirming it is no longer running. Back up and repair
an incomplete final line before further writes. This is local-filesystem V0,
not a distributed or power-loss-durable database.

## Cleanup

Normal operations only append. Explicit maintenance:

```sh
nvim --headless -u NONE -l "$CLI" archive-resolved
```

Under the same lock, this first saves a **complete recovery snapshot** to
`archive/`, then atomically replaces the active log with unresolved threads and
all their events. Archives therefore may contain repeated unresolved history;
they are backups, not additional logs to concatenate. No archives are deleted
automatically. Archived threads are no longer available for replies in the
active UI/CLI. A stale reply gets an error instead of recreating a missing thread.

## Tests

From `nvim/`:

```sh
nvim --headless -u NONE -l tests/review.lua
```

Covers storage, validation, status/replies, compose save/discard, view actions,
gutter signs, archive pruning, concurrent CLI writes, and torn-write detection.
