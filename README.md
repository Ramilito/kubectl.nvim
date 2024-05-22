# kubectl.nvim
Opens a buffer that displays output of kubectl

![image](https://github.com/Ramilito/kubectl.nvim/assets/8473233/b60b9dca-8a52-4222-8b3e-a7483c3debfb)

## ✨ Features
- Navigate your cluster in a buffer, using hierarchy where possible e.g. deplyoment -> pod
- Colored output and highlighted errors
- Floating windows for contextual stuff such as pod_logs, pod_description

## ⚡️ Dependencies
- kubectl
  
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
return {
	{
		"ramilito/kubectl.nvim",
		keys = {
			{
				"<leader>k",
				function()
					require("kubectl").open()
				end,
				desc = "Kubectl",
			},
		},
		config = function()
			require("kubectl").setup()
		end,
	},
}

```

## Performance

### Startup

No startup impact since we load on demand.

## TODO
- Open in split
- Auto watch state
- Hints bar for shortcuts
- Integrate with tooling (such as kubesses or kubediff)

## Motivation
This plugins main purpose is to browse the kubernetes state using vim like navigation and keys, similar to oil.nvim for filebrowsing. I might add a way to act on the cluster (delete resources, ssh, edit) in the future, not sure yet.
