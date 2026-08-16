local T = _G.T
local autolist = require('autolist')
local context = require('autolist.context')
local config = require('autolist.config')

local function kinds(buf)
  local opts = config.get(buf)
  local out = {}
  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    out[lnum] = context.kind(buf, lnum, opts)
  end
  return out
end

T.describe('FR-7 contexts that are not lists', function()
  T.it('stays out of a fenced code block', function()
    local buf = T.buf({ 'text', '```sh', '- not a list', '```', '- a list' })
    T.eq({ 'text', 'code', 'code', 'code', 'list' }, kinds(buf))
    T.cursor_eol(3)
    T.falsy(autolist.newline())
    T.falsy(autolist.renumber())
    T.cursor_eol(5)
    T.truthy(autolist.newline())
  end)

  T.it('handles tilde fences and fences inside a blockquote', function()
    local buf = T.buf({ '~~~', '- x', '~~~' })
    T.eq({ 'code', 'code', 'code' }, kinds(buf))

    buf = T.buf({ '> ```', '> - x', '> ```' })
    T.eq({ 'code', 'code', 'code' }, kinds(buf))
  end)

  T.it('stays out of an indented code block', function()
    local buf = T.buf({ 'paragraph', '', '    - not a list', '', 'end' })
    T.eq({ 'text', 'blank', 'code_indent', 'blank', 'text' }, kinds(buf))
    T.cursor_eol(3)
    T.falsy(autolist.newline())
  end)

  T.it('does not mistake nested list items for indented code', function()
    local buf = T.buf({ '- a', '    - b', '', '    - c' })
    T.eq({ 'list', 'list', 'blank', 'list' }, kinds(buf))
  end)

  T.it('does not treat emphasis or a thematic break as a marker', function()
    local buf = T.buf({ '*bold* text', '---', 'see 1. below' })
    for lnum = 1, 3 do
      T.cursor_eol(lnum)
      T.falsy(autolist.newline(), 'line ' .. lnum)
    end
    T.eq({ '*bold* text', '---', 'see 1. below' }, T.lines(buf))
  end)

  T.it('re-reads the buffer after an edit above the cursor', function()
    local buf = T.buf({ '- a', '- b' })
    T.eq('list', kinds(buf)[2])
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '```' })
    T.eq({ 'code', 'code', 'code' }, kinds(buf))
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
    T.eq({ 'list', 'list' }, kinds(buf))
  end)
end)
