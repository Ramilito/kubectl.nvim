# kubectl.nvim
Opens a buffer that displays output of kubectl


## ✨ Features
- Navigate your cluster in a buffer, using hierarchy where possible e.g. deplyoment -> pod
- Colored output and highlighted errors


## ⚡️ Dependencies
- None so far
  
## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
	{
		"ramilito/kubectl.nvim",
		dir = "~/workspace/mine/kubectl.nvim/",
		keys = {
			{
				"<leader>k",
				function()
					require("kubectl").open()
				end,
				desc = "kgpa",
			},
		},
		config = function()
			require("kubectl").setup()
		end,
	},
}
```

## ⚙️ Configuration

### Setup
```lua
{

}
```

## Performance

### Startup

No startup impact since we load on demand.

## TODO
- Open in split
- Auto watch state
- Integrate with tooling (such as kubesses or kubediff)

## Motivation
This plugin aims to help people move away from the tabline way of working but still need to orient them selves when working with multiple files by giving context.
The features are inspired by VSCode behaviour, some code is borrowed from bufferline, thanks for that 🙏.
