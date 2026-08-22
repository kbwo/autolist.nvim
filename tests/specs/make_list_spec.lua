local T = _G.T
local autolist = require('autolist')

T.describe('FR-9 turning plain lines into a list', function()
  T.it('marks the cursor line by default', function()
    local buf = T.buf({ 'ccmanager', 'other' })
    T.cursor(1, 0)
    T.truthy(autolist.make_list())
    T.eq({ '- ccmanager', 'other' }, T.lines(buf))
  end)

  T.it('keeps the indentation that already carries the nesting', function()
    local buf = T.buf({
      'ccmanager',
      '\t設定用のskillを用意',
      '\tworktreeを消せるように',
      '2d 3dを切り替えられるゲーム',
    })
    autolist.make_list(1, 4)
    T.eq({
      '- ccmanager',
      '\t- 設定用のskillを用意',
      '\t- worktreeを消せるように',
      '- 2d 3dを切り替えられるゲーム',
    }, T.lines(buf))
  end)

  T.it('works with spaces just as well as tabs', function()
    local buf = T.buf({ 'parent', '    child', '        grandchild' })
    autolist.make_list(1, 3)
    T.eq({ '- parent', '    - child', '        - grandchild' }, T.lines(buf))
  end)

  T.it('leaves lines that are already items alone', function()
    local buf = T.buf({ '- already', 'plain', '1. numbered' })
    autolist.make_list(1, 3)
    T.eq({ '- already', '- plain', '1. numbered' }, T.lines(buf))
  end)

  T.it('leaves blank lines and thematic breaks alone', function()
    local buf = T.buf({ 'a', '', '---', 'b' })
    autolist.make_list(1, 4)
    T.eq({ '- a', '', '---', '- b' }, T.lines(buf))
  end)

  T.it('stays out of code blocks', function()
    local buf = T.buf({ 'before', '```', 'code line', '```', 'after' })
    autolist.make_list(1, 5)
    T.eq({ '- before', '```', 'code line', '```', '- after' }, T.lines(buf))
  end)

  T.it('keeps blockquote markers', function()
    local buf = T.buf({ '> quoted note', '>   deeper' })
    autolist.make_list(1, 2)
    T.eq({ '> - quoted note', '>   - deeper' }, T.lines(buf))
  end)

  T.it('reports that it did nothing when there is nothing to mark', function()
    local buf = T.buf({ '- a', '- b' })
    T.falsy(autolist.make_list(1, 2))
    T.eq({ '- a', '- b' }, T.lines(buf))
  end)

  T.it('does nothing in a buffer of another filetype', function()
    local buf = T.buf({ 'plain' }, 'python')
    T.falsy(autolist.make_list(1, 1))
    T.eq({ 'plain' }, T.lines(buf))
  end)

  T.it('takes one undo to reverse (NFR-3)', function()
    local buf = T.buf({ 'a', '\tb', 'c' })
    autolist.make_list(1, 3)
    T.eq({ '- a', '\t- b', '- c' }, T.lines(buf))
    vim.cmd('silent undo')
    T.eq({ 'a', '\tb', 'c' }, T.lines(buf))
  end)

  T.it('is reachable as a command with a range', function()
    local buf = T.buf({ 'a', 'b', 'c' })
    vim.cmd('2,3AutolistMakeList')
    T.eq({ 'a', '- b', '- c' }, T.lines(buf))
  end)

  T.it('numbers each level from one when the style is ordered', function()
    autolist.setup({ filetypes = { markdown = { cycle = { '1.', '-' } } } })
    local ok, err = pcall(function()
      local buf = T.buf({ 'a', '\tx', '\ty', 'b', '\tp' })
      autolist.make_list(1, 5)
      T.eq({ '1. a', '\t1. x', '\t2. y', '2. b', '\t1. p' }, T.lines(buf))
    end)
    autolist.setup({})
    if not ok then
      error(err, 0)
    end
  end)

  T.it('composes with the marker cycle for other styles', function()
    local buf = T.buf({ 'a', 'b' })
    autolist.make_list(1, 2)
    T.cursor(1, 0)
    autolist.cycle_markers_block() -- '-' -> '- [ ]'
    autolist.cycle_markers_block() -- '- [ ]' -> '*'
    autolist.cycle_markers_block() -- '*' -> '1.'
    T.eq({ '1. a', '2. b' }, T.lines(buf))
  end)
end)
