local M = {}
local store = require("review.store")
local ns = vim.api.nvim_create_namespace("review-comments")
local views = {}

local function guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
  end
end

local function source()
  local file = vim.api.nvim_buf_get_name(0)
  assert(vim.bo.buftype == "" and file ~= "", "Open a real source file first (gf from Diffview)")
  local ctx = store.context(vim.fn.fnamemodify(file, ":h"))
  local path = file:sub(#ctx.root + 2)
  assert(file:sub(1, #ctx.root + 1) == ctx.root .. "/", "File outside worktree")
  return ctx, path
end

local function scratch(title, editable)
  vim.cmd("botright 12new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, "review://" .. buf .. "/" .. tostring(vim.uv.hrtime()) .. ".md")
  vim.bo[buf].buftype = editable and "acwrite" or "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.wo.winbar = title:gsub("%%", "%%%%")
  return buf
end

local function compose(ctx, event, title)
  local buf = scratch(title .. " | :w publish · :q! discard", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  vim.bo[buf].modified = false
  local saved = false
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = guard(function()
      assert(not saved, "Already published")
      event.body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert(vim.trim(event.body) ~= "", "Empty comment: write some text or :q! to discard")
      local e = store.append(ctx, event)
      saved = true
      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
      M.refresh()
      vim.notify("Published " .. e.id)
    end),
  })
end

M.comment = guard(function(opts)
  assert(opts.args == "" or opts.args == "file", "Usage: [range]ReviewComment [file]")
  local ctx, path = source()
  local scope = opts.args == "file" and "file" or "range"
  local event = store.anchor(ctx, path, opts.line1, opts.line2, scope,
    vim.api.nvim_buf_get_lines(0, 0, -1, false))
  compose(ctx, event, store.location(event))
end)

local function matches(thread, spec)
  local c = thread.comment
  if spec.status and thread.status ~= spec.status then return false end
  if spec.path and c.path ~= spec.path then return false end
  return not spec.line or c.scope == "file" or (c.line <= spec.line and c.end_line >= spec.line)
end

local function render(buf)
  local view = views[buf]
  local lines, targets = { "# Review comments", "", "r: reply | s: status | <Enter>: source | R: refresh | q: close", "" }, {}
  for _, thread in ipairs(store.threads(store.read(view.ctx))) do
    if matches(thread, view.spec) then
      local start = #lines + 1
      local c = thread.comment
      vim.list_extend(lines, { "## " .. thread.id .. " · " .. thread.status, store.location(c),
        "Author: " .. c.author .. " · " .. c.timestamp, "HEAD context: " .. (c.sha or "unknown"), "" })
      vim.list_extend(lines, vim.split(c.body, "\n", { plain = true }))
      for _, reply in ipairs(thread.replies) do
        vim.list_extend(lines, { "", "### " .. reply.author .. " · " .. reply.timestamp, "" })
        vim.list_extend(lines, vim.split(reply.body, "\n", { plain = true }))
      end
      lines[#lines + 1] = ""
      for i = start, #lines do targets[i] = thread end
    end
  end
  if #lines == 4 then lines[#lines + 1] = "No matching comments." end
  view.targets = targets
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

M.view = guard(function(filter, status)
  local ctx, path, line
  if filter == "all" then
    if vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= "" then ctx = source()
    else ctx = store.context() end
  else
    ctx, path = source()
    if filter == "line" then line = vim.api.nvim_win_get_cursor(0)[1] end
  end
  local buf = scratch("Review · " .. filter .. (status and " · " .. status or ""), false)
  views[buf] = { ctx = ctx, spec = { path = path, line = line, status = status } }
  local function selected()
    return assert(views[buf].targets[vim.api.nvim_win_get_cursor(0)[1]], "Move onto a comment thread")
  end
  local function map(key, fn) vim.keymap.set("n", key, guard(fn), { buffer = buf, silent = true }) end
  map("r", function()
    local thread = selected()
    compose(ctx, { type = "reply", thread = thread.id, author = "human" }, "Reply to " .. thread.id)
  end)
  map("s", function()
    local thread = selected()
    vim.ui.select({ "open", "addressed", "resolved" }, { prompt = "Thread status" }, guard(function(value)
      if value then
        store.append(ctx, { type = "status", thread = thread.id, author = "human", status = value })
        M.refresh()
      end
    end))
  end)
  map("<CR>", function()
    local c = selected().comment
    vim.cmd("wincmd p")
    vim.cmd.edit(vim.fn.fnameescape(ctx.root .. "/" .. c.path))
    vim.api.nvim_win_set_cursor(0, { math.min(c.line or 1, vim.api.nvim_buf_line_count(0)), 0 })
  end)
  map("R", function() M.refresh() end)
  map("q", function() vim.api.nvim_buf_delete(buf, { force = true }) end)
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = buf, once = true, callback = function() views[buf] = nil end })
  render(buf)
end)

function M.mark(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if vim.bo[buf].buftype ~= "" then return end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return end
  local ok, ctx = pcall(store.context, vim.fn.fnamemodify(file, ":h"))
  if not ok or file:sub(1, #ctx.root + 1) ~= ctx.root .. "/" then return end
  local count = vim.api.nvim_buf_line_count(buf)
  local hash = vim.fn.sha256(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
  for _, thread in ipairs(store.threads(store.read(ctx))) do
    local c = thread.comment
    -- Don't silently pin a historical range to unrelated current text.
    if c.path == file:sub(#ctx.root + 2) and thread.status ~= "resolved"
      and (c.scope == "file" or c.content_hash == hash) then
      local row = (c.line or 1) - 1
      if row < count then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          if vim.wo[win].signcolumn == "yes" or vim.wo[win].signcolumn == "auto" then
            vim.wo[win].signcolumn = "auto:2" -- Leave room alongside Gitsigns.
          end
        end
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
          sign_text = "◆", sign_hl_group = thread.status == "addressed" and "DiagnosticInfo" or "DiagnosticWarn",
          priority = 5,
        })
      end
    end
  end
end

function M.refresh()
  for buf in pairs(views) do if vim.api.nvim_buf_is_valid(buf) then render(buf) end end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.mark(buf) end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("ReviewComments", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged" }, {
    group = group, callback = guard(function(ev) M.mark(ev.buf) end),
  })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = guard(M.refresh) })
  vim.api.nvim_create_user_command("ReviewComment", M.comment, {
    range = true, nargs = "?", complete = function() return { "file" } end,
  })
  vim.api.nvim_create_user_command("ReviewComments", function(opts)
    local filter, status = opts.fargs[1] or "file", opts.fargs[2]
    if not vim.tbl_contains({ "line", "file", "all" }, filter)
      or (status and not vim.tbl_contains({ "open", "addressed", "resolved" }, status)) then
      vim.notify("Usage: ReviewComments [line|file|all] [open|addressed|resolved]", vim.log.levels.ERROR)
      return
    end
    M.view(filter, status)
  end, { nargs = "*" })
  vim.api.nvim_create_user_command("ReviewRefresh", guard(M.refresh), {})
end

return M
