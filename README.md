# kubectl.nvim
Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.
<img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/682db4a5-7387-4b89-8e2f-f0739058f728" width="1700px">

## ✨ Features
- Navigate your cluster in a buffer, using hierarchy where possible (backspace for up, enter for down) e.g. root -> deplyoment -> pod -> container
- Colored output and smart highlighting
- Floating windows for contextual stuff such as logs, description, containers..
<details>
  <summary>Run custom commands e.g `:Kubectl get configmaps -A`</summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/2a3507da-cfe3-4922-bd2f-ed0d8a696375" width="700px">
https://github.com/Ramilito/kubectl.nvim/assets/17252601/2a3507da-cfe3-4922-bd2f-ed0d8a696375
</details>
<details>
  <summary>Exec into containers</summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/812fb83c-d74a-4e81-98c2-c24981eb429f" width="700px">
</details>
<details>
  <summary>Sort by headers</summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/69299d58-c884-43b5-b715-29e8808bf032" width="700px">
</details>
<details>
  <summary>Tail logs</summary>
  <img src="https://github.com/Ramilito/kubectl.nvim/assets/17252601/8276f2c1-0cfa-4930-87d1-c4ec7a5dd9de" width="700px">
</details>


## ⚡️ Dependencies
- kubectl
- neovim >= 0.10

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
  auto_refresh = {
    enabled = false,
    interval = 3000, -- milliseconds
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

No startup impact since we load on demand.

## Usage

### Sorting
By moving the cursor to a header word and pressing ```s```

### Exec into container
In the pod view, select a pod by pressing ```<cr>``` and then again ```<cr>``` on the container you want to exec into

## Versioning
> [!WARNING]
> As we have not yet reached v1.0.0, we may have some breaking changes
> in cases where it is deemed necessary.

## Motivation
This plugins main purpose is to browse the kubernetes state using vim like navigation and keys, similar to oil.nvim for filebrowsing. I might add a way to act on the cluster (delete resources, edit) in the future, not sure yet.
