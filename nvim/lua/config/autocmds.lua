-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
local yank_group = vim.api.nvim_create_augroup("YankCopyGroup", { clear = true }) -- Create an autocommand group named "YankCopyGroup" and clear any existing autocommands in the group
local yank_copy_regname_list = { "p" }

local function isStringInTable(target, stringTable)
  for _, str in ipairs(stringTable) do
    if str == target then
      return true
    end
  end
  return false
end

vim.api.nvim_create_autocmd("TextYankPost", { -- Create an autocommand for the "TextYankPost" event
  pattern = "*", -- Match any pattern
  group = yank_group, -- Assign the autocommand to the "YankCopyGroup" group
  callback = function()
    local event = vim.v.event -- Get the event information
    if not isStringInTable(event.regname, yank_copy_regname_list) then
      return -- Exit the function if the register name is not "p"
    end

    local bin_loc = vim.fn.system("which pbcopy")
    if bin_loc ~= "" then
      vim.fn.system("pbcopy", event.regcontents)
      return
    end

    vim.fn.writefile(event.regcontents, "/tmp/copy.txt") -- Write the contents of the register "p" to the file "/tmp/copy.txt"
  end,
})
