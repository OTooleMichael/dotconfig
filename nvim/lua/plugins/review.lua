return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    opts = {
      keymaps = {
        view = { { "n", "<leader>b", false } },
        file_panel = { { "n", "L", false }, { "n", "<leader>b", false } },
        file_history_panel = { { "n", "L", false }, { "n", "<leader>b", false } },
      },
    },
    keys = {
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree" },
      { "<leader>gV", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
      { "<leader>ge", "<cmd>DiffviewToggleFiles<cr>", desc = "Diffview: toggle file panel" },
      { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: current file history" },
    },
  },
  {
    "ibhagwan/fzf-lua",
    keys = {
      {
        "<leader>gw",
        function()
          require("config.worktrees").pick()
        end,
        desc = "Git worktrees (switch and review)",
      },
    },
    init = function()
      require("review.ui").setup()
      vim.keymap.set({ "n", "x" }, "<leader>rc", ":ReviewComment<cr>", { desc = "Review: comment on line/range" })
      vim.keymap.set("n", "<leader>rC", "<cmd>ReviewComment file<cr>", { desc = "Review: comment on file" })
      vim.keymap.set("n", "<leader>rv", "<cmd>ReviewComments line<cr>", { desc = "Review: comments here" })
      vim.keymap.set("n", "<leader>rl", "<cmd>ReviewComments file<cr>", { desc = "Review: file comments" })
      vim.keymap.set("n", "<leader>ra", "<cmd>ReviewComments all<cr>", { desc = "Review: worktree comments" })
      vim.api.nvim_create_user_command("Worktrees", function()
        require("config.worktrees").pick()
      end, { desc = "Switch to a Git worktree and open its diff" })
    end,
  },
}
