# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## Reviewing changes

Restart Neovim after changing the config. Leader is Space.

| Key | Action |
| --- | --- |
| `<leader>gv` | Diffview: working tree against `main` |
| `<leader>gV` | Close Diffview |
| `<leader>ge` | Toggle Diffview file panel |
| `<leader>gH` | Current file history |
| `<leader>gw` | Worktree picker (`:Worktrees`) |

In Diffview: H/L retain LazyVim's previous/next buffer navigation (including in
file/history panels). Tab/Shift-Tab move between changed files, `]c`/`[c` between hunks,
`<leader>e` focuses the file panel, and `gf` opens the actual checked-out
file in the previous tab for normal editing/LSP navigation. Historical diff
buffers aren't a substitute for checking out a revision for LSP exploration.

Useful commands from the repository root:

```vim
:DiffviewOpen HEAD
:DiffviewOpen main...HEAD -- zj-session-picker/
:DiffviewFileHistory -- zj-session-picker/
:DiffviewOpen <base-sha>..<checkpoint-sha> -- zj-session-picker/
:DiffviewClose
```

`Space gv` and the worktree picker compare `main` to the working tree, including
committed and uncommitted changes. Repositories must have a local `main` branch.
Use bare `:DiffviewOpen` for the index comparison or pass an explicit revision.

`HEAD` includes staged and unstaged changes; `main...HEAD` shows committed
branch changes from the merge base. The two-SHA form compares exact checkpoints.
Diffview is not read-only: edits and staging actions affect the selected checkout.

The worktree picker lists existing worktrees for the current file's repository
(or cwd for non-file buffers). Enter closes the current Diffview, switches cwd to
the selected worktree, and opens its diff against `main` in the same Neovim. Existing buffers,
including unsaved edits, remain open and still refer to their original worktrees;
H/L can cycle through them. No terminal integration, copying commands, or
worktree creation/deletion is involved.

Only `main` exists initially. To add an optional exploration checkout:

```sh
cd ~/src/dotconfig
git worktree add -b review/explore ../dotconfig-review
```

This starts from HEAD, not uncommitted files. Neovim still uses the shared config
at `~/.config/nvim`. Checkpoint automation is not implemented.

## Review comments

See [REVIEW.md](REVIEW.md) for the JSONL model, agent CLI, sharing logs, and cleanup.

- `Space rc`: comment on cursor line or visually selected range.
- `Space rC`: comment on the entire file.
- `Space rv` / `Space rl` / `Space ra`: comments here / in file / in worktree.
- Comment/reply buffer: `:w` publishes, `:q!` discards.
- Thread view: `r` replies, `s` changes status, Enter jumps to source, `R` refreshes.
- `:ReviewComments all open` filters to open threads.

Use real source buffers (`gf` from Diffview). Unresolved comments get gutter
markers when their captured source matches the buffer; resolved threads stay
in history until explicitly archived.

Run picker tests from this directory:

```sh
nvim --headless -u NONE -l tests/worktrees.lua
```
