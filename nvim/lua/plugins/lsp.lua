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
}
