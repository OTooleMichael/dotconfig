return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" }, -- optional, for icons
  cmd = "FzfLua",
  keys = {
    { "<leader>ff", desc = "Fzf: Find files" },
    { "<leader>fF", desc = "Fzf: Find all files" },
    { "<leader>f/", desc = "Fzf: Live grep (all)" },
  },
  config = function()
    local fzf = require("fzf-lua")

    -- <leader>ff: regular files
    vim.keymap.set("n", "<leader>ff", function()
      fzf.git_files()
    end, { desc = "Fzf: Find files" })

    -- <leader>fF: hidden + ignored
    vim.keymap.set("n", "<leader>fF", function()
      fzf.files({ cmd = "rg --files --hidden --no-ignore --follow" })
    end, { desc = "Fzf: Find all files (hidden + ignored)" })

    -- <leader>f/: live grep including hidden + ignored
    vim.keymap.set("n", "<leader>f/", function()
      fzf.live_grep_glob({
        rg_opts = "rg --color=never --no-heading --with-filename --line-number --column --smart-case -u",
      })
    end, { desc = "Fzf: Live grep (all)" })
  end,
}
