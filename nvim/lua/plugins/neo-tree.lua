local Util = require("lazyvim.util")

return {
  {
    "neo-tree.nvim",
    -- https://github.com/nvim-neo-tree/neo-tree.nvim/blob/54fe2a5f6f698094b34461a11370fcc29b8a4393/lua/neo-tree/defaults.lua#L442
    keys = {
      {
        "<leader>fe",
        function()
          require("neo-tree.command").execute({ toggle = true, dir = Util.root() })
        end,
        desc = "Explorer NeoTree (root dir)",
      },
      {
        "<leader>fE",
        function()
          require("neo-tree.command").execute({ toggle = true, dir = vim.loop.cwd() })
        end,
        desc = "Explorer NeoTree (cwd)",
      },
      { "<leader>e", "<leader>fe", desc = "Explorer NeoTree (root dir)", remap = true },
      { "<leader>E", "<leader>fE", desc = "Explorer NeoTree (cwd)", remap = true },
      {
        "<leader>ge",
        function()
          require("neo-tree.command").execute({ source = "git_status", toggle = true })
        end,
        desc = "Git explorer",
      },
    },
    opts = {
      window = {
        position = "float",
      },
      bind_to_cwd = false,
      filesystem = {
        filtered_items = {
          visible = false, -- when true, they will just be displayed differently than normal items
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_hidden = false, -- only works on Windows for hidden files/directories
          hide_by_name = {
            ".git",
          },
          hide_by_pattern = { -- uses glob style patterns
            "__pycache__",
            ".pytest_cache",
            ".mypy_cache",
            ".vscode",
            ".idea",
            ".ruff_cache",
          },
          always_show = { -- remains visible even if other settings would normally hide it
          },
          never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
            ".DS_Store",
            "thumbs.db",
          },
          never_show_by_pattern = { -- uses glob style patterns
          },
        },
        follow_current_file = {
          enabled = false, -- This will find and focus the file in the active buffer every time
          leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
        },
      },
    },
  },
}
