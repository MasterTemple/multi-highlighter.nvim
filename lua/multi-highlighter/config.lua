--- Configuration management
local M = {}

-- Default palette — used when a category doesn't specify fg/bg,
-- cycling through these for auto-assigned colors
M.defaults = {
  -- Palette of (fg, bg) pairs for auto-assigned categories.
  -- Each entry is { fg = "#rrggbb", bg = "#rrggbb" }.
  -- bg takes precedence visually; fg is the text color over the highlight.
  palette = {
    { bg = "#3d5a3e", fg = "#c8e6c9" }, -- green
    { bg = "#3b3a5c", fg = "#ce93d8" }, -- purple
    { bg = "#5c3a1e", fg = "#ffcc80" }, -- orange
    { bg = "#1e3a5c", fg = "#90caf9" }, -- blue
    { bg = "#5c1e1e", fg = "#ef9a9a" }, -- red
    { bg = "#3a3a1e", fg = "#fff176" }, -- yellow
    { bg = "#1e4a4a", fg = "#80cbc4" }, -- teal
    { bg = "#4a1e3a", fg = "#f48fb1" }, -- pink
  },

  -- Pre-defined categories loaded at startup.
  -- Each key is a category name, value is options:
  --   hl_group  : use an existing Vim highlight group (overrides fg/bg)
  --   fg        : foreground color "#rrggbb"
  --   bg        : background color "#rrggbb"
  --   bold      : boolean
  --   italic    : boolean
  --   underline : boolean
  -- Example:
  --   categories = {
  --     todo   = { bg = "#5c3a1e", fg = "#ffcc80", bold = true },
  --     search = { hl_group = "Search" },
  --   }
  categories = {},
}

M.options = vim.deepcopy(M.defaults)

---@param opts table
function M.apply(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end

return M
