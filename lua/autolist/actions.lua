--- The behaviours described in the requirements. Every function here is
--- explicit: nothing observes the buffer and reformats on its own (NFR-6), and
--- each one writes its result with a single buffer update so that one action
--- costs one undo (NFR-3).
local M = {}

local block = require('autolist.block')
local config = require('autolist.config')
local context = require('autolist.context')
local lineparse = require('autolist.line')

local function resolve_buf(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function resolve_win(win)
  if win == nil or win == 0 then
    return vim.api.nvim_get_current_win()
  end
  return win
end

--- Write back every line marked dirty, as one update spanning only the range
--- that actually changed.
local function flush(bufnr, blk)
  local first, last
  for _, entry in ipairs(blk.entries) do
    if entry.dirty then
      first = first or entry.lnum
      last = entry.lnum
    end
  end
  if not first then
    return false
  end
  local lines = {}
  for lnum = first, last do
    local entry = blk.by_lnum[lnum]
    lines[#lines + 1] = entry.dirty and lineparse.render(entry.item) or entry.item.text
  end
  vim.api.nvim_buf_set_lines(bufnr, first - 1, last, false, lines)
  return true
end

local function ordered_items(run)
  local ordered = {}
  for _, entry in ipairs(run) do
    if entry.item.marker.kind ~= 'bullet' then
      ordered[#ordered + 1] = entry
    end
  end
  return ordered
end

--- A list written entirely with the same number (`1. 1. 1.`) renders as a
--- sequence in markdown anyway, and people write it on purpose. Detect it so it
--- can be left alone.
local function all_same_number(ordered)
  if #ordered < 2 then
    return false
  end
  for i = 2, #ordered do
    if ordered[i].item.marker.value ~= ordered[1].item.marker.value then
      return false
    end
  end
  return true
end

--- Settle single letters that could be read either as a letter or as a Roman
--- numeral by looking at the siblings that are not ambiguous.
local function resolve_letter_kind(ordered)
  local roman, alpha = false, false
  for _, entry in ipairs(ordered) do
    local marker = entry.item.marker
    if not marker.ambiguous then
      if marker.kind == 'roman' then
        roman = true
      elseif marker.kind == 'alpha' then
        alpha = true
      end
    end
  end
  if roman then
    return 'roman'
  end
  if alpha then
    return 'alpha'
  end
  return nil
end

--- Renumber one sibling run in place. Each item keeps its own delimiter and its
--- own kind of number; only the ordinal changes.
--- @param run table
--- @param opts table|nil `force` ignores the all-same-number rule, `start`
---   overrides the value of the first item
--- @return boolean changed
function M.renumber_run(run, opts)
  opts = opts or {}
  local ordered = ordered_items(run)
  if #ordered == 0 then
    return false
  end
  if not opts.force and all_same_number(ordered) then
    return false
  end
  local letter_kind = resolve_letter_kind(ordered)
  local start = opts.start or ordered[1].item.marker.value
  local changed = false
  for i, entry in ipairs(ordered) do
    local marker = entry.item.marker
    if marker.ambiguous and letter_kind then
      marker.kind = letter_kind
      marker.ambiguous = false
    end
    marker.value = start + i - 1
    local text = lineparse.render_marker(marker)
    if text ~= entry.item.marker_text then
      entry.item.marker_text = text
      entry.dirty = true
      changed = true
    end
  end
  return changed
end

--- FR-3. Renumber the whole list block around the cursor line.
--- @param bufnr integer
--- @param lnum integer
--- @return boolean
function M.renumber(bufnr, lnum)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  bufnr = resolve_buf(bufnr)
  local blk = block.find(bufnr, lnum, opts)
  if not blk then
    return false
  end
  for _, run in ipairs(block.runs(blk)) do
    M.renumber_run(run)
  end
  return flush(bufnr, blk)
end

--- What the next item in this run should look like: whether the list repeats
--- one number, and how its ambiguous letters are meant to be read.
local function run_style(bufnr, lnum, opts)
  local blk = block.find(bufnr, lnum, opts)
  if not blk then
    return { repeat_number = false }
  end
  block.runs(blk)
  local run = block.run_at(blk, lnum)
  if not run then
    return { repeat_number = false }
  end
  local ordered = ordered_items(run)
  return { repeat_number = all_same_number(ordered), letter_kind = resolve_letter_kind(ordered) }
end

--- Shared by `can_newline` and `newline` so that the two never disagree.
local function newline_target(bufnr, win, opts)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(win))
  if context.is_code(bufnr, lnum, opts) then
    return nil
  end
  local parsed = lineparse.parse(block.get_line(bufnr, lnum), opts)
  -- Continuation lines take part in a block but never start a new item, and a
  -- cursor sitting inside the marker itself means the user is not appending to
  -- the item. Both fall through to a plain newline.
  if not parsed.marker or col < #parsed.prefix then
    return nil
  end
  return { lnum = lnum, col = col, item = parsed }
end

--- Whether `newline()` would do anything, so that a mapping can fall back to
--- whatever else is bound to the key (NFR-2).
--- @return boolean
function M.can_newline(bufnr, win)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  return newline_target(resolve_buf(bufnr), resolve_win(win), opts) ~= nil
end

--- FR-1 and FR-2. Break the line and carry the list on, or leave the list when
--- the item is empty.
--- @return boolean whether autolist handled the newline
function M.newline(bufnr, win)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  bufnr = resolve_buf(bufnr)
  win = resolve_win(win)
  local target = newline_target(bufnr, win, opts)
  if not target then
    return false
  end
  local item = target.item
  local lnum, col = target.lnum, target.col

  -- FR-2: an empty item disappears and the line becomes an ordinary one. Inside
  -- a blockquote the quote markers stay, because the text is still quoted.
  if item.empty then
    local left = item.quote ~= '' and (item.quote .. ' ') or ''
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { left })
    vim.api.nvim_win_set_cursor(win, { lnum, #left })
    return true
  end

  local marker = vim.deepcopy(item.marker)
  if marker.kind ~= 'bullet' then
    local style = run_style(bufnr, lnum, opts)
    if marker.ambiguous and style.letter_kind then
      marker.kind = style.letter_kind
      marker.ambiguous = false
    end
    if not style.repeat_number then
      marker.value = (marker.value or 0) + 1
    end
  end

  local space = item.space ~= '' and item.space or ' '
  local checkbox = ''
  if item.checkbox then
    local box_space = item.checkbox_space ~= '' and item.checkbox_space or ' '
    -- A new item always starts unchecked, however the previous one was left.
    checkbox = '[' .. opts.checkbox.unchecked .. ']' .. box_space
  end
  local prefix = item.quote .. item.indent .. lineparse.render_marker(marker) .. space .. checkbox

  local line = item.text
  vim.api.nvim_buf_set_lines(
    bufnr,
    lnum - 1,
    lnum,
    false,
    { line:sub(1, col), prefix .. line:sub(col + 1) }
  )
  vim.api.nvim_win_set_cursor(win, { lnum + 1, #prefix })
  return true
end

--- Where an item lands when it is shifted. Indenting aims at the level of the
--- children the previous sibling already has, so that an item joins an existing
--- nested list instead of inventing a new indent width for it.
local function target_indent(blk, index, width, direction, opts)
  if direction > 0 then
    local sibling
    for i = index - 1, 1, -1 do
      local other = blk.entries[i]
      if not other.continuation then
        if other.item.indent_width == width then
          sibling = i
          break
        elseif other.item.indent_width < width then
          break
        end
      end
    end
    -- The first item of a run has nothing to nest under.
    if not sibling then
      return nil
    end
    for i = sibling + 1, index - 1 do
      local other = blk.entries[i]
      if not other.continuation and other.item.indent_width > width then
        return other.item.indent_width
      end
    end
    return width + opts.shiftwidth
  end
  for i = index - 1, 1, -1 do
    local other = blk.entries[i]
    if not other.continuation and other.item.indent_width < width then
      return other.item.indent_width
    end
  end
  return nil
end

local function shift_plan(bufnr, win, direction, opts)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(win))
  local blk = block.find(bufnr, lnum, opts)
  if not blk then
    return nil
  end
  local entry = blk.by_lnum[lnum]
  if not entry or entry.continuation then
    return nil
  end
  local index = blk.index[lnum]
  local width = entry.item.indent_width
  local target = target_indent(blk, index, width, direction, opts)
  if not target or target == width then
    return nil
  end
  return { blk = blk, entry = entry, index = index, width = width, target = target, lnum = lnum, col = col }
end

--- Whether `shift()` would move anything.
--- @return boolean
function M.can_shift(bufnr, win, direction)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  return shift_plan(resolve_buf(bufnr), resolve_win(win), direction, opts) ~= nil
end

--- FR-4. Move the item under the cursor one level in or out, carrying its
--- continuation lines and nested items with it, and fix the numbering of the
--- block as part of the same action.
--- @param direction integer 1 to indent, -1 to dedent
--- @return boolean
function M.shift(bufnr, win, direction)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  bufnr = resolve_buf(bufnr)
  win = resolve_win(win)
  local plan = shift_plan(bufnr, win, direction, opts)
  if not plan then
    return false
  end
  local blk, entry = plan.blk, plan.entry

  local last = plan.index
  for i = plan.index + 1, #blk.entries do
    if blk.entries[i].item.indent_width > plan.width then
      last = i
    else
      break
    end
  end

  local delta = plan.target - plan.width
  local before = #entry.item.indent
  for i = plan.index, last do
    local other = blk.entries[i]
    local width = math.max(0, other.item.indent_width + delta)
    other.item.indent = lineparse.make_indent(width, opts)
    other.item.indent_width = width
    other.dirty = true
  end

  local runs = block.runs(blk)
  -- An item that ends up alone at a level it just created starts that level's
  -- numbering from the beginning rather than keeping the number it had.
  if direction > 0 and entry.run and entry.run[1] == entry and entry.item.marker.kind ~= 'bullet' then
    entry.item.marker.value = 1
  end
  for _, run in ipairs(runs) do
    M.renumber_run(run)
  end

  flush(bufnr, blk)

  local moved = #entry.item.indent - before
  local line = block.get_line(bufnr, plan.lnum)
  vim.api.nvim_win_set_cursor(win, { plan.lnum, math.max(0, math.min(#line, plan.col + moved)) })
  return true
end

--- Whether the cursor sits in the leading part of a list item -- its indent,
--- marker or checkbox -- rather than inside the content. Used to keep an
--- insert-mode `<Tab>` from shifting the item when the user is simply typing.
--- @return boolean
function M.cursor_in_prefix(bufnr, win)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  bufnr = resolve_buf(bufnr)
  win = resolve_win(win)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(win))
  local parsed = lineparse.parse(block.get_line(bufnr, lnum), opts)
  return parsed.marker ~= nil and col <= #parsed.prefix
end

--- FR-5. Flip the checkbox of the item on `lnum`.
--- @return boolean
function M.toggle_checkbox(bufnr, lnum)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  bufnr = resolve_buf(bufnr)
  if lnum < 1 or lnum > vim.api.nvim_buf_line_count(bufnr) then
    return false
  end
  if context.is_code(bufnr, lnum, opts) then
    return false
  end
  local parsed = lineparse.parse(block.get_line(bufnr, lnum), opts)
  if not parsed.marker or not parsed.checkbox then
    return false
  end
  parsed.checkbox = parsed.checkbox == opts.checkbox.unchecked and opts.checkbox.checked
    or opts.checkbox.unchecked
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { lineparse.render(parsed) })
  return true
end

local function style_matches(marker, spec)
  if marker.kind ~= spec.kind then
    return false
  end
  if marker.kind == 'bullet' then
    return marker.text == spec.text
  end
  return marker.delim == spec.delim and marker.upper == spec.upper
end

--- FR-6. Convert every item of the block to the next marker style in the
--- configured order, numbering each level from the start.
--- @return boolean
function M.cycle_markers(bufnr, lnum)
  local opts = config.get(bufnr)
  if not opts then
    return false
  end
  bufnr = resolve_buf(bufnr)
  local blk = block.find(bufnr, lnum, opts)
  if not blk then
    return false
  end

  local specs = {}
  for _, text in ipairs(opts.cycle or {}) do
    local marker = lineparse.parse(text .. ' x', opts).marker
    if marker then
      specs[#specs + 1] = marker
    end
  end
  if #specs == 0 then
    return false
  end

  local first
  for _, entry in ipairs(blk.entries) do
    if not entry.continuation then
      first = entry
      break
    end
  end
  if not first then
    return false
  end

  local at = 0
  for i, spec in ipairs(specs) do
    if style_matches(first.item.marker, spec) then
      at = i
      break
    end
  end
  local next_spec = specs[(at % #specs) + 1]

  for _, run in ipairs(block.runs(blk)) do
    local ordinal = 0
    for _, entry in ipairs(run) do
      ordinal = ordinal + 1
      local marker = entry.item.marker
      marker.kind = next_spec.kind
      marker.text = next_spec.text
      marker.delim = next_spec.delim
      marker.upper = next_spec.upper
      marker.ambiguous = false
      marker.value = next_spec.kind ~= 'bullet' and ordinal or nil
      local text = lineparse.render_marker(marker)
      if text ~= entry.item.marker_text then
        entry.item.marker_text = text
        entry.dirty = true
      end
    end
  end

  return flush(bufnr, blk)
end

return M
