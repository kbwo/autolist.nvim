local T = _G.T
local lineparse = require('autolist.line')
local numbering = require('autolist.numbering')

local opts = { tabstop = 4, expandtab = true, blockquote = true }

local function parse(line)
  return lineparse.parse(line, opts)
end

T.describe('line parsing', function()
  T.it('reads a bullet item', function()
    local item = parse('- apple')
    T.eq('bullet', item.marker.kind)
    T.eq('-', item.marker.text)
    T.eq('apple', item.content)
    T.eq('- ', item.prefix)
    T.falsy(item.empty)
  end)

  T.it('reads an ordered item and keeps its delimiter', function()
    for _, case in ipairs({ { '1. a', '.' }, { '2) a', ')' } }) do
      local item = parse(case[1])
      T.eq('numeric', item.marker.kind)
      T.eq(case[2], item.marker.delim)
    end
  end)

  T.it('measures indent by display width so tabs and spaces mix', function()
    T.eq(4, parse('    - a').indent_width)
    T.eq(4, parse('\t- a').indent_width)
  end)

  T.it('treats an item with no content as empty, checkbox or not', function()
    T.truthy(parse('- ').empty)
    T.truthy(parse('-').empty)
    T.truthy(parse('- [ ] ').empty)
    T.truthy(parse('- [x]').empty)
    T.falsy(parse('- [ ] x').empty)
  end)

  T.it('takes the blockquote marker as part of the prefix', function()
    local item = parse('> - apple')
    T.eq(1, item.quote_depth)
    T.eq('>', item.quote)
    T.eq('bullet', item.marker.kind)
    T.eq('apple', item.content)
  end)

  T.it('round-trips any line it parses', function()
    for _, line in ipairs({
      '- apple',
      '  1) [x] done',
      '> > IV. deep',
      '\ta. tabbed',
      'plain text',
      '   continuation',
      '',
    }) do
      T.eq(line, lineparse.render(parse(line)), 'round trip of ' .. string.format('%q', line))
    end
  end)
end)

T.describe('things that only look like markers (FR-7)', function()
  T.it('ignores emphasis', function()
    T.eq(nil, parse('*bold*').marker)
    T.eq(nil, parse('*bold* and more').marker)
  end)

  T.it('ignores thematic breaks', function()
    for _, line in ipairs({ '---', '***', '___', '- - -', '* * *' }) do
      T.eq(nil, parse(line).marker, line)
      T.truthy(parse(line).thematic_break, line)
    end
  end)

  T.it('ignores a number that is not at the start of the line', function()
    T.eq(nil, parse('see 1. below').marker)
  end)

  T.it('needs whitespace after the marker', function()
    T.eq(nil, parse('1.5 apples').marker)
    T.eq(nil, parse('-apple').marker)
  end)

  T.it('still accepts a marker that ends the line', function()
    T.eq('numeric', parse('1.').marker.kind)
    T.eq('bullet', parse('-').marker.kind)
  end)
end)

T.describe('letters and Roman numerals', function()
  T.it('reads unambiguous words by their spelling', function()
    T.eq('roman', parse('IV. a').marker.kind)
    T.eq(4, parse('IV. a').marker.value)
    T.eq('alpha', parse('ab) a').marker.kind)
    T.eq(28, parse('ab) a').marker.value)
  end)

  T.it('reads a single ambiguous letter by its case, and says so', function()
    local upper = parse('I. a').marker
    T.eq('roman', upper.kind)
    T.truthy(upper.ambiguous)
    local lower = parse('i. a').marker
    T.eq('alpha', lower.kind)
    T.truthy(lower.ambiguous)
  end)

  T.it('rejects mixed case and non-canonical numerals', function()
    T.eq(nil, parse('Ab. a').marker)
    T.eq('alpha', parse('iix. a').marker.kind)
  end)

  T.it('converts both ways', function()
    T.eq('IV', numbering.to_roman(4, true))
    T.eq('iv', numbering.to_roman(4, false))
    T.eq(4, numbering.from_roman('iv'))
    T.eq('aa', numbering.to_alpha(27, false))
    T.eq(27, numbering.from_alpha('AA'))
  end)
end)
