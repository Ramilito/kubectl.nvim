local M = {
  resource = "top-pods",
  display_name = "top pods",
  ft = "k8s_top_pods",
  url = { "{{BASE}}/apis/metrics.k8s.io/v1beta1/{{NAMESPACE}}pods?pretty=false" },
  hints = {
    { key = "<Plug>(kubectl.top_pods)", desc = "top_pods", long_desc = "Top pods" },
    { key = "<Plug>(kubectl.top_nodes)", desc = "top_nodes", long_desc = "Top nodes" },
  },
}

function M.getHeaders()
  local headers = {
    "NAMESPACE",
    "NAME",
    "CPU-CORES",
    "MEM-BYTES",
  }

  return headers
end

return vim.tbl_extend("force", require("kubectl.views.top.definition"), M)
