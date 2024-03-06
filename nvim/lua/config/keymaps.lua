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

local function stripWhitespace(str)
  return str:match("^%s*(.-)%s*$")
end

local function replaceRange(command, range_value)
  return command:gsub("@(%a+)", function(letter)
    if #letter ~= 1 then
      return "@" .. letter
    end
    local value = vim.fn.getreg(letter)
    if letter == "v" then
      value = range_value
    end
    return vim.fn.shellescape(value)
  end)
end

local function fshell_command(opts)
  local range_content = vim.fn.getline(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
  local range_value = table.concat(range_content, "\n")
  local command = stripWhitespace(table.concat(opts.fargs, " "))
  command = replaceRange(command, range_value)
  if command == "" then
    command = replaceRange(range_value, "")
  end
  print("Running: " .. command)

  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= "" then
    vim.cmd(":enew")
  end
  -- get the current active buffer
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "Running: ", command })
  local function handle_output(job_id, data, event)
    if data then
      vim.api.nvim_buf_set_lines(buffer, -1, -1, false, data)
    end
  end
  local job_id = vim.fn.jobstart(command, {
    on_stdout = handle_output,
    on_stderr = handle_output,
    stderr_buffered = true,
    stderr_buffer = buffer,
    stdout_buffered = true,
    stdout_buffer = buffer,
  })
  vim.api.nvim_buf_attach(buffer, false, {
    on_detach = function()
      vim.fn.jobstop(job_id)
    end,
  })
end

vim.api.nvim_create_user_command("Fshell", fshell_command, { range = true, nargs = "*" })
vim.api.nvim_create_user_command("Fsh", fshell_command, { range = true, nargs = "*" })

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

vim.keymap.set("n", "<leader>be", ":Tel buffers<CR>", { remap = true })
vim.keymap.set("n", "<leader>wT", "<C-w>T")
vim.keymap.set("n", "<leader>wj", "<C-w>j")
vim.keymap.set("n", "<leader>wk", "<C-w>k")
vim.keymap.set("n", "<leader>wh", "<C-w>h")
vim.keymap.set("n", "<leader>wl", "<C-w>l")

vim.keymap.set("n", "<leader>w<", "<cmd>vertical resize -10<cr>", { desc = "Decrease window width", remap = true })
vim.keymap.set("n", "<leader>w>", "<cmd>vertical resize +10<cr>", { desc = "Increase window width", remap = true })
vim.keymap.set("n", "<leader>w-", "<cmd>vertical resize -10<cr>", { desc = "Decrease window width", remap = true })
vim.keymap.set("n", "<leader>w+", "<cmd>vertical resize +10<cr>", { desc = "Increase window width", remap = true })
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
vim.keymap.set("v", "<leader>re", ":Fsh<CR>")
vim.keymap.set("n", "<leader>re", function()
  local current_line = vim.fn.getline(".")
  vim.cmd(":Fsh " .. current_line)
end)
vim.keymap.set("n", "<leader>gp", ":ChatGPT<CR>")
vim.keymap.set("v", "<leader>gp", ":ChatGPTEditWithInstructions<CR>")

vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true })
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true })
