--- Checks that a mapping can hand the key on to another plugin's <Plug>
--- mapping when autolist declines it (NFR-2). delimitMate's <Plug>delimitMateCR
--- is the case this stands in for.
local T = _G.T

local function setup(buf)
  -- Stand-in for another plugin that owns <CR>.
  vim.keymap.set('i', '<Plug>OtherCR', function()
    vim.api.nvim_put({ '', 'FROM-OTHER' }, 'c', false, true)
  end, {})
  vim.keymap.set('i', '<CR>', function()
    return require('autolist').cr() or '<Plug>OtherCR'
  end, { buffer = buf, expr = true, remap = true })
end

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('falling through to another plugin', function()
  T.it('runs autolist on a list line', function()
    local buf = T.buf({ '- apple' })
    setup(buf)
    type_keys('A<CR>banana<Esc>')
    T.eq({ '- apple', '- banana' }, T.lines(buf))
  end)

  T.it('hands the key to the other plugin elsewhere', function()
    local buf = T.buf({ 'hello' })
    setup(buf)
    type_keys('A<CR><Esc>')
    T.eq({ 'hello', 'FROM-OTHER' }, T.lines(buf))
  end)

  T.it('exposes the prefix test for non-expr callers', function()
    T.buf({ '- a', '- b' })
    T.cursor(2, 0)
    T.truthy(require('autolist').at_item_prefix(), 'cursor on the marker')
    T.cursor(2, #'- b')
    T.falsy(require('autolist').at_item_prefix(), 'cursor in the content')
    T.buf({ 'hello' })
    T.cursor(1, 0)
    T.falsy(require('autolist').at_item_prefix(), 'not a list line')
  end)

  T.it('is not disturbed by remap being on', function()
    -- The <Cmd> sequence autolist returns must survive a remapping mapping:
    -- its trailing <CR> must not be fed back through this same mapping.
    local buf = T.buf({ '1. a' })
    setup(buf)
    type_keys('A<CR>b<Esc>')
    T.eq({ '1. a', '2. b' }, T.lines(buf))
  end)
end)
