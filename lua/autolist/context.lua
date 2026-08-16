--- Tells apart lines that only look like list items from lines that are ones
--- (FR-7). Whether a line sits inside a code block cannot be decided from the
--- line alone -- a fence opened anywhere above changes the answer -- so the
--- buffer is classified from the top.
---
--- Doing that on every keystroke would scan the whole buffer, which NFR-1
--- forbids. Instead the classification is cached per buffer and extended
--- lazily: only lines up to the one being asked about are ever classified, a
--- snapshot of the scanner state is kept every `SNAPSHOT_EVERY` lines, and an
--- edit only invalidates the cache from the nearest snapshot before it. Typing
--- at the bottom of a large file therefore costs a bounded amount of work.
local M = {}

local lineparse = require('autolist.line')

local SNAPSHOT_EVERY = 200

--- bufnr -> cache
local caches = {}

local function initial_carry()
  return { fence = nil, list_active = false, list_indent = 0, blank_run = 0, prev = nil }
end

local function copy_carry(carry)
  return {
    fence = carry.fence and { char = carry.fence.char, len = carry.fence.len } or nil,
    list_active = carry.list_active,
    list_indent = carry.list_indent,
    blank_run = carry.blank_run,
    prev = carry.prev,
  }
end

--- Strip blockquote markers and indentation, so that a fence inside a quote or
--- inside a list item is still recognised.
local function strip(line, opts)
  local pos = 1
  if opts.blockquote then
    while true do
      local _, stop = line:find('^[ \t]*>', pos)
      if not stop then
        break
      end
      pos = stop + 1
    end
  end
  local indent = line:match('^[ \t]*', pos)
  return line:sub(pos + #indent), lineparse.ws_width(indent, opts.tabstop or 8)
end

local function fence_run(body)
  return body:match('^(`+)') or body:match('^(~+)')
end

--- Classify one line and advance the scanner state.
--- @return '"code"'|'"code_indent"'|'"blank"'|'"list"'|'"continuation"'|'"text"'
local function step(carry, line, opts)
  local body, width = strip(line, opts)
  local kind

  if carry.fence then
    kind = 'code'
    local run = fence_run(body)
    if
      run
      and run:sub(1, 1) == carry.fence.char
      and #run >= carry.fence.len
      and body:sub(#run + 1):match('^[ \t]*$')
    then
      carry.fence = nil
    end
  elseif body == '' then
    kind = 'blank'
    carry.blank_run = carry.blank_run + 1
    -- A single blank line does not end a list, so an indented line after it is
    -- still list content rather than an indented code block.
    if carry.blank_run >= 2 then
      carry.list_active = false
    end
  else
    carry.blank_run = 0
    local run = fence_run(body)
    if run and #run >= 3 then
      carry.fence = { char = run:sub(1, 1), len = #run }
      kind = 'code'
    else
      -- An indented code block has to be recognised before the marker is
      -- looked at, because `    - x` is code there rather than a list item.
      -- Unlike CommonMark, the start of the buffer does not open one: a file
      -- whose first line is an indented list item is far more likely to be a
      -- fragment of a list than a code block.
      if
        not carry.list_active
        and width >= 4
        and (carry.prev == 'blank' or carry.prev == 'code_indent')
      then
        kind = 'code_indent'
      else
        local parsed = lineparse.parse(line, opts)
        if parsed.marker then
          kind = 'list'
          carry.list_active = true
          carry.list_indent = parsed.indent_width
        elseif carry.list_active and width > carry.list_indent then
          kind = 'continuation'
        else
          kind = 'text'
          carry.list_active = false
        end
      end
    end
  end

  carry.prev = kind
  return kind
end

local function invalidate(cache, first)
  local anchor = math.floor((first - 1) / SNAPSHOT_EVERY) * SNAPSHOT_EVERY + 1
  for lnum in pairs(cache.snapshots) do
    if lnum > anchor then
      cache.snapshots[lnum] = nil
    end
  end
  if cache.valid >= anchor then
    local snapshot = cache.snapshots[anchor]
    if snapshot then
      cache.valid = anchor - 1
      cache.carry = copy_carry(snapshot)
    else
      cache.valid = 0
      cache.carry = initial_carry()
    end
  end
end

local function get_cache(bufnr)
  local cache = caches[bufnr]
  if cache then
    return cache
  end
  cache = { kinds = {}, snapshots = { [1] = initial_carry() }, valid = 0, carry = initial_carry() }
  caches[bufnr] = cache
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, _, firstline)
      local current = caches[buf]
      if not current then
        return true
      end
      invalidate(current, firstline + 1)
    end,
    on_reload = function(_, buf)
      caches[buf] = nil
      return true
    end,
    on_detach = function(_, buf)
      caches[buf] = nil
    end,
  })
  return cache
end

local function ensure(cache, bufnr, lnum, opts)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local target = math.min(lnum, total)
  if cache.valid >= target then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, cache.valid, target, false)
  local at = cache.valid + 1
  for _, line in ipairs(lines) do
    if (at - 1) % SNAPSHOT_EVERY == 0 then
      cache.snapshots[at] = copy_carry(cache.carry)
    end
    cache.kinds[at] = step(cache.carry, line, opts)
    at = at + 1
  end
  cache.valid = target
end

--- @param bufnr integer
--- @param lnum integer 1-based
--- @param opts table
--- @return string
function M.kind(bufnr, lnum, opts)
  local cache = get_cache(bufnr)
  ensure(cache, bufnr, lnum, opts)
  return cache.kinds[lnum] or 'text'
end

--- @param bufnr integer
--- @param lnum integer 1-based
--- @param opts table
--- @return boolean
function M.is_code(bufnr, lnum, opts)
  if not opts.code_blocks then
    return false
  end
  local kind = M.kind(bufnr, lnum, opts)
  return kind == 'code' or kind == 'code_indent'
end

--- Drop the cache for a buffer. Only needed by tests.
function M.reset(bufnr)
  if bufnr then
    caches[bufnr] = nil
  else
    caches = {}
  end
end

return M
