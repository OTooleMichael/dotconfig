-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
vim.keymap.set("n", "<leader>q", function()
  local buffers = vim.api.nvim_list_bufs()
  for _, buffer in ipairs(buffers) do
    local buf_name = vim.api.nvim_buf_get_name(buffer)
    if buf_name == "" then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
  end
end, { desc = "Close all unnamed buffers", remap = true })

vim.api.nvim_create_user_command("Fshell", function(opts)
  local command = table.concat(opts.fargs, " ")
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= "" then
    vim.cmd(":enew")
  end
  vim.cmd(": % ! " .. command)
end, { nargs = "*" })

vim.api.nvim_create_user_command("Fsh", function(opts)
  local command = table.concat(opts.fargs, " ")
  vim.cmd(":Fshell " .. command)
end, { nargs = "*" })

vim.api.nvim_create_user_command("Fscript", function(opts)
  local cwd = vim.fn.getcwd()
  local command = table.concat(opts.fargs, " ")
  local variants = { "/", "/scripts/" }
  for k, v in pairs(variants) do
    for k1, v1 in pairs({ "", ".sh" }) do
      local full_path = cwd .. v .. command .. v1
      local is_ok, is_readable = pcall(vim.fn.filereadable, full_path)
      if is_ok and is_readable == 1 then
        vim.cmd(":Fshell sh " .. full_path)
        return
      end
    end
  end
  print("Error: couldn't find script for command - " .. command)
end, { nargs = "*" })

vim.keymap.set("n", "<leader>wj", "<cmd>vertical resize -10<cr>", { desc = "Decrease window width", remap = true })
vim.keymap.set("n", "<leader>wk", "<cmd>vertical resize +10<cr>", { desc = "Increase window width", remap = true })
vim.keymap.set("i", "jj", "<Esc>")
vim.keymap.set("i", "kk", function()
  require("copilot.suggestion").accept()
end)
vim.keymap.set("i", "‘‘", function()
  require("copilot.suggestion").next()
end)
vim.keymap.set("i", "““", function()
  require("copilot.suggestion").prev()
end)
vim.keymap.set("i", "ø", function()
  require("copilot.suggestion").accept_word()
end)
vim.keymap.set("n", 'gs"', 'gsaiw"', { remap = true })
vim.keymap.set("n", "gs'", "gsaiw'", { remap = true })
vim.keymap.set("n", "<leader>o", "o<Esc>")
vim.keymap.set("n", "<leader>O", "O<Esc>")
vim.keymap.set("n", "<leader>rf", ":Fscript format<CR>")
vim.keymap.set("n", "<leader>rt", ":Fscript test<CR>")
vim.keymap.set("n", "<leader>gp", ":ChatGPT<CR>")
vim.keymap.set("v", "<leader>gp", ":ChatGPTEditWithInstructions<CR>")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true })
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true })
