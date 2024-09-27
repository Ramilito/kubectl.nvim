# kubectl.nvim

Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.
<img src="https://github.com/user-attachments/assets/3c070dc5-1b93-47a0-9412-bf34ae611267" width="1700px">

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
    <sub>By moving the cursor to a column and pressing <code>s</code></sub>
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
<details>
  <summary>Port forward</summary>
  <img src="https://github.com/user-attachments/assets/ff52acdb-6341-456a-a6df-1bb88bec4ef8" width="700px">
</details>
<details>
  <summary>Aliases (fallback view)</summary>
  <sub>A fallback view that directs custom resources</sub>
  <img src="https://github.com/user-attachments/assets/226394a0-7579-4574-9337-2dd036a0dc63" width="700px">
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

We expose open, close and toggle to bind against:

#### Toggle

```lua
vim.keymap.set("n", "<leader>k", '<cmd>lua require("kubectl").toggle()<cr>', { noremap = true, silent = true })
```

You can also override the plugin's keymaps using the `<Plug>` mappings:

```lua
-- default mappings
vim.keymap.set("n", "<Plug>(kubectl.alias_view)", "<C-a>")
vim.keymap.set("n", "<Plug>(kubectl.browse)", "gx")
vim.keymap.set("n", "<Plug>(kubectl.contexts_view)", "<C-x>")
vim.keymap.set("n", "<Plug>(kubectl.cordon)", "gC")
vim.keymap.set("n", "<Plug>(kubectl.create_job)", "gc")
vim.keymap.set("n", "<Plug>(kubectl.delete)", "gD")
vim.keymap.set("n", "<Plug>(kubectl.describe)", "gd")
vim.keymap.set("n", "<Plug>(kubectl.drain)", "gR")
vim.keymap.set("n", "<Plug>(kubectl.edit)", "ge")
vim.keymap.set("n", "<Plug>(kubectl.filter_label)", "<C-l>")
vim.keymap.set("n", "<Plug>(kubectl.filter_view)", "<C-f>")
vim.keymap.set("n", "<Plug>(kubectl.follow)", "f")
vim.keymap.set("n", "<Plug>(kubectl.go_up)", "<BS>")
vim.keymap.set("v", "<Plug>(kubectl.filter_term)", "<C-f>")
vim.keymap.set("n", "<Plug>(kubectl.help)", "g?")
vim.keymap.set("n", "<Plug>(kubectl.history)", "gh")
vim.keymap.set("n", "<Plug>(kubectl.kill)", "gk")
vim.keymap.set("n", "<Plug>(kubectl.logs)", "gl")
vim.keymap.set("n", "<Plug>(kubectl.namespace_view)", "<C-n>")
vim.keymap.set("n", "<Plug>(kubectl.portforward)", "gp")
vim.keymap.set("n", "<Plug>(kubectl.portforwards_view)", "gP")
vim.keymap.set("n", "<Plug>(kubectl.prefix)", "gp")
vim.keymap.set("n", "<Plug>(kubectl.quit)", "")
vim.keymap.set("n", "<Plug>(kubectl.refresh)", "gr")
vim.keymap.set("n", "<Plug>(kubectl.rollout_restart)", "grr")
vim.keymap.set("n", "<Plug>(kubectl.scale)", "gss")
vim.keymap.set("n", "<Plug>(kubectl.select)", "<CR>")
vim.keymap.set("n", "<Plug>(kubectl.set_image)", "gi")
vim.keymap.set("n", "<Plug>(kubectl.sort)", "gs")
vim.keymap.set("n", "<Plug>(kubectl.suspend_job)", "gx")
vim.keymap.set("n", "<Plug>(kubectl.tab)", "<Tab>")
vim.keymap.set("n", "<Plug>(kubectl.timestamps)", "gt")
vim.keymap.set("n", "<Plug>(kubectl.top_nodes)", "gn")
vim.keymap.set("n", "<Plug>(kubectl.top_pods)", "gp")
vim.keymap.set("n", "<Plug>(kubectl.uncordon)", "gU")
vim.keymap.set("n", "<Plug>(kubectl.view_1)", "1")
vim.keymap.set("n", "<Plug>(kubectl.view_2)", "2")
vim.keymap.set("n", "<Plug>(kubectl.view_3)", "3")
vim.keymap.set("n", "<Plug>(kubectl.view_4)", "4")
vim.keymap.set("n", "<Plug>(kubectl.view_5)", "5")
vim.keymap.set("n", "<Plug>(kubectl.wrap)", "gw")
vim.keymap.set("n", "<Plug>(kubectl.yaml)", "gy")
```

## ⚙️ Configuration

### Setup

```lua
{
  auto_refresh = {
    enabled = true,
    interval = 300, -- milliseconds
  },
  diff = {
    bin = "kubediff" -- or any other binary
  },
  kubectl_cmd = { cmd = "kubectl", env = {}, args = {} },
  namespace = "All",
  namespace_fallback = {}, -- If you have limited access you can list all the namespaces here
  hints = true,
  context = true,
  alias = {
    max_history = 5,
  },
  filter = {
    apply_on_select_from_history = true,
    max_history = 10,
  },
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
  obj_fresh = 5, -- highlight if creation newer than number (in minutes)
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
