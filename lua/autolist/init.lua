--- Public API.
---
--- No keys are mapped here and nothing is triggered by an autocommand
--- (NFR-6, NFR-7): every function below runs only when the user calls it, or
--- presses a key they bound to it themselves.
local M = {}

local actions = require('autolist.actions')
local config = require('autolist.config')

--- @param opts table|nil see `autolist.config.defaults`
function M.setup(opts)
  config.setup(opts)
end

--- FR-1, FR-2. Break the current list item, or leave the list when the item is
--- empty. Returns false when the cursor is not on a list item, in which case
--- the caller should insert a plain newline.
--- @return boolean handled
function M.newline()
  return actions.newline(0, 0)
end

--- FR-4. Move the item under the cursor one level in, taking its nested items
--- with it, and renumber the block.
--- @return boolean handled
function M.indent()
  return actions.shift(0, 0, 1)
end

--- FR-4. Move the item under the cursor one level out.
--- @return boolean handled
function M.dedent()
  return actions.shift(0, 0, -1)
end

--- FR-3. Renumber the list block around the cursor.
--- @return boolean handled
function M.renumber()
  return actions.renumber(0, vim.api.nvim_win_get_cursor(0)[1])
end

--- FR-5. Toggle the checkbox on `lnum`, or on the cursor line.
--- @param lnum integer|nil
--- @return boolean handled
function M.toggle_checkbox(lnum)
  return actions.toggle_checkbox(0, lnum or vim.api.nvim_win_get_cursor(0)[1])
end

--- FR-6. Switch every item of the block around the cursor, at every level, to
--- the next marker style in the configured cycle.
--- @param opts table|nil `{ reverse = true }` walks the cycle backwards
--- @return boolean handled
function M.cycle_markers_block(opts)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return actions.cycle_markers(0, lnum, 'block', opts and opts.reverse)
end

--- FR-6. Switch only the run of siblings the cursor is in, leaving its parent
--- and its nested items as they are.
--- @param opts table|nil `{ reverse = true }` walks the cycle backwards
--- @return boolean handled
function M.cycle_markers_siblings(opts)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return actions.cycle_markers(0, lnum, 'siblings', opts and opts.reverse)
end

--- FR-9. Turn the plain lines of a range into list items, keeping whatever
--- indentation they already have. Defaults to the cursor line.
--- @param first integer|nil
--- @param last integer|nil
--- @return boolean handled
function M.make_list(first, last)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return actions.make_list(0, first or lnum, last or first or lnum)
end

--- Whether the cursor sits in the leading part of a list item -- its
--- indentation, marker or checkbox -- rather than in the content.
---
--- This is the condition |autolist.tab()| applies internally. It is exposed for
--- callers that cannot use an expression mapping, such as a key routed through
--- another plugin's own mapping table:
---
---     elseif autolist.at_item_prefix() and autolist.indent() then
---
--- @return boolean
function M.at_item_prefix()
  return actions.cursor_in_prefix(0, 0)
end

--- Expression-mapping helpers.
---
--- Each returns a key sequence when autolist wants the key, and nil when it does
--- not, so that the mapping can fall through to whatever the user or another
--- plugin would otherwise do with it:
---
---     vim.keymap.set('i', '<CR>', function()
---       return require('autolist').cr() or '<CR>'
---     end, { expr = true, buffer = true })
---
--- The returned sequence runs the action through `<Cmd>`, because an expression
--- mapping is not allowed to change the buffer itself.

--- @return string|nil
function M.cr()
  if not actions.can_newline(0, 0) then
    return nil
  end
  return "<Cmd>lua require('autolist').newline()<CR>"
end

--- Meant for insert mode: the key only shifts the item while the cursor is in
--- the item's indent, marker or checkbox. Typing a tab inside the content is
--- left alone.
--- @return string|nil
function M.tab()
  if not actions.cursor_in_prefix(0, 0) or not actions.can_shift(0, 0, 1) then
    return nil
  end
  return "<Cmd>lua require('autolist').indent()<CR>"
end

--- @return string|nil
function M.shift_tab()
  if not actions.cursor_in_prefix(0, 0) or not actions.can_shift(0, 0, -1) then
    return nil
  end
  return "<Cmd>lua require('autolist').dedent()<CR>"
end

return M
