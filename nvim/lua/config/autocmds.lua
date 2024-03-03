-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
local yank_group = vim.api.nvim_create_augroup("YankCopyGroup", { clear = true }) -- Create an autocommand group named "YankCopyGroup" and clear any existing autocommands in the group

vim.api.nvim_create_autocmd("TextYankPost", { -- Create an autocommand for the "TextYankPost" event
  pattern = "*", -- Match any pattern
  group = yank_group, -- Assign the autocommand to the "YankCopyGroup" group
  callback = function() -- Define the callback function for the autocommand
    local e = vim.v.event -- Get the event information
    if e.regname ~= "p" then -- Check if the register name is not "p"
      return -- Exit the function if the register name is not "p"
    end
    vim.fn.writefile(e.regcontents, "/tmp/copy.txt") -- Write the contents of the register "p" to the file "/tmp/copy.txt"
  end,
})
