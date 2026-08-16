--- Finding the list block around a line, and grouping its items into sibling
--- runs.
---
--- A block is a maximal run of consecutive lines that are either list items or
--- continuation lines, at one blockquote depth. It ends at a blank line, at a
--- line that is neither an item nor a continuation, at a change of blockquote
--- depth, and at a code block.
local M = {}

local lineparse = require('autolist.line')
local context = require('autolist.context')

local function get_line(bufnr, lnum)
  return (vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false))[1]
end

--- Grow a block downwards from `start`, or return nil when `start` is not a
--- list item.
local function segment(bufnr, start, quote_depth, total, opts)
  local entries = {}
  local last_indent = nil
  local lnum = start
  while lnum <= total do
    if context.is_code(bufnr, lnum, opts) then
      break
    end
    local parsed = lineparse.parse(get_line(bufnr, lnum), opts)
    if parsed.blank or parsed.quote_depth ~= quote_depth or parsed.thematic_break then
      break
    end
    if parsed.marker then
      entries[#entries + 1] = { lnum = lnum, item = parsed }
      last_indent = parsed.indent_width
    elseif last_indent and parsed.indent_width > last_indent then
      entries[#entries + 1] = { lnum = lnum, item = parsed, continuation = true }
    else
      break
    end
    lnum = lnum + 1
  end
  if #entries == 0 then
    return nil
  end
  local block = {
    first = entries[1].lnum,
    last = entries[#entries].lnum,
    entries = entries,
    quote_depth = quote_depth,
    by_lnum = {},
    index = {},
    opts = opts,
  }
  for i, entry in ipairs(entries) do
    block.by_lnum[entry.lnum] = entry
    block.index[entry.lnum] = i
  end
  return block
end

--- The block that contains `lnum`, or nil when that line is not part of one.
--- @param bufnr integer
--- @param lnum integer 1-based
--- @param opts table
--- @return table|nil
function M.find(bufnr, lnum, opts)
  local total = vim.api.nvim_buf_line_count(bufnr)
  if lnum < 1 or lnum > total then
    return nil
  end
  if context.is_code(bufnr, lnum, opts) then
    return nil
  end
  local current = lineparse.parse(get_line(bufnr, lnum), opts)
  if current.blank or current.thematic_break then
    return nil
  end
  local quote_depth = current.quote_depth

  -- Widest possible upper bound: stop at the first line that can never take
  -- part in this block.
  local top = lnum
  while top > 1 do
    local above = lineparse.parse(get_line(bufnr, top - 1), opts)
    if
      above.blank
      or above.quote_depth ~= quote_depth
      or above.thematic_break
      or context.is_code(bufnr, top - 1, opts)
    then
      break
    end
    top = top - 1
  end

  -- Between `top` and `lnum` there may be several blocks, and leading lines
  -- that belong to none. Walk them until the one holding `lnum` is found.
  local start = top
  while start <= lnum do
    local block = segment(bufnr, start, quote_depth, total, opts)
    if block and block.first <= lnum and lnum <= block.last then
      return block
    end
    start = (block and block.last or start) + 1
  end
  return nil
end

--- Split the items of a block into sibling runs: maximal sequences of items at
--- the same indent with no shallower item in between. Numbering is computed per
--- run, which is what makes nested lists count independently of their parent.
--- @param block table
--- @return table[] list of runs, each a list of entries
function M.runs(block)
  local runs = {}
  local stack = {}
  for _, entry in ipairs(block.entries) do
    if not entry.continuation then
      local width = entry.item.indent_width
      while #stack > 0 and stack[#stack].indent > width do
        table.remove(stack)
      end
      local run
      if #stack > 0 and stack[#stack].indent == width then
        run = stack[#stack].run
        run[#run + 1] = entry
      else
        run = { entry }
        runs[#runs + 1] = run
        stack[#stack + 1] = { indent = width, run = run }
      end
      entry.run = run
      entry.depth = #stack
    end
  end
  return runs
end

--- The run that contains `lnum`, after `M.runs` has been called.
--- @param block table
--- @param lnum integer
--- @return table|nil
function M.run_at(block, lnum)
  local entry = block.by_lnum[lnum]
  return entry and entry.run or nil
end

M.get_line = get_line

return M
