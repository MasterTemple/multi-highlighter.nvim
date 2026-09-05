--- multi-highlighter.nvim
--- Multiple simultaneous highlights with category management
local M = {}

-- Internal state
M._categories = {} -- { [name] = { hl_group, ranges, ns_id } }
M._ns_prefix = "MultiHighlighter_"

local config = require("multi-highlighter.config")
local highlights = require("multi-highlighter.highlights")
local commands = require("multi-highlighter.commands")

--- Setup the plugin with user configuration
---@param opts table|nil
function M.setup(opts)
  config.apply(opts or {})
  highlights.init()
  commands.register()
end

-- Re-export the public API
M.add_range = highlights.add_range
M.set_range = highlights.set_range
M.clear = highlights.clear
M.clear_all = highlights.clear_all
M.add_pattern = highlights.add_pattern
M.set_pattern = highlights.set_pattern
M.define_category = highlights.define_category
M.get_categories = highlights.get_categories
M.populate_qflist = highlights.populate_qflist
M.populate_loclist = highlights.populate_loclist

return M
