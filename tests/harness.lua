--- A small test harness, so that the suite runs with nothing but Neovim.
--- Every case drives a real buffer, as NFR-5 requires.
local M = { passed = 0, failures = {}, group = nil }

local function label(name)
  return (M.group and (M.group .. ' / ') or '') .. name
end

function M.describe(name, fn)
  local outer = M.group
  M.group = outer and (outer .. ' / ' .. name) or name
  fn()
  M.group = outer
end

function M.it(name, fn)
  local full = label(name)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
  else
    M.failures[#M.failures + 1] = full
    io.write('FAIL  ' .. full .. '\n')
    io.write('      ' .. tostring(err):gsub('\n', '\n      ') .. '\n')
  end
end

local function render(value)
  if type(value) == 'table' then
    local out = {}
    for i, v in ipairs(value) do
      out[i] = string.format('%d: %q', i, tostring(v))
    end
    return '\n' .. table.concat(out, '\n')
  end
  return string.format('%q', tostring(value))
end

local function same(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if not same(a[i], b[i]) then
      return false
    end
  end
  return true
end

function M.eq(expected, actual, note)
  if not same(expected, actual) then
    error(
      (note and (note .. '\n') or '')
        .. 'expected: '
        .. render(expected)
        .. '\nactual:   '
        .. render(actual),
      2
    )
  end
end

function M.truthy(value, note)
  if not value then
    error(note or 'expected a truthy value, got ' .. tostring(value), 2)
  end
end

function M.falsy(value, note)
  if value then
    error(note or 'expected a falsy value, got ' .. tostring(value), 2)
  end
end

--- Fresh buffer with the given lines. Indentation is four spaces, matching the
--- examples in the requirements.
function M.buf(lines, filetype)
  vim.cmd('enew!')
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].filetype = filetype or 'markdown'
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].tabstop = 4
  vim.bo[bufnr].shiftwidth = 4
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  -- Close the undo block that filling the buffer opened. Without this the setup
  -- and whatever the test does next merge into one, and an undo test cannot
  -- tell them apart.
  vim.cmd('let &l:undolevels = &l:undolevels')
  require('autolist.context').reset(bufnr)
  return bufnr
end

function M.lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
end

function M.cursor(lnum, col)
  vim.api.nvim_win_set_cursor(0, { lnum, col })
end

--- Put the cursor at the end of a line, which is where most of the newline
--- examples in the requirements start from.
function M.cursor_eol(lnum)
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
  vim.api.nvim_win_set_cursor(0, { lnum, #line })
end

function M.report()
  io.write(string.format('\n%d passed, %d failed\n', M.passed, #M.failures))
  return #M.failures == 0
end

return M
