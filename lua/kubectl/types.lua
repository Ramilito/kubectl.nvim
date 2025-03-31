---@class Hint
---@field key string
---@field desc string
---@field long_desc string

---@class GVK
---@field g string
---@field v string
---@field k string

---@class Informer
---@field enabled boolean

---@class Definition
---@field resource string
---@field display_name string
---@field ft string
---@field gvk GVK
---@field informer Informer
---@field hints Hint[]
---@field headers string[]

---@class Module
---@field View fun(cancellationToken: any)
---@field Draw fun(cancellationToken: any)
---@field Desc fun(name: string, ns: string, reload: boolean)
---@field Definition Definition
---@field getCurrentSelection function: string|nil
