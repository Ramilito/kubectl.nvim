local M = {
  resource = "top_nodes",
  display_name = "top nodes",
  ft = "k8s_top_nodes",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/nodes?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.top_pods)", desc = "top_pods", long_desc = "Top pods" },
    { key = "<Plug>(kubectl.top_nodes)", desc = "top_nodes", long_desc = "Top nodes" },
  },
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
