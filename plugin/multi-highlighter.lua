-- plugin/multi-highlighter.lua
-- Auto-loaded by Neovim. Registers :Hl with sensible defaults
-- even if the user doesn't call require("multi-highlighter").setup().

if vim.g.loaded_multi_highlighter then
  return
end
vim.g.loaded_multi_highlighter = true

-- Defer so that user init.lua setup() calls can configure before we init
vim.schedule(function()
  local ok, mh = pcall(require, "multi-highlighter")
  if not ok then return end
  -- Only auto-init if the user hasn't already called setup()
  if not mh._initialised then
    mh.setup({})
    mh._initialised = true
  end
end)
