local T = _G.T
local autolist = require('autolist')

T.describe('FR-6 converting the marker style', function()
  T.it('walks the configured order and wraps around', function()
    local buf = T.buf({ '- あ' })
    T.cursor(1, 0)
    local seen = {}
    for _ = 1, 8 do
      autolist.cycle_markers_block()
      seen[#seen + 1] = T.lines(buf)[1]
    end
    T.eq({
      '- [ ] あ',
      '* あ',
      '1. あ',
      '1) あ',
      'a) あ',
      'I. あ',
      '- あ',
      '- [ ] あ',
    }, seen)
  end)

  T.it('numbers the whole block when it becomes ordered', function()
    local buf = T.buf({ '- あ', '- い', '- う' })
    T.cursor(1, 0)
    autolist.cycle_markers_block() -- '-' -> '- [ ]'
    autolist.cycle_markers_block() -- '- [ ]' -> '*'
    autolist.cycle_markers_block() -- '*' -> '1.'
    T.eq({ '1. あ', '2. い', '3. う' }, T.lines(buf))
  end)

  T.it('converts a list that repeats one number too', function()
    local buf = T.buf({ '1. あ', '1. い', '1. う' })
    T.cursor(1, 0)
    autolist.cycle_markers_block() -- '1.' -> '1)'
    T.eq({ '1) あ', '2) い', '3) う' }, T.lines(buf))
  end)

  T.it('walks backwards too', function()
    local buf = T.buf({ '1. あ' })
    T.cursor(1, 0)
    local seen = {}
    for _ = 1, 4 do
      autolist.cycle_markers_block({ reverse = true })
      seen[#seen + 1] = T.lines(buf)[1]
    end
    T.eq({ '* あ', '- [ ] あ', '- あ', 'I. あ' }, seen)
  end)

  T.it('comes straight back from a step too far', function()
    local buf = T.buf({ '- a', '- b' })
    T.cursor(1, 0)
    autolist.cycle_markers_block()
    autolist.cycle_markers_block()
    T.eq({ '* a', '* b' }, T.lines(buf))
    autolist.cycle_markers_block({ reverse = true })
    T.eq({ '- [ ] a', '- [ ] b' }, T.lines(buf))
    autolist.cycle_markers_block({ reverse = true })
    T.eq({ '- a', '- b' }, T.lines(buf))
  end)

  T.it('reverses the sibling scope as well', function()
    local buf = T.buf({ '- 親', '    1. 子', '    2. 子', '- 親' })
    T.cursor(2, 0)
    autolist.cycle_markers_siblings({ reverse = true })
    T.eq({ '- 親', '    * 子', '    * 子', '- 親' }, T.lines(buf))
  end)

  T.it('starts from the beginning of the cycle for an unlisted style', function()
    for _, reverse in ipairs({ false, true }) do
      local buf = T.buf({ '+ あ' })
      T.cursor(1, 0)
      autolist.cycle_markers_block({ reverse = reverse })
      T.eq({ '- あ' }, T.lines(buf), 'reverse=' .. tostring(reverse))
    end
  end)

  T.it('does nothing outside a list', function()
    local buf = T.buf({ 'paragraph' })
    T.cursor(1, 0)
    T.falsy(autolist.cycle_markers_block())
    T.eq({ 'paragraph' }, T.lines(buf))
  end)
end)

T.describe('FR-6 checkboxes are part of the style', function()
  T.it('adds an unchecked box to items that have none', function()
    local buf = T.buf({ '- 買い物', '- 洗濯' })
    T.cursor(1, 0)
    autolist.cycle_markers_block()
    T.eq({ '- [ ] 買い物', '- [ ] 洗濯' }, T.lines(buf))
  end)

  T.it('keeps the tick of items that already have one', function()
    local buf = T.buf({ '* [x] 済み', '* [ ] 未' })
    T.cursor(1, 0)
    -- '* [x]' is not in the cycle, so this lands on its start, which has no box.
    autolist.cycle_markers_block()
    T.eq({ '- 済み', '- 未' }, T.lines(buf))
    -- and on to '- [ ]', which gives every item a fresh unchecked box
    autolist.cycle_markers_block()
    T.eq({ '- [ ] 済み', '- [ ] 未' }, T.lines(buf))
  end)

  T.it('preserves a tick when moving between two boxed styles', function()
    autolist.setup({ filetypes = { markdown = { cycle = { '- [ ]', '1. [ ]' } } } })
    local ok, err = pcall(function()
      local buf = T.buf({ '- [x] 済み', '- [ ] 未' })
      T.cursor(1, 0)
      autolist.cycle_markers_block()
      T.eq({ '1. [x] 済み', '2. [ ] 未' }, T.lines(buf))
    end)
    autolist.setup({})
    if not ok then
      error(err, 0)
    end
  end)

  T.it('drops the box when the next style has none', function()
    local buf = T.buf({ '- [x] 済み' })
    T.cursor(1, 0)
    autolist.cycle_markers_block() -- '- [ ]' -> '*'
    T.eq({ '* 済み' }, T.lines(buf))
  end)

  T.it('keeps blockquote markers while adding a box', function()
    local buf = T.buf({ '> - a', '> - b' })
    T.cursor(1, 0)
    autolist.cycle_markers_block()
    T.eq({ '> - [ ] a', '> - [ ] b' }, T.lines(buf))
  end)
end)

T.describe('FR-6 choosing what to convert', function()
  local nested = { '- 親', '    - 子', '    - 子', '- 親' }

  T.it('block: converts every level', function()
    local buf = T.buf(nested)
    T.cursor(1, 0)
    autolist.cycle_markers_block()
    autolist.cycle_markers_block()
    autolist.cycle_markers_block()
    T.eq({ '1. 親', '    1. 子', '    2. 子', '2. 親' }, T.lines(buf))
  end)

  T.it('siblings: converts only the run at the cursor', function()
    local buf = T.buf(nested)
    T.cursor(2, 0) -- on a child
    autolist.cycle_markers_siblings()
    autolist.cycle_markers_siblings()
    autolist.cycle_markers_siblings()
    T.eq({ '- 親', '    1. 子', '    2. 子', '- 親' }, T.lines(buf))
  end)

  T.it('siblings: leaves the children when run on a parent', function()
    local buf = T.buf(nested)
    T.cursor(1, 0)
    autolist.cycle_markers_siblings()
    T.eq({ '- [ ] 親', '    - 子', '    - 子', '- [ ] 親' }, T.lines(buf))
  end)

  T.it('siblings: takes its cue from the first item of that run', function()
    local buf = T.buf({ '1. 親', '    * 子', '    * 子' })
    T.cursor(2, 0)
    autolist.cycle_markers_siblings() -- '*' -> '1.'
    T.eq({ '1. 親', '    1. 子', '    2. 子' }, T.lines(buf))
  end)

  T.it('siblings: numbers that run from one', function()
    local buf = T.buf({ '- a', '    - x', '    - y', '    - z' })
    T.cursor(3, 0)
    autolist.cycle_markers_siblings()
    autolist.cycle_markers_siblings()
    autolist.cycle_markers_siblings()
    T.eq({ '- a', '    1. x', '    2. y', '    3. z' }, T.lines(buf))
  end)
end)
