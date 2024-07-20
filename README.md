# kubectl.nvim
Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.
<img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/1d624569-b6d9-4c2e-8037-7727352ad822" width="1700px">

## ✨ Features
<details>
  <summary>Navigate your cluster in a buffer, using hierarchy where possible (backspace for up, enter for down) e.g. root -> deplyoment -> pod -> container
</summary>
  <img src="https://github.com/user-attachments/assets/422fa6e3-1e3d-4efc-85a2-e6087bdd8815" width="700px">
</details>
<details>
  <summary>Colored output and smart highlighting</summary>
  <img src="https://github.com/user-attachments/assets/d9b34465-7644-486a-8ad2-8d4ae960a8f3" width="700px">
</details>
<details>
  <summary>Floating windows for contextual stuff such as logs, description, containers..</summary>
  <img src="https://github.com/user-attachments/assets/d5c927b4-cfa7-4906-8a73-a0b7c822a00b" width="700px">
</details>
<details>
  <summary>Run custom commands e.g <code>:Kubectl get configmaps -A</code></summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/d889e44e-d22a-4cb5-96fb-61de9d37ad43" width="700px">
</details>
<details>
  <summary>Change context using cmd <code>:Kubectx context-name</code></summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/8473233/9ca4f5b6-fb8c-47bf-a588-560e219c439c" width="700px">
</details>
<details>
  <summary>Exec into containers</summary>
  <sub>In the pod view, select a pod by pressing <code>&lt;cr&gt;</code> and then again <code>&lt;cr&gt;</code> on the container you want to exec into</sub>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/24e15963-bfd2-43a5-9e35-9d33cf5d976e" width="700px">
</details>
<details>
  <summary>Sort by headers</summary>
    <sub>By moving the cursor to a header word and pressing <code>s</code></sub>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/9f96e943-eda4-458e-a4ba-cf23e0417963" width="700px">
</details>
<details>
  <summary>Tail logs</summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/8ab220a7-459a-4faf-8709-7f106a36a53b" width="700px">
</details>
<details>
  <summary>Diff view: <code>:Kubectl diff (path)</code></summary>
  <img src="https://github.com/user-attachments/assets/52662db4-698b-4059-a5a2-2c9ddfe8d146" width="700px">
</details>
   
## ⚡️ Required Dependencies
- kubectl
- curl
- neovim >= 0.10
 
## ⚡️ Optional Dependencies
- [kubediff](https://github.com/Ramilito/kubediff) or [DirDiff](https://github.com/will133/vim-dirdiff) (If you want to use the diff feature)

## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  {
    "ramilito/kubectl.nvim",
    config = function()
      require("kubectl").setup()
    end,
  },
}
```

## ⌨️ Keymaps

```lua
-- Recommended is to have the same open mapping as your close (```<leader>k```) the plugin for a toggle effect.
vim.keymap.set("n", "<leader>k", '<cmd>lua require("kubectl").open()<cr>', { noremap = true, silent = true })
```

## ⚙️ Configuration

### Setup
```lua
{
  auto_refresh = {
    enabled = false,
    interval = 3000, -- milliseconds
  },
  diff = {
    bin = "kubediff" -- or any other binary
  },
  namespace = "All",
  notifications = {
    enabled = true,
    verbose = false,
    blend = 100,
  },
  hints = true,
  context = true,
  float_size = {
    -- Almost fullscreen:
    -- width = 1.0,
    -- height = 0.95, -- Setting it to 1 will cause bottom to be cutoff by statuscolumn

    -- For more context aware size:
    width = 0.9,
    height = 0.8,

    -- Might need to tweak these to get it centered when float is smaller
    col = 10,
    row = 5,
  },
  obj_fresh = 0, -- highlight if creation newer than number (in minutes)
  mappings = {
    exit = "<leader>k",
  }
}
```

## Performance

### Startup

The setup function only adds ~1ms to startup.
We use kubectl proxy and curl to reduce latency.

## Versioning
> [!WARNING]
> As we have not yet reached v1.0.0, we may have some breaking changes
> in cases where it is deemed necessary.

## Motivation
This plugins main purpose is to browse the kubernetes state using vim like navigation and keys, similar to oil.nvim for file browsing.
