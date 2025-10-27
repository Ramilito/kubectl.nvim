-- Run with `nvim -u repro.lua`

vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

require("lazy.minit").repro({
	spec = {
		{
			"ramilito/kubectl.nvim",
			keys = {
				{ "K", '<cmd>lua require("kubectl").toggle({tab = true})<cr>', desc = "Join Toggle" },
			},
			-- version = "2.*",
			build = "cargo build --release",
			opts = {},
			dependencies = "saghen/blink.download",
		},
	},
})
