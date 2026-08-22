--- Configuration. Defaults alone are enough for markdown (NFR-4); settings
--- exist only to override them.
local M = {}

--- Applied to every enabled filetype, then overridden by that filetype's entry.
M.filetype_defaults = {
  --- Order the marker styles are cycled through (FR-6). An entry may carry a
  --- checkbox, which makes having one part of the style.
  cycle = { '-', '- [ ]', '*', '1.', '1)', 'a)', 'I.' },
  --- Characters written between the brackets of a checkbox (FR-5).
  checkbox = { checked = 'x', unchecked = ' ' },
  --- Treat a leading `>` as part of the item prefix.
  blockquote = true,
  --- Recognise fenced and indented code blocks and stay out of them (FR-7).
  code_blocks = true,
}

M.defaults = {
  --- Filetypes the plugin acts on. Add an entry to enable another one, or set
  --- an entry to `false` to disable it. Buffers of any other filetype are left
  --- alone entirely (FR-8).
  filetypes = {
    markdown = {},
  },
}

local settings = nil
local per_filetype = {}

--- @param opts table|nil
function M.setup(opts)
  settings = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  per_filetype = {}
end

local function current()
  if not settings then
    M.setup({})
  end
  return settings
end

--- Resolved options for a buffer, or nil when its filetype is not enabled.
--- Buffer-local 'tabstop', 'expandtab' and 'shiftwidth' are read at call time
--- so that indentation follows the buffer the user is actually editing.
--- @param bufnr integer
--- @return table|nil
function M.get(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local filetype = vim.bo[bufnr].filetype
  local entry = current().filetypes[filetype]
  if not entry then
    return nil
  end
  if not per_filetype[filetype] then
    local resolved = vim.tbl_deep_extend('force', vim.deepcopy(M.filetype_defaults), entry)
    resolved.checkbox_class = require('autolist.line').checkbox_class(resolved.checkbox)
    per_filetype[filetype] = resolved
  end
  return setmetatable({
    filetype = filetype,
    tabstop = vim.bo[bufnr].tabstop,
    expandtab = vim.bo[bufnr].expandtab,
    shiftwidth = vim.fn.shiftwidth(),
  }, { __index = per_filetype[filetype] })
end

return M
