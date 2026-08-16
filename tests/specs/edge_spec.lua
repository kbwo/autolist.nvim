local T = _G.T
local autolist = require('autolist')

T.describe('indentation written with tabs', function()
  T.it('continues a tab-indented item with the same indent', function()
    local buf = T.buf({ '\t1. あ' })
    vim.bo[buf].expandtab = false
    T.cursor_eol(1)
    autolist.newline()
    T.eq({ '\t1. あ', '\t2. ' }, T.lines(buf))
  end)

  T.it('indents with a tab when the buffer does not expand them', function()
    local buf = T.buf({ '- あ', '- い' })
    vim.bo[buf].expandtab = false
    T.cursor(2, 0)
    autolist.indent()
    T.eq({ '- あ', '\t- い' }, T.lines(buf))
  end)

  T.it('nests tabs and spaces by depth, not by character count', function()
    local buf = T.buf({ '1. 親', '\t5. 子', '    9. 子', '3. 親' })
    T.cursor(1, 0)
    autolist.renumber()
    -- A tab and four spaces are both four columns wide here, so both children
    -- sit at the same level.
    T.eq({ '1. 親', '\t5. 子', '    6. 子', '2. 親' }, T.lines(buf))
  end)
end)

T.describe('blockquote depth', function()
  T.it('keeps lists at different depths in separate blocks', function()
    local buf = T.buf({ '> 1. あ', '> > 5. い', '> 9. う' })
    T.cursor(1, 0)
    autolist.renumber()
    T.eq({ '> 1. あ', '> > 5. い', '> 9. う' }, T.lines(buf))

    T.cursor(3, 0)
    T.falsy(autolist.renumber(), 'a single-item block has nothing to fix')
  end)
end)

T.describe('lists that mix marker kinds', function()
  T.it('counts only the ordered items of a level', function()
    local buf = T.buf({ '- あ', '1. い', '7. う' })
    T.cursor(1, 0)
    autolist.renumber()
    T.eq({ '- あ', '1. い', '2. う' }, T.lines(buf))
  end)
end)

T.describe('list bounded by other content', function()
  T.it('does not renumber past a thematic break', function()
    local buf = T.buf({ '1. あ', '---', '5. い', '9. う' })
    T.cursor(3, 0)
    autolist.renumber()
    T.eq({ '1. あ', '---', '5. い', '6. う' }, T.lines(buf))
  end)

  T.it('continues a list that sits at the very end of the buffer', function()
    local buf = T.buf({ 'text', '', '1. あ' })
    T.cursor_eol(3)
    autolist.newline()
    T.eq({ 'text', '', '1. あ', '2. ' }, T.lines(buf))
  end)
end)
