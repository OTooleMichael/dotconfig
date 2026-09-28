-- From nvim/: nvim --headless -u NONE -l tests/worktrees.lua
package.path = "./lua/?.lua;" .. package.path
local worktrees = require("config.worktrees")
local parsed = worktrees.parse(table.concat({
  "worktree /tmp/main checkout", "HEAD abc123", "branch refs/heads/main", "",
  "worktree /tmp/review\ncheckout", "HEAD def456", "detached", "",
  "worktree /tmp/bare", "bare", "",
  "worktree /tmp/missing", "HEAD fed321", "prunable gitdir file points to non-existent location", "",
}, "\0") .. "\0")
assert(#parsed == 4)
assert(parsed[1].path == "/tmp/main checkout" and parsed[1].branch == "main")
assert(parsed[2].path == "/tmp/review\ncheckout" and parsed[2].branch == nil)
assert(parsed[2].sha == "def456")
assert(parsed[3].bare and parsed[4].prunable)

local open = worktrees.open
local called = false
package.loaded["fzf-lua"] = {
  fzf_exec = function(entries, opts)
    called = true
    assert(#entries >= 1)
    assert(type(opts.actions.default) == "function")
    local selected
    worktrees.open = function(wt)
      selected = wt
    end
    opts.actions.default({ entries[1] })
    assert(selected and vim.fn.isdirectory(selected.path) == 1)
    opts.actions.default({}) -- Cancellation must be harmless.
  end,
}
worktrees.pick()
assert(called, "Expected picker to receive real Git worktrees")
-- Exercise switching without loading plugins or launching external processes.
local original_cwd = vim.fn.getcwd()
local target = vim.fn.tempname() .. " worktree with spaces"
vim.fn.mkdir(target, "p")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved review notes" })
local dirty = vim.api.nvim_get_current_buf()
local closed, opened = false, false
package.loaded["diffview.lib"] = { get_current_view = function() return {} end }
vim.api.nvim_create_user_command("DiffviewClose", function() closed = true end, {})
vim.api.nvim_create_user_command("DiffviewOpen", function()
  opened = true
  assert(closed)
  assert(vim.fn.getcwd() == vim.uv.fs_realpath(target))
  assert(vim.api.nvim_buf_get_name(0) == "")
end, {})
open({ path = target })
assert(opened)
assert(vim.api.nvim_buf_is_valid(dirty) and vim.bo[dirty].modified)
assert(vim.api.nvim_buf_get_lines(dirty, 0, -1, false)[1] == "unsaved review notes")
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(target, "d")
print("worktree tests passed")
