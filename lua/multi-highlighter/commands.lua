--- :Hl command registration with full tab-completion
local M = {}

local hl = require("multi-highlighter.highlights")

-- ── Pattern parsing ──────────────────────────────────────────────────────────

--- Extract pattern and flags from /pattern/flags notation.
--- Returns pattern string and flags string (may be empty).
---@param s string
---@return string|nil pattern, string flags
local function parse_pattern_arg(s)
  if s:sub(1, 1) == "/" then
    -- /pattern/flags  or  /pattern/  or  /pattern
    local body = s:sub(2)
    local close = body:find("/[^/]*$")
    if close then
      local pat   = body:sub(1, close - 1)
      local flags = body:sub(close + 1)
      return pat, flags
    else
      return body, ""
    end
  end
  return nil, ""
end

-- ── Sub-command handlers ─────────────────────────────────────────────────────

local function cmd_add(args)
  if #args < 2 then
    vim.notify(":Hl add <category> <range|/pattern/[flags]>", vim.log.levels.WARN)
    return
  end
  local cat  = args[1]
  local rest = table.concat(args, " ", 2)

  local pat, flags = parse_pattern_arg(rest)
  if pat then
    hl.add_pattern(cat, pat, flags)
  else
    -- Could be multiple space-separated ranges
    for i = 2, #args do
      hl.add_range(cat, args[i])
    end
  end
end

local function cmd_set(args)
  if #args < 2 then
    vim.notify(":Hl set <category> <range|/pattern/[flags]>", vim.log.levels.WARN)
    return
  end
  local cat  = args[1]
  local rest = table.concat(args, " ", 2)

  local pat, flags = parse_pattern_arg(rest)
  if pat then
    hl.set_pattern(cat, pat, flags)
  else
    -- Set with first range only (clear then add)
    hl.clear(cat)
    for i = 2, #args do
      hl.add_range(cat, args[i])
    end
  end
end

local function cmd_clear(args)
  if #args == 0 then
    hl.clear_all()
  else
    for _, cat in ipairs(args) do
      hl.clear(cat)
    end
  end
end

-- option key → validator/normaliser.  Returns cleaned value or nil + err msg.
local category_option_keys = {
  fg        = function(v) return v end,
  bg        = function(v) return v end,
  hl_group  = function(v) return v end,
  bold      = function(v)
    if v == "true"  or v == "1" then return true  end
    if v == "false" or v == "0" then return false end
    return nil, "bold must be true/false"
  end,
  italic    = function(v)
    if v == "true"  or v == "1" then return true  end
    if v == "false" or v == "0" then return false end
    return nil, "italic must be true/false"
  end,
  underline = function(v)
    if v == "true"  or v == "1" then return true  end
    if v == "false" or v == "0" then return false end
    return nil, "underline must be true/false"
  end,
}

local function cmd_category(args)
  if #args == 0 then
    -- List existing categories
    local cats = hl.get_categories()
    if #cats == 0 then
      vim.notify("[multi-highlighter] No categories defined", vim.log.levels.INFO)
    else
      vim.notify("[multi-highlighter] Categories: " .. table.concat(cats, ", "), vim.log.levels.INFO)
    end
    return
  end

  local name = args[1]
  local opts = {}

  -- Parse key=value pairs
  for i = 2, #args do
    local k, v = args[i]:match("^([%w_]+)=(.+)$")
    if not k then
      vim.notify("[multi-highlighter] Invalid option: " .. args[i] .. " (use key=value)", vim.log.levels.WARN)
      return
    end
    local validator = category_option_keys[k]
    if not validator then
      vim.notify("[multi-highlighter] Unknown option: " .. k, vim.log.levels.WARN)
      return
    end
    local val, err = validator(v)
    if err then
      vim.notify("[multi-highlighter] " .. err, vim.log.levels.WARN)
      return
    end
    opts[k] = val
  end

  hl.define_category(name, opts)
  vim.notify(string.format("[multi-highlighter] Category '%s' defined", name), vim.log.levels.INFO)
end

local function cmd_qflist(args)
  hl.populate_qflist(#args > 0 and args or nil)
end

local function cmd_loclist(args)
  hl.populate_loclist(#args > 0 and args or nil)
end

-- ── Completion ───────────────────────────────────────────────────────────────

local sub_commands = { "add", "set", "clear", "category", "qflist", "loclist" }

local category_option_completions = (function()
  local list = {}
  for k in pairs(category_option_keys) do
    table.insert(list, k .. "=")
  end
  table.sort(list)
  return list
end)()

local function filter_prefix(list, prefix)
  local out = {}
  for _, v in ipairs(list) do
    if v:sub(1, #prefix) == prefix then
      table.insert(out, v)
    end
  end
  return out
end

---@param arg_lead string   the word being completed
---@param cmd_line string   the full command line so far
---@param _cursor_pos number
local function complete(arg_lead, cmd_line, _cursor_pos)
  -- Tokenise the command line (skip the :Hl part)
  local parts = {}
  for token in cmd_line:gmatch("%S+") do
    table.insert(parts, token)
  end
  -- If there is a trailing space, add a blank token for the current position
  if cmd_line:sub(-1) == " " then
    table.insert(parts, "")
  end

  -- parts[1] is "Hl", parts[2] is sub-command, parts[3]+ are args
  local n = #parts

  if n <= 2 then
    -- Completing the sub-command
    return filter_prefix(sub_commands, arg_lead)
  end

  local sub = parts[2]
  local cat_names = hl.get_categories()

  if sub == "add" or sub == "set" then
    if n == 3 then
      -- Completing category name
      return filter_prefix(cat_names, arg_lead)
    end
    -- After category: suggest pattern prefix hint
    if arg_lead == "" or arg_lead:sub(1, 1) == "/" then
      return { "/" }
    end
    return {}
  end

  if sub == "clear" then
    -- Any number of category names
    return filter_prefix(cat_names, arg_lead)
  end

  if sub == "category" then
    if n == 3 then
      -- Category name (existing or new)
      return filter_prefix(cat_names, arg_lead)
    end
    -- Options: key=value
    -- Complete the key portion before '='
    local prefix_key = arg_lead:match("^([%w_]*)") or ""
    local completions = {}
    for _, opt in ipairs(category_option_completions) do
      if opt:sub(1, #prefix_key) == prefix_key then
        table.insert(completions, opt)
      end
    end
    -- Bool completions after "bold=", "italic=", "underline="
    for _, boolkey in ipairs({ "bold", "italic", "underline" }) do
      local prefix = boolkey .. "="
      if arg_lead:sub(1, #prefix) == prefix then
        local val_prefix = arg_lead:sub(#prefix + 1)
        local bools = filter_prefix({ "true", "false" }, val_prefix)
        local out = {}
        for _, b in ipairs(bools) do
          table.insert(out, prefix .. b)
        end
        return out
      end
    end
    return completions
  end

  if sub == "qflist" or sub == "loclist" then
    return filter_prefix(cat_names, arg_lead)
  end

  return {}
end

-- ── Registration ─────────────────────────────────────────────────────────────

function M.register()
  vim.api.nvim_create_user_command("Hl", function(opts)
    local fargs = opts.fargs
    if #fargs == 0 then
      vim.notify(":Hl <add|set|clear|category|qflist|loclist> [args...]", vim.log.levels.INFO)
      return
    end

    local sub  = fargs[1]
    local rest = { unpack(fargs, 2) }

    if sub == "add"      then cmd_add(rest)
    elseif sub == "set"      then cmd_set(rest)
    elseif sub == "clear"    then cmd_clear(rest)
    elseif sub == "category" then cmd_category(rest)
    elseif sub == "qflist"   then cmd_qflist(rest)
    elseif sub == "loclist"  then cmd_loclist(rest)
    else
      vim.notify("[multi-highlighter] Unknown sub-command: " .. sub, vim.log.levels.WARN)
    end
  end, {
    nargs      = "*",
    complete   = complete,
    desc       = "multi-highlighter: manage highlight categories and ranges",
  })
end

return M
