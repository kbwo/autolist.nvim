--- Binding a key to the checkbox toggle while keeping that key's normal
--- behaviour elsewhere. `toggle_checkbox()` already reports whether it acted,
--- so this needs nothing from the plugin beyond the mapping itself.
local T = _G.T

local function setup(buf)
  vim.keymap.set('n', '<CR>', function()
    if not require('autolist').toggle_checkbox() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
    end
  end, { buffer = buf })
end

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('<CR> on a checkbox line', function()
  T.it('checks an unchecked box', function()
    local buf = T.buf({ '- [ ] todo' })
    setup(buf)
    T.cursor(1, 0)
    type_keys('<CR>')
    T.eq({ '- [x] todo' }, T.lines(buf))
  end)

  T.it('unchecks it again', function()
    local buf = T.buf({ '- [x] done' })
    setup(buf)
    T.cursor(1, 0)
    type_keys('<CR>')
    T.eq({ '- [ ] done' }, T.lines(buf))
  end)

  T.it('works from anywhere on the line', function()
    local buf = T.buf({ '    - [ ] nested todo' })
    setup(buf)
    T.cursor(1, #'    - [ ] nested')
    type_keys('<CR>')
    T.eq({ '    - [x] nested todo' }, T.lines(buf))
  end)

  T.it('leaves a list item without a checkbox alone and moves on', function()
    local buf = T.buf({ '- plain', '- second' })
    setup(buf)
    T.cursor(1, 0)
    type_keys('<CR>')
    T.eq({ '- plain', '- second' }, T.lines(buf))
    T.eq(2, vim.api.nvim_win_get_cursor(0)[1], '<CR> did its usual job')
  end)

  T.it('behaves normally on a line that is not a list', function()
    local buf = T.buf({ 'paragraph', 'next line' })
    setup(buf)
    T.cursor(1, 0)
    type_keys('<CR>')
    T.eq({ 'paragraph', 'next line' }, T.lines(buf))
    T.eq(2, vim.api.nvim_win_get_cursor(0)[1])
  end)

  T.it('does nothing inside a code block', function()
    local buf = T.buf({ '```', '- [ ] not a task', '```' })
    setup(buf)
    T.cursor(2, 0)
    type_keys('<CR>')
    T.eq({ '```', '- [ ] not a task', '```' }, T.lines(buf))
  end)
end)
