local M = {}

local function git(root, ...)
  local result = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

function M.context(path)
  local root = git(path or vim.fn.getcwd(), "rev-parse", "--show-toplevel")
  local dir = vim.env.NVIM_REVIEW_DIR
  if not dir or dir == "" then
    dir = git(root, "rev-parse", "--path-format=absolute", "--git-path", "agent-review")
  end
  assert(dir:sub(1, 1) == "/", "NVIM_REVIEW_DIR must be absolute")
  return { root = root, dir = dir, log = dir .. "/events.jsonl" }
end

function M.read(ctx)
  if vim.fn.filereadable(ctx.log) == 0 then return {} end
  local events, ids = {}, {}
  local lines = vim.fn.readfile(ctx.log, "b")
  assert(#lines == 0 or lines[#lines] == "", "Incomplete final JSONL record; repair the log before writing")
  if lines[#lines] == "" then table.remove(lines) end
  for i, line in ipairs(lines) do
    local ok, event = pcall(vim.json.decode, line)
    assert(ok and type(event) == "table" and event.version == 1 and type(event.id) == "string",
      "Invalid review event at line " .. i)
    assert(not ids[event.id], "Duplicate event ID: " .. event.id)
    ids[event.id] = true
    events[#events + 1] = event
  end
  return events
end

function M.threads(events)
  local list, lookup = {}, {}
  for _, e in ipairs(events) do
    if e.type == "comment" then
      local thread = { id = e.id, comment = e, replies = {}, status = "open" }
      list[#list + 1], lookup[e.id] = thread, thread
    elseif e.type == "reply" or e.type == "status" then
      local thread = assert(lookup[e.thread], "Missing thread: " .. tostring(e.thread))
      if e.type == "reply" then
        thread.replies[#thread.replies + 1] = e
      else
        thread.status = e.status
      end
    else
      error("Unknown event type: " .. tostring(e.type))
    end
  end
  return list, lookup
end

local function with_lock(ctx, fn)
  vim.fn.mkdir(ctx.dir, "p")
  local lock = ctx.dir .. "/write.lock"
  local acquired = vim.wait(3000, function() return vim.uv.fs_mkdir(lock, 448) ~= nil end, 25)
  assert(acquired, "Review log busy: " .. lock .. " (remove only if its writer has stopped)")
  local ok, result = xpcall(fn, debug.traceback)
  vim.uv.fs_rmdir(lock)
  assert(ok, result)
  return result
end

local function validate_comment(e)
  assert(vim.tbl_contains({ "worktree", "file", "range" }, e.scope), "scope must be worktree, file or range")
  if e.scope == "worktree" then
    assert(e.path == nil and e.line == nil and e.end_line == nil, "worktree comments have no file/range")
    return
  end
  assert(type(e.path) == "string" and e.path ~= "" and not e.path:match("^/")
    and not e.path:match("^%.%./") and not e.path:find("/../", 1, true), "relative path required")
  if e.scope ~= "range" then return end
  assert(type(e.line) == "number" and type(e.end_line) == "number"
    and e.line >= 1 and e.line % 1 == 0 and e.end_line >= e.line and e.end_line % 1 == 0, "invalid range")
end

function M.append(ctx, event)
  return with_lock(ctx, function()
    local _, threads = M.threads(M.read(ctx))
    local e = vim.deepcopy(event)
    assert(type(e.author) == "string" and e.author ~= "", "author required")
    if e.type == "comment" then
      validate_comment(e)
    else
      assert(threads[e.thread], "Unknown thread: " .. tostring(e.thread))
      assert(e.type == "reply" or e.type == "status", "invalid event type")
      if e.type == "status" then
        assert(vim.tbl_contains({ "open", "addressed", "resolved" }, e.status), "invalid status")
      end
    end
    if e.type ~= "status" then
      assert(type(e.body) == "string" and vim.trim(e.body) ~= "", "empty comment")
    end
    e.version = 1
    e.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    e.id = vim.fn.sha256(tostring(vim.uv.hrtime()) .. vim.fn.getpid() .. vim.json.encode(e)):sub(1, 20)
    assert(vim.fn.writefile({ vim.json.encode(e) }, ctx.log, "a") == 0, "Could not append event")
    return e
  end)
end

-- Explicit maintenance only. Archive a complete recovery snapshot before
-- atomically replacing the active log with unresolved threads and their events.
function M.archive_resolved(ctx)
  return with_lock(ctx, function()
    local events = M.read(ctx)
    local _, threads = M.threads(events)
    local kept, removed = {}, 0
    for _, e in ipairs(events) do
      local thread = threads[e.type == "comment" and e.id or e.thread]
      if thread.status == "resolved" then removed = removed + 1
      else kept[#kept + 1] = vim.json.encode(e) end
    end
    if removed == 0 then return "No resolved threads" end
    local archive = ctx.dir .. "/archive"
    vim.fn.mkdir(archive, "p")
    local name = tostring(vim.uv.hrtime()) .. "-" .. vim.fn.getpid()
    local backup = archive .. "/" .. name .. ".jsonl"
    assert(vim.uv.fs_copyfile(ctx.log, backup), "Could not archive log")
    local temp = ctx.dir .. "/events-" .. name .. ".tmp"
    assert(vim.fn.writefile(kept, temp) == 0, "Could not write compacted log")
    assert(vim.uv.fs_rename(temp, ctx.log), "Could not replace log; original and archive retained")
    return backup
  end)
end

function M.location(comment)
  if comment.scope == "worktree" then return "./ (worktree)" end
  return "./" .. comment.path .. (comment.scope == "file" and "" or
    (":" .. comment.line .. (comment.end_line == comment.line and "" or "-" .. comment.end_line)))
end

function M.anchor(ctx, path, first, last, scope, lines)
  local sha = git(ctx.root, "rev-parse", "HEAD")
  return {
    type = "comment", author = "human", path = path, scope = scope,
    line = scope == "range" and first or nil, end_line = scope == "range" and last or nil,
    sha = sha, side = "new", content_hash = vim.fn.sha256(table.concat(lines, "\n")),
    -- SHA is context, not a claim that an unsaved buffer equals HEAD.
    context = scope == "range" and vim.list_slice(lines, math.max(1, first - 3), math.min(#lines, last + 3)) or nil,
    context_start = scope == "range" and math.max(1, first - 3) or nil,
  }
end

return M
