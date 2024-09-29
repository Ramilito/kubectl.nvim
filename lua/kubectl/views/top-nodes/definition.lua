local M = {
  resource = "top-nodes",
  display_name = "top nodes",
  ft = "k8s_top_nodes",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/nodes?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.top_pods)", desc = "top-pods", long_desc = "Top pods" },
    { key = "<Plug>(kubectl.top_nodes)", desc = "top-nodes", long_desc = "Top nodes" },
  },
  nodes = {},
}

function M.getHeaders()
  local headers = {
    "NAME",
    "CPU-CORES",
    "CPU-%",
    "MEM-BYTES",
    "MEM-%",
  }

  return headers
end

return vim.tbl_extend("force", require("kubectl.views.top.definition"), M)
