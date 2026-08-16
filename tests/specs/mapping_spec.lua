--- Drives the plugin the way a user would: through an expression mapping, with
--- real keystrokes, checking that one action costs one undo (NFR-3).
local T = _G.T

local function map(buf)
  vim.keymap.set('i', '<CR>', function()
    return require('autolist').cr() or '<CR>'
  end, { expr = true, buffer = buf })
  vim.keymap.set('i', '<Tab>', function()
    return require('autolist').tab() or '<Tab>'
  end, { expr = true, buffer = buf })
end

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('as a mapping', function()
  T.it('continues the list when <CR> is pressed', function()
    local buf = T.buf({ '- apple' })
    map(buf)
    type_keys('A<CR>banana<Esc>')
    T.eq({ '- apple', '- banana' }, T.lines(buf))
  end)

  T.it('takes one undo to reverse (NFR-3)', function()
    local buf = T.buf({ '- apple' })
    map(buf)
    type_keys('A<CR>banana<Esc>')
    T.eq({ '- apple', '- banana' }, T.lines(buf))
    vim.cmd('silent undo')
    T.eq({ '- apple' }, T.lines(buf))
  end)

  T.it('one undo also reverses leaving the list', function()
    local buf = T.buf({ '- apple', '- ' })
    map(buf)
    T.cursor_eol(2)
    type_keys('a<CR><Esc>')
    T.eq({ '- apple', '' }, T.lines(buf))
    vim.cmd('silent undo')
    T.eq({ '- apple', '- ' }, T.lines(buf))
  end)

  T.it('passes <CR> through on a line that is not an item (FR-8)', function()
    local buf = T.buf({ 'paragraph' })
    map(buf)
    type_keys('A<CR>more<Esc>')
    T.eq({ 'paragraph', 'more' }, T.lines(buf))
  end)

  T.it('indents from the marker but types a tab inside the content', function()
    local buf = T.buf({ '- a', '- b' })
    map(buf)
    T.cursor(2, 0)
    type_keys('i<Tab><Esc>')
    T.eq({ '- a', '    - b' }, T.lines(buf))

    -- With the cursor in the content the key does what it always does: here,
    -- 'expandtab' with a tabstop of four fills up to the next stop.
    T.cursor_eol(2)
    type_keys('a<Tab><Esc>')
    T.eq({ '- a', '    - b ' }, T.lines(buf))
  end)

  T.it('takes one undo to reverse a command (NFR-3)', function()
    local buf = T.buf({ '1. あ', '5. い', '2. う' })
    T.cursor(1, 0)
    vim.cmd('AutolistRenumber')
    T.eq({ '1. あ', '2. い', '3. う' }, T.lines(buf))
    vim.cmd('silent undo')
    T.eq({ '1. あ', '5. い', '2. う' }, T.lines(buf))
  end)

  T.it('takes one undo to reverse an indent (NFR-3)', function()
    local buf = T.buf({ '1. あ', '2. い', '3. う' })
    T.cursor(2, 0)
    vim.cmd('AutolistIndent')
    T.eq({ '1. あ', '    1. い', '2. う' }, T.lines(buf))
    vim.cmd('silent undo')
    T.eq({ '1. あ', '2. い', '3. う' }, T.lines(buf))
  end)
end)
