# kubectl.nvim
Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.
<img width="1746" alt="image" src="https://github.com/Ramilito/kubectl.nvim/assets/8473233/c999a5cd-5a64-4787-b232-f2acffd247f2">

Note: This is still incomplete in that it doesn't handle all possible resources and I might change things up in the future.

## ✨ Features
- Navigate your cluster in a buffer, using hierarchy where possible (backspace for up, enter for down) e.g. root -> deplyoment -> pod -> container
- Colored output and smart highlighting
- Floating windows for contextual stuff such as logs, description, containers..

## ⚡️ Dependencies
- kubectl
  
## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

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

## ⚙️ Configuration

### Setup
```lua
{
  TBD
}
```

## Performance

### Startup

No startup impact since we load on demand.

## TODO
[x] Open in split
[ ] Auto refresh state
[ ] Configuration, e.g don't display hints or context
[x] Hints bar for shortcuts
[x] Node view
[x] Services view
[x] Pod view
[x] Container view
[x] Deployment view
[x] Secrets view
[ ] CRDS view
[ ] Generic view for dynamic commands
[ ] Integrate with tooling (such as kubesses or kubediff)

## Motivation
This plugins main purpose is to browse the kubernetes state using vim like navigation and keys, similar to oil.nvim for filebrowsing. I might add a way to act on the cluster (delete resources, ssh, edit) in the future, not sure yet.
