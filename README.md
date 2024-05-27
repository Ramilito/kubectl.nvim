# kubectl.nvim
Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.
<img width="1746" alt="image" src="https://github.com/Ramilito/kubectl.nvim/assets/8473233/c999a5cd-5a64-4787-b232-f2acffd247f2">

Note: This is still incomplete in that it doesn't handle all possible resources and I might change things up in the future.

## ✨ Features
- Navigate your cluster in a buffer, using hierarchy where possible (backspace for up, enter for down) e.g. root -> deplyoment -> pod -> container
- Colored output and smart highlighting
- Floating windows for contextual stuff such as logs, description, containers..
- Run custom commands e.g ```:Kubectl get configmaps -A```

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
- [x] Open in split
- [x] Exec into container
- [ ] Auto refresh state (should probably do async operations task first)
- [ ] Async operations
- [ ] Populate the g? help buffer
- [ ] Configuration
  - [ ] Optional hints
  - [ ] Optional or toggable context info
  - [ ] Bring your own colors
- [x] Hints bar for shortcuts
- [x] Node view
- [x] Services view
- [x] Pod view
- [x] Container viewn
- [x] Deployment view
- [x] Secrets view
- [ ] CRDS view
- [ ] Generic view for user commands
  - [x] Add barebones to use user commands
  - [ ] Add autocompletion
  - [ ] Add some smartness, figure out filetype based on command
- [ ] Integrate with tooling (such as kubesses or kubediff)

## Motivation
This plugins main purpose is to browse the kubernetes state using vim like navigation and keys, similar to oil.nvim for filebrowsing. I might add a way to act on the cluster (delete resources, ssh, edit) in the future, not sure yet.
