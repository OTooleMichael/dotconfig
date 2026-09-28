-- nvim --headless -u NONE -l /absolute/path/to/scripts/review.lua <command> ...
local script = debug.getinfo(1, "S").source:sub(2)
local base = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.runtimepath:prepend(base)
package.path = base .. "/lua/?.lua;" .. package.path
local store = require("review.store")

local function help()
  print([[Run from the target worktree; NVIM_REVIEW_DIR overrides the log directory.
  path                              Print JSONL path
  snapshot                          JSON on stdout: root, log, events, threads
  archive-resolved                  Snapshot log, then prune resolved threads
  list [all|open|addressed|resolved] [relative-file]
  append <event.json>                Append comment/reply/status; author required
  reply <thread-id> <body-file> [author]
  status <thread-id> <open|addressed|resolved> [author]

Use the CLI for writes, not direct JSONL edits. Replies/status default to author=agent.
comment: type, author, scope=worktree|file|range, body; file/range need path,
ranges also need line/end_line. Worktree steering has no path or lines.
reply: type, author, thread, body. status: type, author, thread, status.
IDs, timestamps and schema version are generated.]])
end

local function read_text(path)
  assert(path, "Expected a file path")
  return table.concat(vim.fn.readfile(path), "\n")
end

local function publish(ctx, event)
  print(vim.json.encode(store.append(ctx, event)))
end

local function matches(thread, status, path)
  if status ~= "all" and thread.status ~= status then return false end
  if path and thread.comment.path ~= path then return false end
  return true
end

local function print_thread(thread)
  print("## " .. thread.id .. " · " .. thread.status .. "\n" .. store.location(thread.comment))
  print(thread.comment.author .. ": " .. thread.comment.body)
  for _, reply in ipairs(thread.replies) do print("\n" .. reply.author .. ": " .. reply.body) end
  print("")
end

local commands = {}

function commands.snapshot(ctx)
  local events = store.read(ctx)
  io.stdout:write(vim.json.encode({
    version = 1, root = ctx.root, log = ctx.log, events = events, threads = store.threads(events),
  }) .. "\n")
end

commands["archive-resolved"] = function(ctx) print(store.archive_resolved(ctx)) end
function commands.path(ctx) print(ctx.log) end

function commands.list(ctx)
  local status = arg[2] or "all"
  assert(vim.tbl_contains({ "all", "open", "addressed", "resolved" }, status), "Invalid status")
  local path = arg[3] and arg[3]:gsub("^%./", "")
  for _, thread in ipairs(store.threads(store.read(ctx))) do
    if matches(thread, status, path) then print_thread(thread) end
  end
end

function commands.append(ctx)
  publish(ctx, vim.json.decode(read_text(arg[2])))
end

function commands.reply(ctx)
  assert(arg[2] and arg[3], "Expected thread ID and body file")
  publish(ctx, { type = "reply", thread = arg[2], author = arg[4] or "agent", body = read_text(arg[3]) })
end

function commands.status(ctx)
  assert(arg[2] and arg[3], "Expected thread ID and status")
  publish(ctx, { type = "status", thread = arg[2], author = arg[4] or "agent", status = arg[3] })
end

local function main()
  local name = arg[1] or "help"
  if name == "help" then return help() end
  local command = assert(commands[name], "Unknown command: " .. name)
  command(store.context())
end

local ok, err = pcall(main)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
