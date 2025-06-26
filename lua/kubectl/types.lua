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

---@class ExtMark
---@field row? number the row number in the buffer (0-based)
---@field start_col number the starting column in the buffer (0-based)
---@field virt_text {text: string, highlight: string} the virtual text to display, tuple of text and highlight group
---@field virt_text_pos string the position of the virtual text, can be "inline" or "eol"
---@field right_gravity? boolean whether the virtual text should be right-aligned

---@class FilterLabelViewLine
---@field row number the row number of the line in the buffer (real number)
---@field ext_number number the extmark number in the buffer
---@field text? string the text of the line
---@field is_label boolean whether the line is a label or not
---@field is_selected? boolean whether the line is selected or not (only applies
---if is_label is true)
---@field extmarks ExtMark[] the extmarks associated with the line
---@field type string the type of the line, can be "existing_label", "res_label", or "confirmation"
