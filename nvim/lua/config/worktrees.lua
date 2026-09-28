local M = {}

-- -z keeps paths containing spaces, quotes, or newlines unambiguous.
function M.parse(output)
  local worktrees, current = {}, nil
  for field in output:gmatch("([^%z]+)") do
    local path = field:match("^worktree (.*)$")
    if path then
      current = { path = path }
      table.insert(worktrees, current)
    elseif current then
      if field:match("^branch ") then
        current.branch = field:sub(8):gsub("^refs/heads/", "")
      elseif field:match("^HEAD ") then
        current.sha = field:sub(6)
      elseif field == "bare" then
        current.bare = true
      elseif field:match("^prunable") then
        current.prunable = true
      end
    end
  end
  return worktrees
end

function M.open(worktree)
  if vim.fn.isdirectory(worktree.path) ~= 1 then
    vim.notify("Worktree directory no longer exists: " .. worktree.path, vim.log.levels.ERROR)
    return
  end
  local lib = package.loaded["diffview.lib"]
  if lib and lib.get_current_view() then
    vim.cmd("DiffviewClose")
  end
  -- Keep old buffers (including unsaved edits), but don't let an old file's
  -- project root determine the new diff or file picker's repository.
  vim.cmd("hide enew")
  vim.cmd.cd(vim.fn.fnameescape(worktree.path))
  vim.cmd("DiffviewOpen main")
end

function M.pick()
  -- Prefer the current source file's repository, falling back to the window cwd.
  local file = vim.api.nvim_buf_get_name(0)
  local cwd = vim.fn.getcwd()
  if vim.bo.buftype == "" and file ~= "" then
    cwd = vim.fn.fnamemodify(file, ":h")
  end
  local result = vim.system({ "git", "-C", cwd, "worktree", "list", "--porcelain", "-z" }, { text = false }):wait()
  if result.code ~= 0 then
    vim.notify("Cannot list worktrees: " .. (result.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local entries, lookup = {}, {}
  for _, worktree in ipairs(M.parse(result.stdout)) do
    if not worktree.bare and not worktree.prunable then
      local branch = worktree.branch or ("detached @ " .. (worktree.sha or "?"):sub(1, 8))
      -- Display escaped control characters; retain the original path in the lookup.
      local label = string.format("%d  %s  %s", #entries + 1, branch, vim.fn.strtrans(worktree.path))
      table.insert(entries, label)
      lookup[label] = worktree
    end
  end
  if #entries == 0 then
    vim.notify("No usable worktrees found", vim.log.levels.WARN)
    return
  end
  require("fzf-lua").fzf_exec(entries, {
    prompt = "Worktrees> ",
    header = "enter: switch worktree and open diff (existing buffers retained)",
    actions = {
      ["default"] = function(selected)
        if selected and lookup[selected[1]] then
          M.open(lookup[selected[1]])
        end
      end,
    },
  })
end

return M
