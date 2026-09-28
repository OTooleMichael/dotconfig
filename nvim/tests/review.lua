-- Run from nvim/: nvim --headless -u NONE -l tests/review.lua
package.path = "./lua/?.lua;" .. package.path
local store = require("review.store")
local root = vim.fn.tempname() .. " review test"
vim.fn.mkdir(root, "p")
local function git(...)
  local r = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(r.code == 0, r.stderr)
end
git("init", "-q")
git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-qm", "init")
vim.fn.writefile({ "one", "two", "three" }, root .. "/source.txt")
vim.env.NVIM_REVIEW_DIR = nil
local ctx = store.context(root)
local event = store.anchor(ctx, "source.txt", 2, 3, "range", { "one", "two", "three" })
event.body = "Please change this\nsecond line"
local c = store.append(ctx, event)
store.append(ctx, { type = "reply", thread = c.id, author = "agent", body = "Done" })
store.append(ctx, { type = "status", thread = c.id, author = "agent", status = "addressed" })
local threads = store.threads(store.read(ctx))
assert(#threads == 1 and threads[1].status == "addressed" and #threads[1].replies == 1)
assert(store.location(c) == "./source.txt:2-3")
assert(not pcall(store.append, ctx, { type = "reply", thread = "missing", author = "agent", body = "bad" }))
assert(vim.fn.isdirectory(ctx.dir .. "/write.lock") == 0)

local ui = require("review.ui")
ui.setup()
vim.cmd.edit(vim.fn.fnameescape(root .. "/source.txt"))
local source = vim.api.nvim_get_current_buf()
ui.refresh()
local ns = vim.api.nvim_get_namespaces()["review-comments"]
assert(#vim.api.nvim_buf_get_extmarks(source, ns, 0, -1, {}) == 1)
vim.api.nvim_buf_set_lines(source, 0, 1, false, { "modified" })
ui.mark(source)
assert(#vim.api.nvim_buf_get_extmarks(source, ns, 0, -1, {}) == 0)
vim.api.nvim_buf_set_lines(source, 0, 1, false, { "one" })
vim.bo[source].modified = false
vim.api.nvim_win_set_cursor(0, { 1, 0 })
ui.view("line")
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("No matching comments", 1, true))
vim.cmd("quit")
ui.view("all", "resolved")
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("No matching comments", 1, true))
vim.cmd("quit")
vim.cmd("1,2ReviewComment")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Saved from editor" })
vim.cmd("write")
assert(#store.threads(store.read(ctx)) == 2)
vim.cmd("ReviewComment file")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Discard me" })
vim.cmd("quit!")
assert(#store.threads(store.read(ctx)) == 2)
ui.view("file")
assert(not vim.bo.modifiable)
local rendered = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(rendered:find("Saved from editor", 1, true))
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.fn.maparg("r", "n", false, true).callback()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Human reply" })
vim.cmd("write")
assert(#store.threads(store.read(ctx))[1].replies == 2)
local select = vim.ui.select
vim.ui.select = function(_, _, callback) callback("resolved") end
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.fn.maparg("s", "n", false, true).callback()
vim.ui.select = select
assert(store.threads(store.read(ctx))[1].status == "resolved")
vim.cmd("quit")
local backup = store.archive_resolved(ctx)
assert(vim.fn.filereadable(backup) == 1)
assert(#store.threads(store.read(ctx)) == 1)
-- Concurrent headless CLI writers must retain every reply.
local active = store.threads(store.read(ctx))[1].id
local cli = vim.fn.fnamemodify("scripts/review.lua", ":p")
local body = root .. "/reply.txt"
vim.fn.writefile({ "Concurrent agent reply" }, body)
local jobs = {}
for _ = 1, 4 do
  jobs[#jobs + 1] = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", cli,
    "reply", active, body }, { cwd = root, text = true })
end
for _, job in ipairs(jobs) do local result = job:wait(); assert(result.code == 0, result.stderr) end
assert(#store.threads(store.read(ctx))[1].replies == 4)
-- A torn write must block new appends, not concatenate more JSON onto it.
vim.fn.writefile({ '{"version":' }, ctx.log, "ab")
assert(not pcall(store.read, ctx))
vim.cmd("cd /tmp")
vim.fn.delete(root, "rf")
print("review tests passed")
