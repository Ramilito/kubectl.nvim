# kubectl.nvim

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
  <summary>Run custom commands e.g <code>:Kubectl get endpoints</code></summary>
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

## ⚡️ Required Dependencies

- kubectl
- curl
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

    -- Global
    k("n", "<Plug>(kubectl.help)", "g?", opts) -- Help float
    k("n", "<Plug>(kubectl.refresh)", "gr", opts) -- Refresh view
    k("n", "<Plug>(kubectl.sort)", "gs", opts) -- Sort by column
    k("n", "<Plug>(kubectl.delete)", "gD", opts) -- Delete resource
    k("n", "<Plug>(kubectl.describe)", "gd", opts) -- Describe resource
    k("n", "<Plug>(kubectl.edit)", "ge", opts) -- Edit resource
    k("n", "<Plug>(kubectl.filter_label)", "<C-l>", opts) -- Filter labels
    k("n", "<Plug>(kubectl.go_up)", "<BS>", opts) -- Go back to previous view
    k("v", "<Plug>(kubectl.filter_term)", "<C-f>", opts) -- Filter selected text
    k("n", "<Plug>(kubectl.select)", "<CR>", opts) -- Resource select action (different on each view)
    k("n", "<Plug>(kubectl.tab)", "<Tab>", opts) -- Tab completion (ascending, when applicable)
    k("n", "<Plug>(kubectl.shift_tab)", "<Tab>", opts) -- Tab completion (descending, when applicable)
    k("n", "<Plug>(kubectl.quit)", "", opts) -- Close view (when applicable)
    k("n", "<Plug>(kubectl.kill)", "gk", opts) -- Pod/portforward kill

    -- Header
    k("n", "<Plug>(kubectl.toggle_hints)", "<M-h>", opts) -- Toggle hints
    k("n", "<Plug>(kubectl.toggle_context)", "<M-c>", opts) -- Toggle context
    k("n", "<Plug>(kubectl.toggle_versions)", "<M-v>", opts) -- Toggle versions
    k("n", "<Plug>(kubectl.toggle_heartbeat)", "<M-b>", opts) -- Toggle heartbeat

    -- Views
    k("n", "<Plug>(kubectl.alias_view)", "<C-a>", opts) -- Aliases view
    k("n", "<Plug>(kubectl.contexts_view)", "<C-x>", opts) -- Contexts view
    k("n", "<Plug>(kubectl.filter_view)", "<C-f>", opts) -- Filter view
    k("n", "<Plug>(kubectl.namespace_view)", "<C-n>", opts) -- Namespaces view
    k("n", "<Plug>(kubectl.portforwards_view)", "gP", opts) -- Portforwards view
    k("n", "<Plug>(kubectl.view_deployments)", "1", opts) -- Deployments view
    k("n", "<Plug>(kubectl.view_pods)", "2", opts) -- Pods view
    k("n", "<Plug>(kubectl.view_configmaps)", "3", opts) -- ConfigMaps view
    k("n", "<Plug>(kubectl.view_secrets)", "4", opts) -- Secrets view
    k("n", "<Plug>(kubectl.view_services)", "5", opts) -- Services view
    k("n", "<Plug>(kubectl.view_ingresses)", "6", opts) -- Ingresses view
    k("n", "<Plug>(kubectl.view_api_resources)", "", opts) -- API-Resources view
    k("n", "<Plug>(kubectl.view_clusterrolebinding)", "", opts) -- ClusterRoleBindings view
    k("n", "<Plug>(kubectl.view_crds)", "", opts) -- CRDs view
    k("n", "<Plug>(kubectl.view_cronjobs)", "", opts) -- CronJobs view
    k("n", "<Plug>(kubectl.view_daemonsets)", "", opts) -- DaemonSets view
    k("n", "<Plug>(kubectl.view_events)", "", opts) -- Events view
    k("n", "<Plug>(kubectl.view_helm)", "", opts) -- Helm view
    k("n", "<Plug>(kubectl.view_jobs)", "", opts) -- Jobs view
    k("n", "<Plug>(kubectl.view_nodes)", "", opts) -- Nodes view
    k("n", "<Plug>(kubectl.view_overview)", "", opts) -- Overview view
    k("n", "<Plug>(kubectl.view_pv)", "", opts) -- PersistentVolumes view
    k("n", "<Plug>(kubectl.view_pvc)", "", opts) -- PersistentVolumeClaims view
    k("n", "<Plug>(kubectl.view_sa)", "", opts) -- ServiceAccounts view
    k("n", "<Plug>(kubectl.view_top_nodes)", "", opts) -- Top view for nodes
    k("n", "<Plug>(kubectl.view_top_pods)", "", opts) -- Top view for pods

    -- Deployment/DaemonSet actions
    k("n", "<Plug>(kubectl.rollout_restart)", "grr", opts) -- Rollout restart
    k("n", "<Plug>(kubectl.scale)", "gss", opts) -- Scale workload
    k("n", "<Plug>(kubectl.set_image)", "gi", opts) -- Set image (only if 1 container)

    -- Pod/Container logs
    k("n", "<Plug>(kubectl.logs)", "gl", opts) -- Logs view
    k("n", "<Plug>(kubectl.history)", "gh", opts) -- Change logs --since= flag
    k("n", "<Plug>(kubectl.follow)", "f", opts) -- Follow logs
    k("n", "<Plug>(kubectl.wrap)", "gw", opts) -- Toggle wrap log lines
    k("n", "<Plug>(kubectl.prefix)", "gp", opts) -- Toggle container name prefix
    k("n", "<Plug>(kubectl.timestamps)", "gt", opts) -- Toggle timestamps prefix

    -- Node actions
    k("n", "<Plug>(kubectl.cordon)", "gC", opts) -- Cordon node
    k("n", "<Plug>(kubectl.uncordon)", "gU", opts) -- Uncordon node
    k("n", "<Plug>(kubectl.drain)", "gR", opts) -- Drain node

    -- Top actions
    k("n", "<Plug>(kubectl.top_nodes)", "gn", opts) -- Top nodes
    k("n", "<Plug>(kubectl.top_pods)", "gp", opts) -- Top pods

    -- CronJob/Job actions
    k("n", "<Plug>(kubectl.suspend_job)", "gx", opts) -- only for CronJob
    k("n", "<Plug>(kubectl.create_job)", "gc", opts) -- Create Job from CronJob or Job

    k("n", "<Plug>(kubectl.portforward)", "gp", opts) -- Pods/Services portforward
    k("n", "<Plug>(kubectl.browse)", "gx", opts) -- Ingress view
    k("n", "<Plug>(kubectl.yaml)", "gy", opts) -- Helm view
  end,
})
```

</details>

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
  kubectl_cmd = { cmd = "kubectl", env = {}, args = {} },
  namespace = "All",
  namespace_fallback = {}, -- If you have limited access you can list all the namespaces here
  hints = true,
  context = true,
  heartbeat = true,
  kubernetes_versions = true,
  alias = {
    apply_on_select_from_history = true,
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

## 🚀 Performance

### Startup

The setup function only adds ~1ms to startup.
We use kubectl proxy and curl to reduce latency.

### Efficient Resource Monitoring

We leverage the Kubernetes Informer to efficiently monitor resource updates.

By using the `resourceVersion`, we avoid fetching all resources in each loop.

Instead, the Informer provides only the changes, significantly reducing overhead and improving performance.

## ⚠️ Versioning

As we advance to `v1.0.0`, our primary goal is to maintain the stability of the
plugin and minimize any breaking changes. We are committed to providing a
reliable and consistent user experience.

## 💪🏼 Motivation

This plugins main purpose is to browse the kubernetes state using vim like
navigation and keys, similar to oil.nvim for file browsing.
