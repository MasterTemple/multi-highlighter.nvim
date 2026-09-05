--- Core highlight state and operations
local M = {}

local config = require("multi-highlighter.config")

-- { [cat_name] = {
--     hl_group  = string,    -- vim highlight group name
--     ns_id     = number,    -- extmark namespace
--     ranges    = {          -- list of { buf, lnum, col_start, col_end }
--       { buf, lnum, col_start, col_end }, ...
--     }
--   }
-- }
local categories = {}

-- Number of categories ever created (for palette cycling)
local category_count = 0

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function hl_group_name(cat)
  return "MultiHighlighter_" .. cat
end

local function ensure_category(name)
  if not categories[name] then
    M.define_category(name, {})
  end
end

--- Apply a vim.api.nvim_set_hl call for a category based on its stored opts.
local function apply_hl(name, opts)
  local hl_spec = {}
  if opts.hl_group then
    -- Link to an existing group
    vim.api.nvim_set_hl(0, hl_group_name(name), { link = opts.hl_group })
    return
  end

  -- Auto-pick from palette if neither fg nor bg given
  local palette = config.options.palette
  local index = ((category_count - 1) % #palette) + 1
  local pair = palette[index]

  hl_spec.bg = opts.bg or pair.bg
  hl_spec.fg = opts.fg or pair.fg
  if opts.bold ~= nil then hl_spec.bold = opts.bold end
  if opts.italic ~= nil then hl_spec.italic = opts.italic end
  if opts.underline ~= nil then hl_spec.underline = opts.underline end

  vim.api.nvim_set_hl(0, hl_group_name(name), hl_spec)
end

--- Return a zero-indexed (row, col_start, col_end) from a range spec.
--- Range specs:
---   "N"          → whole line N (1-indexed)
---   "N,M"        → line N col M (M is 1-indexed byte col)
---   "N,M-P,Q"    → line N col M to line P col Q
---   { lnum=, col_start=, col_end= } (already parsed, 0-indexed)
---@return { lnum:number, col_start:number, col_end:number }[]|nil
local function parse_range(range_str)
  if type(range_str) == "table" then
    return { range_str }
  end

  local results = {}

  -- Try "lnum,col_start-lnum2,col_end"
  local l1, c1, l2, c2 = range_str:match("^(%d+),(%d+)-(%d+),(%d+)$")
  if l1 then
    -- Multi-line: one entry per line
    l1, c1, l2, c2 = tonumber(l1) - 1, tonumber(c1) - 1,
                     tonumber(l2) - 1, tonumber(c2) - 1
    if l1 == l2 then
      table.insert(results, { lnum = l1, col_start = c1, col_end = c2 })
    else
      -- First line: c1 to EOL
      table.insert(results, { lnum = l1, col_start = c1, col_end = -1 })
      for ln = l1 + 1, l2 - 1 do
        table.insert(results, { lnum = ln, col_start = 0, col_end = -1 })
      end
      -- Last line: 0 to c2
      table.insert(results, { lnum = l2, col_start = 0, col_end = c2 })
    end
    return results
  end

  -- Try "lnum,col"
  local l, c = range_str:match("^(%d+),(%d+)$")
  if l then
    l, c = tonumber(l) - 1, tonumber(c) - 1
    -- Highlight the character at col
    table.insert(results, { lnum = l, col_start = c, col_end = c + 1 })
    return results
  end

  -- Try bare "lnum"
  local ln = range_str:match("^(%d+)$")
  if ln then
    ln = tonumber(ln) - 1
    table.insert(results, { lnum = ln, col_start = 0, col_end = -1 })
    return results
  end

  return nil
end

--- Place extmarks for a list of parsed ranges in a buffer.
---@param buf number
---@param ns_id number
---@param hl_grp string
---@param parsed_ranges table
local function place_extmarks(buf, ns_id, hl_grp, parsed_ranges)
  for _, r in ipairs(parsed_ranges) do
    local opts = {
      end_row    = r.lnum,
      hl_group   = hl_grp,
      priority   = 200,
    }
    if r.col_end == -1 then
      -- Whole line highlight via line_hl_group
      opts = {
        line_hl_group = hl_grp,
        priority      = 200,
      }
      vim.api.nvim_buf_set_extmark(buf, ns_id, r.lnum, 0, opts)
    else
      opts.end_col = r.col_end
      vim.api.nvim_buf_set_extmark(buf, ns_id, r.lnum, r.col_start, opts)
    end
  end
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Initialise the plugin: load pre-configured categories.
function M.init()
  for name, opts in pairs(config.options.categories) do
    M.define_category(name, opts)
  end
end

--- Define (or redefine) a category.
---@param name string
---@param opts table  { hl_group?, fg?, bg?, bold?, italic?, underline? }
function M.define_category(name, opts)
  opts = opts or {}
  if not categories[name] then
    category_count = category_count + 1
    categories[name] = {
      ns_id  = vim.api.nvim_create_namespace("MultiHighlighter_" .. name),
      ranges = {},
      opts   = opts,
    }
  else
    categories[name].opts = opts
  end
  apply_hl(name, categories[name].opts)
end

--- Return sorted list of defined category names.
---@return string[]
function M.get_categories()
  local names = {}
  for k in pairs(categories) do
    table.insert(names, k)
  end
  table.sort(names)
  return names
end

--- Add one or more ranges to a category in the current buffer.
---@param cat string
---@param range_str string  e.g. "5" | "5,3" | "5,3-7,10"
function M.add_range(cat, range_str)
  ensure_category(cat)
  local buf = vim.api.nvim_get_current_buf()
  local parsed = parse_range(range_str)
  if not parsed then
    vim.notify("[multi-highlighter] Invalid range: " .. range_str, vim.log.levels.WARN)
    return
  end

  local entry = categories[cat]
  for _, r in ipairs(parsed) do
    r.buf = buf
    table.insert(entry.ranges, r)
  end
  place_extmarks(buf, entry.ns_id, hl_group_name(cat), parsed)
end

--- Set (replace) ranges for a category.
---@param cat string
---@param range_str string
function M.set_range(cat, range_str)
  M.clear(cat)
  M.add_range(cat, range_str)
end

--- Add all matches of a Vim pattern in the current buffer to a category.
---@param cat string
---@param pattern string   bare pattern, e.g. "TODO" or "\bfoo\b"
---@param flags string|nil  "g" (default) or "gI" etc. — not used directly,
---                          nvim search is always global per line here
function M.add_pattern(cat, pattern, _flags)
  ensure_category(cat)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local entry = categories[cat]
  local hl_grp = hl_group_name(cat)
  local new_ranges = {}

  -- Use vim regex for consistency with Vim patterns
  local ok, rx = pcall(vim.regex, pattern)
  if not ok then
    vim.notify("[multi-highlighter] Invalid pattern: " .. pattern, vim.log.levels.ERROR)
    return
  end

  for lnum, line in ipairs(lines) do
    local row = lnum - 1
    local search_start = 0
    while true do
      local s, e = rx:match_str(line:sub(search_start + 1))
      if s == nil then break end
      -- s/e are 0-indexed relative to sub-string
      local col_start = search_start + s
      local col_end   = search_start + e
      if col_end <= col_start then col_end = col_start + 1 end -- zero-width guard

      local r = { buf = buf, lnum = row, col_start = col_start, col_end = col_end }
      table.insert(entry.ranges, r)
      table.insert(new_ranges, r)
      search_start = col_end
      if search_start >= #line then break end
    end
  end

  place_extmarks(buf, entry.ns_id, hl_grp, new_ranges)
  vim.notify(
    string.format("[multi-highlighter] %d match(es) added to '%s'", #new_ranges, cat),
    vim.log.levels.INFO
  )
end

--- Set (replace) pattern matches for a category.
---@param cat string
---@param pattern string
function M.set_pattern(cat, pattern)
  M.clear(cat)
  M.add_pattern(cat, pattern)
end

--- Clear all highlights for a category (all buffers).
---@param cat string
function M.clear(cat)
  if not categories[cat] then return end
  local entry = categories[cat]
  -- Clear extmarks in every buffer that has some
  local seen_bufs = {}
  for _, r in ipairs(entry.ranges) do
    if r.buf and not seen_bufs[r.buf] then
      seen_bufs[r.buf] = true
      if vim.api.nvim_buf_is_valid(r.buf) then
        vim.api.nvim_buf_clear_namespace(r.buf, entry.ns_id, 0, -1)
      end
    end
  end
  -- Also clear current buf just in case
  vim.api.nvim_buf_clear_namespace(
    vim.api.nvim_get_current_buf(), entry.ns_id, 0, -1
  )
  entry.ranges = {}
end

--- Clear highlights for all categories.
function M.clear_all()
  for name in pairs(categories) do
    M.clear(name)
  end
end

--- Collect ranges across the given categories (or all if nil) for list building.
---@param cat_names string[]|nil
---@return table[]  { bufnr, lnum (1-indexed), col (0-indexed), text, cat }
local function collect_entries(cat_names)
  local entries = {}
  local target = {}
  if cat_names and #cat_names > 0 then
    for _, n in ipairs(cat_names) do target[n] = true end
  else
    for n in pairs(categories) do target[n] = true end
  end

  for cat, is_target in pairs(target) do
    if is_target and categories[cat] then
      local entry = categories[cat]
      for _, r in ipairs(entry.ranges) do
        local buf = r.buf or vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(buf) then
          local lines = vim.api.nvim_buf_get_lines(buf, r.lnum, r.lnum + 1, false)
          local text = (lines[1] or ""):gsub("^%s+", "")
          table.insert(entries, {
            bufnr = buf,
            lnum  = r.lnum + 1,  -- 1-indexed for qf
            col   = r.col_start + 1,
            text  = string.format("[%s] %s", cat, text),
          })
        end
      end
    end
  end

  -- Sort by buf → lnum → col
  table.sort(entries, function(a, b)
    if a.bufnr ~= b.bufnr then return a.bufnr < b.bufnr end
    if a.lnum  ~= b.lnum  then return a.lnum  < b.lnum  end
    return a.col < b.col
  end)
  return entries
end

--- Populate the quickfix list.
---@param cat_names string[]|nil
function M.populate_qflist(cat_names)
  local entries = collect_entries(cat_names)
  vim.fn.setqflist({}, "r", {
    title = "MultiHighlighter matches",
    items = entries,
  })
  if #entries > 0 then
    vim.cmd("copen")
  else
    vim.notify("[multi-highlighter] No matches to add to quickfix list", vim.log.levels.WARN)
  end
end

--- Populate the location list.
---@param cat_names string[]|nil
function M.populate_loclist(cat_names)
  local entries = collect_entries(cat_names)
  local win = vim.api.nvim_get_current_win()
  vim.fn.setloclist(win, {}, "r", {
    title = "MultiHighlighter matches",
    items = entries,
  })
  if #entries > 0 then
    vim.cmd("lopen")
  else
    vim.notify("[multi-highlighter] No matches to add to location list", vim.log.levels.WARN)
  end
end

return M
