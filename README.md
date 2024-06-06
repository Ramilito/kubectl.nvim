# kubectl.nvim
Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.
<img src="/.github/demo2.gif?raw=true" width="1700px">

Note: This is still incomplete in that it doesn't handle all possible resources and I might change things up in the future.

## ✨ Features
- Navigate your cluster in a buffer, using hierarchy where possible (backspace for up, enter for down) e.g. root -> deplyoment -> pod -> container
- Colored output and smart highlighting
- Floating windows for contextual stuff such as logs, description, containers..
<details>
  <summary>Run custom commands e.g ```:Kubectl get configmaps -A```</summary>
  <img src="/.github/usercmd.gif?raw=true" width="700px">
</details>
<details>
  <summary>Exec into containers</summary>
  <img src="/.github/exec.gif?raw=true" width="700px">
</details>
<details>
  <summary>Sort by headers</summary>
  <img src="/.github/sort.gif?raw=true" width="700px">
</details>
<details>
  <summary>Tail logs</summary>
  <img src="/.github/tail.gif?raw=true" width="700px">
</details>


## ⚡️ Dependencies
- kubectl
- plenary.nvim
  
## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  {
    "ramilito/kubectl.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
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
  namespace = "All",
  hints = true,
  auto_refresh = false,
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

## Motivation
This plugins main purpose is to browse the kubernetes state using vim like navigation and keys, similar to oil.nvim for filebrowsing. I might add a way to act on the cluster (delete resources, edit) in the future, not sure yet.
