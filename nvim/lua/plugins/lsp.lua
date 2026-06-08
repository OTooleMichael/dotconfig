return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = {
        enabled = false,
      },
      servers = {
        basedpyright = {
          analysis = {
            typeCheckingMode = "standard",
          },
        },
      },
    },
  },
  {
    "mrcjkb/rustaceanvim",
    opts = {
      server = {
        -- Only attach when Cargo.toml exists in the tree; returning nil blocks startup
        root_dir = function(fname)
          local cargo = vim.fs.find("Cargo.toml", { path = fname, upward = true })[1]
          return cargo and vim.fs.dirname(cargo) or nil
        end,
        settings = {
          ["rust-analyzer"] = {
            cargo = { autoreload = false },
            checkOnSave = { enable = false },
          },
        },
      },
    },
  },
}
