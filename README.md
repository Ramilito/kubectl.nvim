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

- [kubediff](https://github.com/Ramilito/kubediff) or
  [DirDiff](https://github.com/will133/vim-dirdiff) (If you want to use the diff
  feature)

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

<details><summary>Default Mappings</summary>

```lua
-- default mappings
local group = vim.api.nvim_create_augroup("kubectl_mappings", { clear = false })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "k8s_*",
  callback = function(ev)
    local k = vim.keymap.set
    local opts = { buffer = ev.buf }
    k("n", "<Plug>(kubectl.alias_view)", "<C-a>", opts)
    k("n", "<Plug>(kubectl.browse)", "gx", opts)
    k("n", "<Plug>(kubectl.contexts_view)", "<C-x>", opts)
    k("n", "<Plug>(kubectl.cordon)", "gC", opts)
    k("n", "<Plug>(kubectl.create_job)", "gc", opts)
    k("n", "<Plug>(kubectl.delete)", "gD", opts)
    k("n", "<Plug>(kubectl.describe)", "gd", opts)
    k("n", "<Plug>(kubectl.drain)", "gR", opts)
    k("n", "<Plug>(kubectl.edit)", "ge", opts)
    k("n", "<Plug>(kubectl.filter_label)", "<C-l>", opts)
    k("n", "<Plug>(kubectl.filter_view)", "<C-f>", opts)
    k("n", "<Plug>(kubectl.follow)", "f", opts)
    k("n", "<Plug>(kubectl.go_up)", "<BS>", opts)
    k("v", "<Plug>(kubectl.filter_term)", "<C-f>", opts)
    k("n", "<Plug>(kubectl.help)", "g?", opts)
    k("n", "<Plug>(kubectl.history)", "gh", opts)
    k("n", "<Plug>(kubectl.kill)", "gk", opts)
    k("n", "<Plug>(kubectl.logs)", "gl", opts)
    k("n", "<Plug>(kubectl.namespace_view)", "<C-n>", opts)
    k("n", "<Plug>(kubectl.portforward)", "gp", opts)
    k("n", "<Plug>(kubectl.portforwards_view)", "gP", opts)
    k("n", "<Plug>(kubectl.prefix)", "gp", opts)
    k("n", "<Plug>(kubectl.quit)", "", opts)
    k("n", "<Plug>(kubectl.refresh)", "gr", opts)
    k("n", "<Plug>(kubectl.rollout_restart)", "grr", opts)
    k("n", "<Plug>(kubectl.scale)", "gss", opts)
    k("n", "<Plug>(kubectl.select)", "<CR>", opts)
    k("n", "<Plug>(kubectl.set_image)", "gi", opts)
    k("n", "<Plug>(kubectl.sort)", "gs", opts)
    k("n", "<Plug>(kubectl.suspend_job)", "gx", opts)
    k("n", "<Plug>(kubectl.tab)", "<Tab>", opts)
    k("n", "<Plug>(kubectl.timestamps)", "gt", opts)
    k("n", "<Plug>(kubectl.top_nodes)", "gn", opts)
    k("n", "<Plug>(kubectl.top_pods)", "gp", opts)
    k("n", "<Plug>(kubectl.uncordon)", "gU", opts)
    k("n", "<Plug>(kubectl.view_1)", "1", opts)
    k("n", "<Plug>(kubectl.view_2)", "2", opts)
    k("n", "<Plug>(kubectl.view_3)", "3", opts)
    k("n", "<Plug>(kubectl.view_4)", "4", opts)
    k("n", "<Plug>(kubectl.view_5)", "5", opts)
    k("n", "<Plug>(kubectl.wrap)", "gw", opts)
  end,
})
```

</details>

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

## 🎨 Colors

The plugin uses the following highlight groups:

<details><summary>Highlight Groups</summary>

| Name                | Default                       | Color |
| ------------------- | ----------------------------- | ----------------------------------------------------------------------------------------- |
| KubectlHeader       | `{ fg = "#569CD6" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=C586C0" width="20" /> |
| KubectlWarning      | `{ fg = "#D19A66" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=D19A66" width="20" /> |
| KubectlError        | `{ fg = "#D16969" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=D16969" width="20" /> |
| KubectlInfo         | `{ fg = "#608B4E" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=608B4E" width="20" /> |
| KubectlDebug        | `{ fg = "#DCDCAA" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=DCDCAA" width="20" /> |
| KubectlSuccess      | `{ fg = "#4EC9B0" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=4EC9B0" width="20" /> |
| KubectlPending      | `{ fg = "#C586C0" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=C586C0" width="20" /> |
| KubectlDeprecated   | `{ fg = "#D4A5A5" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=D4A5A5" width="20" /> |
| KubectlExperimental | `{ fg = "#CE9178" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=CE9178" width="20" /> |
| KubectlNote         | `{ fg = "#9CDCFE" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=9CDCFE" width="20" /> |
| KubectlGray         | `{ fg = "#666666" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=666666" width="20" /> |
| KubectlPselect      | `{ bg = "#3e4451" }`          | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=3e4451" width="20" /> |
| KubectlPmatch       | `{ link = "KubectlWarning" }` | <img src="https://www.thecolorapi.com/id?format=svg&named=false&hex=D19A66" width="20" /> |
| KubectlUnderline    | `{ underline = true }`        | -                                                                                         |

</details>

## 🚀 Performance

### Startup

The setup function only adds ~1ms to startup.
We use kubectl proxy and curl to reduce latency.

## ⚠️ Versioning

> [!WARNING]
> As we have not yet reached v1.0.0, we may have some breaking changes
> in cases where it is deemed necessary.

## 💪🏼 Motivation

This plugins main purpose is to browse the kubernetes state using vim like
navigation and keys, similar to oil.nvim for file browsing.
