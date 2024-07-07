-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
DNVIM_COPY_FILE = "/tmp/dnvim_copy_watcher.txt"
WATCH_REGISTRIES = { "i" }

vim.api.nvim_create_autocmd("TextYankPost", { -- Create an autocommand for the "TextYankPost" event
  pattern = "*", -- Match any pattern
  group = DnvimGroup, -- Assign the autocommand to the "YankCopyGroup" group
  callback = function()
    local found = false
    for _, value in ipairs(WATCH_REGISTRIES) do
      if value == vim.v.event.regname then
        found = true
      end
    end
    if not found then
      return
    end
    local data = vim.v.event.regcontents
    local bin_loc = vim.fn.system("which pbcopy")
    if bin_loc ~= "" then
      vim.fn.system("pbcopy", data)
      return
    end
    vim.fn.writefile(data, DNVIM_COPY_FILE)
  end,
})
