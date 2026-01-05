<h1 align="center"><img src="https://github.com/user-attachments/assets/f28e04e0-0610-412c-9c58-fa53706a9c91"> kubectl.nvim</h1>
<p align="center">
  <a href="https://nvim.io/">
    <img src="https://img.shields.io/static/v1?style=flat-square&label=neovim&message=v0.11%2b&logo=neovim&color=414b32">
  </a>
  <img src="https://img.shields.io/github/languages/code-size/Ramilito/kubectl.nvim?style=flat-square">
  <a href="https://github.com/Ramilito/kubectl.nvim/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Ramilito/kubectl.nvim?style=flat-square">
  </a>
  <img src="https://img.shields.io/github/check-runs/Ramilito/kubectl.nvim/main">
  <a href="https://github.com/Ramilito/kubectl.nvim/releases/latest">
    <img src="https://img.shields.io/github/v/release/Ramilito/kubectl.nvim">
  </a>
</p>

Processes kubectl outputs to enable vim-like navigation in a buffer for your cluster.

<img src="https://github.com/user-attachments/assets/2243c9d8-0808-4734-92aa-7612496c920b" width="1700px">

## ✨ Features

<details>
  <summary>Navigate your cluster in a buffer, using hierarchy where possible (backspace for up, enter for down) e.g. root -> deplyoment -> pod -> container
</summary>
  <img src="https://github.com/user-attachments/assets/2243c9d8-0808-4734-92aa-7612496c920b" width="700px">
</details>
<details>
  <summary>Colored output and smart highlighting</summary>
  <img src="https://github.com/user-attachments/assets/f42fa62c-0ddc-4733-9a83-b9d55b4745a1" width="700px">
</details>
<details>
  <summary>Floating windows for contextual stuff such as logs, description, containers..</summary>
  <img src="https://github.com/user-attachments/assets/899cb923-e038-4822-890b-d88466797d52" width="700px">
</details>
<details>
  <summary>Completion</summary>
  <img src="https://github.com/user-attachments/assets/f6d5d38a-2b1d-4262-9c15-0587277e2b7a" width="700px">
</details>
<details>
  <summary>Commands: <code>:Kubectl</code>, <code>:Kubens</code>, <code>:Kubectx</code></summary>
  <sub>Run kubectl commands directly or open interactive views. All commands support tab completion.</sub>
  <pre>:Kubectl get endpoints     -- Run kubectl and show output in split
:Kubectl view [resource]          -- Open interactive view for any resource
:Kubectl top                      -- Open top dashboard
:Kubectl diff [path]              -- Diff resources
:Kubens [namespace]               -- Switch or select namespace
:Kubectx [context]                -- Switch or select context</pre>
  <img src="https://github.com/user-attachments/assets/3162ef16-4730-472b-95f8-4bdc2948647f" width="700px">
</details>
<details>
  <summary>Change context using cmd <code>:Kubectx context-name</code> or the context view</summary>
  <img src="https://github.com/user-attachments/assets/bca7c827-4207-47d2-b828-5dc6caab005a" width="700px">
</details>
<details>
  <summary>Exec into containers</summary>
  <sub>In the pod view, select a pod by pressing <code>&lt;cr&gt;</code> and then again <code>&lt;cr&gt;</code> on the container you want to exec into</sub>
  <img src="https://github.com/user-attachments/assets/ffb9cfb1-8e75-4917-88f5-477a443669a9" width="700px">
</details>
<details>
  <summary>Sort by headers</summary>
  <sub>By moving the cursor to anywhere in a column and pressing <code>gs</code></sub>
  <img src="https://github.com/user-attachments/assets/918038d4-60ed-4d7a-a20d-8d9e57fd1be9" width="700px">
</details>
<details>
  <summary>Tail logs</summary>
  <img src="https://github.com/user-attachments/assets/8a1f59fb-59f2-4093-a479-8900940edfc9" width="700px">
</details>
<details>
  <summary>Diff view: <code>:Kubectl diff (path)</code></summary>
  <img src="https://github.com/user-attachments/assets/52662db4-698b-4059-a5a2-2c9ddfe8d146" width="700px">
</details>
<details>
  <summary>Port forward</summary>
  <img src="https://github.com/user-attachments/assets/9dec1bb8-b65c-4b5a-a8fe-4ca26c93ab43" width="700px">
</details>
<details>
  <summary>Aliases (fallback view)</summary>
  <sub>A fallback view that directs custom resources and has basic functionality such desc, edit, del</sub>
  <img src="https://github.com/user-attachments/assets/6d5bbb82-bc42-4ab4-9f9d-a40b1e7f0286" width="700px">
</details>
<details>
  <summary>Overview</summary>
  <img src="https://github.com/user-attachments/assets/cb1f46be-fcc0-4a6d-9d1e-ffcd5bdb32b3" width="700px">
</details>
<details>
  <summary>Picker for recent items</summary>
  <img src="https://github.com/user-attachments/assets/fb519986-4d6e-437d-8fda-bd14199a71f2" width="700px">
</details>
<details>
  <summary>Lineage</summary>
  <sub>A plugin similar to <a href="https://github.com/tohjustin/kube-lineage/tree/master">kube-lineage</a></sub>
  <sub>⚠️ This is a beta feature and not all bugs are sorted out</sub>
  <img src="https://github.com/user-attachments/assets/6c170724-d86d-46a7-af98-2862c45bcd01" width="700px">
</details>

## ⚡️ Required Dependencies

- neovim >= 0.10

## ⚡️ Optional Dependencies

- [kubediff](https://github.com/Ramilito/kubediff) or
  [DirDiff](https://github.com/will133/vim-dirdiff) (If you want to use the diff
  feature)
- [Helm](https://helm.sh/docs/intro/install/) (for helm view)

## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  {
    "ramilito/kubectl.nvim",
    -- use a release tag to download pre-built binaries
    version = "2.*",
    -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    -- build = 'cargo build --release',
    dependencies = "saghen/blink.download",
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
vim.keymap.set(
  "n",
  "<leader>k",
  '<cmd>lua require("kubectl").toggle({ tab: boolean })<cr>',
  { noremap = true, silent = true }
)
```

#### Override existing

```lua
local group = vim.api.nvim_create_augroup("kubectl_mappings", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "k8s_*",
  callback = function(ev)
    local k = vim.keymap
    local opts = { buffer = ev.buf }

    k.set("n", "<C-e>", "<Plug>(kubectl.picker_view)", opts)
  end,
})
```

#### Delete existing

```lua
local group = vim.api.nvim_create_augroup("kubectl_mappings", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "k8s_*",
  callback = function(ev)
    local k = vim.keymap
    local opts = { buffer = ev.buf }

    pcall(k.del, "n", 1, opts)
    pcall(k.del, "n", 2, opts)
    pcall(k.del, "n", 3, opts)
    pcall(k.del, "n", 5, opts)
    pcall(k.del, "n", 6, opts)
  end,
})
```

#### Default Mappings

You can override the plugin's keymaps using the `<Plug>` mappings:

<details><summary>Default Mappings</summary>

```lua
-- default mappings
local group = vim.api.nvim_create_augroup("kubectl_mappings", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "k8s_*",
  callback = function(ev)
    local k = vim.keymap.set
    local opts = { buffer = ev.buf }

    -- Global
    k("n", "g?", "<Plug>(kubectl.help)", opts) -- Help float
    k("n", "gr", "<Plug>(kubectl.refresh)", opts) -- Refresh view
    k("n", "gs", "<Plug>(kubectl.sort)", opts) -- Sort by column
    k("n", "gD", "<Plug>(kubectl.delete)", opts) -- Delete resource
    k("n", "gd", "<Plug>(kubectl.describe)", opts) -- Describe resource
    k("n", "gy", "<Plug>(kubectl.yaml)", opts) -- View yaml
    k("n", "ge", "<Plug>(kubectl.edit)", opts) -- Edit resource
    k("n", "<C-l>", "<Plug>(kubectl.filter_label)", opts) -- Filter labels
    k("n", "<BS>", "<Plug>(kubectl.go_up)", opts) -- Go back to previous view
    k("v", "<C-f>", "<Plug>(kubectl.filter_term)", opts) -- Filter selected text
    k("n", "<CR>", "<Plug>(kubectl.select)", opts) -- Resource select action (different on each view)
    k("n", "<Tab>", "<Plug>(kubectl.tab)", opts) -- Select resource
    k("n", "<S-Tab>", "<Plug>(kubectl.clear_selection)", opts) -- Clear selection
    k("n", "", "<Plug>(kubectl.quit)", opts) -- Close view (when applicable)
    k("n", "gk", "<Plug>(kubectl.kill)", opts) -- Pod/portforward kill
    k("n", "<M-h>", "<Plug>(kubectl.toggle_headers)", opts) -- Toggle headers
    k("n", "<f4>", "<Plug>(kubectl.toggle_fullscreen)", opts) -- Toggle fullscreen

    -- Views
    k("n", "<C-p>", "<Plug>(kubectl.picker_view)", opts) -- Picker view
    k("n", "<C-a>", "<Plug>(kubectl.alias_view)", opts) -- Aliases view
    k("n", "<C-x>", "<Plug>(kubectl.contexts_view)", opts) -- Contexts view
    k("n", "<C-f>", "<Plug>(kubectl.filter_view)", opts) -- Filter view
    k("n", "<C-n>", "<Plug>(kubectl.namespace_view)", opts) -- Namespaces view
    k("n", "gP", "<Plug>(kubectl.portforwards_view)", opts) -- Portforwards view

    -- views
    k("n", "1", "<Plug>(kubectl.view_deployments)", opts) -- Deployments view
    k("n", "2", "<Plug>(kubectl.view_pods)", opts) -- Pods view
    k("n", "3", "<Plug>(kubectl.view_configmaps)", opts) -- ConfigMaps view
    k("n", "4", "<Plug>(kubectl.view_secrets)", opts) -- Secrets view
    k("n", "5", "<Plug>(kubectl.view_services)", opts) -- Services view
    k("n", "6", "<Plug>(kubectl.view_ingresses)", opts) -- Ingresses view
    k("n", "", "<Plug>(kubectl.view_api_resources)", opts) -- API-Resources view
    k("n", "", "<Plug>(kubectl.view_clusterrolebinding)", opts) -- ClusterRoleBindings view
    k("n", "", "<Plug>(kubectl.view_crds)", opts) -- CRDs view
    k("n", "", "<Plug>(kubectl.view_cronjobs)", opts) -- CronJobs view
    k("n", "", "<Plug>(kubectl.view_daemonsets)", opts) -- DaemonSets view
    k("n", "", "<Plug>(kubectl.view_events)", opts) -- Events view
    k("n", "", "<Plug>(kubectl.view_helm)", opts) -- Helm view
    k("n", "", "<Plug>(kubectl.view_horizontalpodautoscalers)", opts) -- HorizontalPodAutoscalers view
    k("n", "", "<Plug>(kubectl.view_jobs)", opts) -- Jobs view
    k("n", "", "<Plug>(kubectl.view_nodes)", opts) -- Nodes view
    k("n", "", "<Plug>(kubectl.view_overview)", opts) -- Overview view
    k("n", "", "<Plug>(kubectl.view_persistentvolumes)", opts) -- PersistentVolumes view
    k("n", "", "<Plug>(kubectl.view_persistentvolumeclaims)", opts) -- PersistentVolumeClaims view
    k("n", "", "<Plug>(kubectl.view_replicasets)", opts) -- ReplicaSets view,
    k("n", "", "<Plug>(kubectl.view_serviceaccounts)", opts) -- ServiceAccounts view
    k("n", "", "<Plug>(kubectl.view_statefulsets)", opts) -- StatefulSets view
    k("n", "", "<Plug>(kubectl.view_storageclasses)", opts) -- StorageClasses view
    k("n", "", "<Plug>(kubectl.view_top_nodes)", opts) -- Top view for nodes
    k("n", "", "<Plug>(kubectl.view_top_pods)", opts) -- Top view for pods

    -- Deployment/DaemonSet actions
    k("n", "grr", "<Plug>(kubectl.rollout_restart)", opts) -- Rollout restart
    k("n", "gss", "<Plug>(kubectl.scale)", opts) -- Scale workload
    k("n", "gi", "<Plug>(kubectl.set_image)", opts) -- Set image (only if 1 container)

    -- Pod/Container logs
    k("n", "gl", "<Plug>(kubectl.logs)", opts) -- Logs view
    k("n", "gh", "<Plug>(kubectl.history)", opts) -- Change logs --since= flag
    k("n", "f", "<Plug>(kubectl.follow)", opts) -- Follow logs
    k("n", "gw", "<Plug>(kubectl.wrap)", opts) -- Toggle wrap log lines
    k("n", "gp", "<Plug>(kubectl.prefix)", opts) -- Toggle container name prefix
    k("n", "gt", "<Plug>(kubectl.timestamps)", opts) -- Toggle timestamps prefix
    k("n", "gpp", "<Plug>(kubectl.previous_logs)", opts) -- Toggle show previous logs

    -- Node actions
    k("n", "gC", "<Plug>(kubectl.cordon)", opts) -- Cordon node
    k("n", "gU", "<Plug>(kubectl.uncordon)", opts) -- Uncordon node
    k("n", "gR", "<Plug>(kubectl.drain)", opts) -- Drain node

    -- Top actions
    k("n", "gn", "<Plug>(kubectl.top_nodes)", opts) -- Top nodes
    k("n", "gp", "<Plug>(kubectl.top_pods)", opts) -- Top pods

    -- CronJob actions
    k("n", "gss", "<Plug>(kubectl.suspend_cronjob)", opts) -- Suspend CronJob
    k("n", "gc", "<Plug>(kubectl.create_job)", opts) -- Create Job from CronJob

    k("n", "gp", "<Plug>(kubectl.portforward)", opts) -- Pods/Services portforward
    k("n", "gx", "<Plug>(kubectl.browse)", opts) -- Ingress view
    k("n", "gy", "<Plug>(kubectl.yaml)", opts) -- Helm view
  end,
})
```

</details>

#### Lazy Setup

For overriding the default mappings when using `lazy.nvim` [check out our wiki page.](https://github.com/Ramilito/kubectl.nvim/wiki/Lazy-setup)

## ⚙️ Configuration

### Setup

```lua
{
  log_level = vim.log.levels.INFO,
  auto_refresh = {
    enabled = true,
    interval = 300, -- milliseconds
  },
  diff = {
    bin = "kubediff" -- or any other binary
  },
  kubectl_cmd = { cmd = "kubectl", env = {}, args = {}, persist_context_change = false },
  terminal_cmd = nil, -- Exec will launch in a terminal if set, i.e. "ghostty -e"
  namespace = "All",
  namespace_fallback = {}, -- If you have limited access you can list all the namespaces here
  headers = {
    enabled = true,
    hints = true,
    context = true,
    heartbeat = true,
    blend = 20,
    skew = {
      enabled = true,
      log_level = vim.log.levels.OFF,
    },
  },
  lineage = {
    enabled = true, -- This feature is in beta at the moment
  },
  logs = {
    prefix = true,
    timestamps = true,
    since = "5m"
  },
  alias = {
    apply_on_select_from_history = true,
    max_history = 5,
  },
  filter = {
    apply_on_select_from_history = true,
    max_history = 10,
  },
  filter_label = {
    max_history = 20,
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
  statusline = {
    enabled = true
  },
  obj_fresh = 5, -- highlight if creation newer than number (in minutes)
  api_resources_cache_ttl = 60 * 60 * 3, -- 3 hours in seconds
}
```

## 🎨 Colors

The plugin uses the following highlight groups:

<details><summary>Highlight Groups</summary>

| Name                | Default                       | Color                                                                                     |
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

## Events

We trigger events that you can use to run custom logic:

<details><summary>events</summary>

| Name                | When                          | Data |
| ------------------- | ----------------------------- | ----------------------------- |
| K8sResourceSelected | On main views, when selecting a resource unless overriden (like pod view) | kind, name, ns |
| K8sContextChanged   | After context change | context |
| K8sCacheLoaded      | After api-resources cache is loaded | - |

Example: saving session on context change

```lua
   vim.api.nvim_create_autocmd("User", {
     group = group,
     pattern = "K8sContextChanged",
     callback = function(ctx)
       local results =
         require("kubectl.actions.commands").shell_command("kubectl", { "config", "use-context", ctx.data.context })
       if not results then
         vim.notify(results, vim.log.levels.INFO)
       end
     end,
   })
```

</details>

## 🚀 Performance

### Startup

The setup function only adds ~1ms to startup.
We use kubectl proxy and curl to reduce latency.

### Efficient resource monitoring

We leverage the kubernetes informer to efficiently monitor resource updates.

By using the `resourceversion`, we avoid fetching all resources in each loop.

Instead, the Informer provides only the changes, significantly reducing overhead and improving performance.

## ⚠️ Versioning

As of `v2`, the plugin is in a stable state. No breaking changes are scheduled at this time, and we remain committed to delivering a reliable, consistent user experience.

## Troubleshooting

### Winbar

If you have a Winbar plugin, such as `lualine` there will be conflicts with the winbar in this plugin. To solve this, you should add our filetypes to the exclude files table.

## 🔥 Developers

Instructions from here: [repro.lua](https://lazy.folke.io/developers#reprolua)
You can find one prepared here: ./repro.lua

## 💪🏼 Motivation

This plugins main purpose is to browse the kubernetes state using vim like
navigation and keys, similar to oil.nvim for file browsing.
