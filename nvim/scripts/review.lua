-- nvim --headless -u NONE -l /absolute/path/to/scripts/review.lua <command> ...
local script = debug.getinfo(1, "S").source:sub(2)
local base = vim.fn.fnamemodify(script, ":p:h:h")
package.path = base .. "/lua/?.lua;" .. package.path
local store = require("review.store")
local function main()
  local command = arg[1] or "help"
  if command == "help" then
    print([[Run from the target worktree. NVIM_REVIEW_DIR can select a shared absolute directory.
commands:
  path                              Print JSONL path
  archive-resolved                  Snapshot log, then prune resolved threads
  list [all|open|addressed|resolved] [relative-file]
  append <event.json>                Append validated comment/reply/status (author required)
  reply <thread-id> <body-file> [author]
  status <thread-id> <open|addressed|resolved> [author]

Replies read UTF-8 text from a file, not shell-interpolated text.
append generates version, ID and timestamp. Do not edit events.jsonl directly.
Comment fields: type=comment, author, path, scope=file|range, body;
range additionally requires line and end_line. Optional sha/content_hash/context.
Reply fields: type=reply, author, thread, body.
Status fields: type=status, author, thread, status.]])
    return
  end
  local ctx = store.context()
  if command == "archive-resolved" then print(store.archive_resolved(ctx))
  elseif command == "path" then print(ctx.log)
  elseif command == "list" then
    local status = arg[2] or "all"
    assert(vim.tbl_contains({ "all", "open", "addressed", "resolved" }, status), "Invalid status")
    for _, t in ipairs(store.threads(store.read(ctx))) do
      if (status == "all" or t.status == status) and (not arg[3] or t.comment.path == arg[3]:gsub("^%./", "")) then
        print("## " .. t.id .. " · " .. t.status .. "\n" .. store.location(t.comment))
        print(t.comment.author .. ": " .. t.comment.body)
        for _, r in ipairs(t.replies) do print("\n" .. r.author .. ": " .. r.body) end
        print("")
      end
    end
  elseif command == "append" then
    assert(arg[2], "Expected event JSON file")
    print(vim.json.encode(store.append(ctx, vim.json.decode(table.concat(vim.fn.readfile(arg[2]), "\n")))))
  elseif command == "reply" then
    assert(arg[2] and arg[3], "Expected thread ID and body file")
    print(vim.json.encode(store.append(ctx, { type = "reply", thread = arg[2], author = arg[4] or "agent",
      body = table.concat(vim.fn.readfile(arg[3]), "\n") })))
  elseif command == "status" then
    print(vim.json.encode(store.append(ctx, { type = "status", thread = arg[2], author = arg[4] or "agent", status = arg[3] })))
  else error("Unknown command: " .. command) end
end
local ok, err = pcall(main)
if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit 1") end
