local T = _G.T
local autolist = require('autolist')

T.describe('FR-6 converting the marker style', function()
  T.it('walks the configured order and wraps around', function()
    local buf = T.buf({ '- あ' })
    T.cursor(1, 0)
    local seen = {}
    for _ = 1, 7 do
      autolist.cycle_markers()
      seen[#seen + 1] = T.lines(buf)[1]
    end
    T.eq({ '* あ', '1. あ', '1) あ', 'a) あ', 'I. あ', '- あ', '* あ' }, seen)
  end)

  T.it('numbers the whole block when it becomes ordered', function()
    local buf = T.buf({ '- あ', '- い', '- う' })
    T.cursor(1, 0)
    autolist.cycle_markers() -- '-' -> '*'
    autolist.cycle_markers() -- '*' -> '1.'
    T.eq({ '1. あ', '2. い', '3. う' }, T.lines(buf))
  end)

  T.it('numbers each level from the start', function()
    local buf = T.buf({ '- 親', '    - 子', '    - 子', '- 親' })
    T.cursor(1, 0)
    autolist.cycle_markers()
    autolist.cycle_markers()
    T.eq({ '1. 親', '    1. 子', '    2. 子', '2. 親' }, T.lines(buf))
  end)

  T.it('converts a list that repeats one number too', function()
    local buf = T.buf({ '1. あ', '1. い', '1. う' })
    T.cursor(1, 0)
    autolist.cycle_markers() -- '1.' -> '1)'
    T.eq({ '1) あ', '2) い', '3) う' }, T.lines(buf))
  end)

  T.it('keeps checkboxes and blockquote markers', function()
    local buf = T.buf({ '> - [x] a', '> - [ ] b' })
    T.cursor(1, 0)
    autolist.cycle_markers()
    autolist.cycle_markers()
    T.eq({ '> 1. [x] a', '> 2. [ ] b' }, T.lines(buf))
  end)

  T.it('does nothing outside a list', function()
    local buf = T.buf({ 'paragraph' })
    T.cursor(1, 0)
    T.falsy(autolist.cycle_markers())
    T.eq({ 'paragraph' }, T.lines(buf))
  end)
end)
