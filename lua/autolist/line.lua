--- Parsing and rendering of a single line.
---
--- A list line is understood as
---
---     <quote><indent><marker><space>[<checkbox><space>]<content>
---
--- Every field is kept verbatim so that a parsed line can be rendered back
--- byte for byte, and so that an edit only changes the field it targets.
local M = {}

local numbering = require('autolist.numbering')

--- @class autolist.Marker
--- @field kind '"bullet"'|'"numeric"'|'"alpha"'|'"roman"'
--- @field text string     raw marker text without the delimiter (`-`, `12`, `iv`)
--- @field delim string    `.` or `)`; empty for bullets
--- @field value integer|nil ordinal value; nil for bullets
--- @field upper boolean   letter case, for alpha and roman markers
--- @field ambiguous boolean single letter that is both a letter and a Roman numeral

--- @class autolist.Line
--- @field text string          the line as it is in the buffer
--- @field quote string         leading blockquote markers, e.g. `> >`
--- @field quote_depth integer  number of `>` consumed
--- @field indent string        whitespace between the quote and the marker
--- @field indent_width integer display width of `indent`, tabs expanded
--- @field body string          everything after `indent`
--- @field blank boolean        nothing but whitespace (and quote markers)
--- @field thematic_break boolean `---`, `***`, `___`
--- @field marker autolist.Marker|nil nil when the line is not a list item
--- @field marker_text string|nil marker as written, delimiter included
--- @field space string|nil     whitespace after the marker
--- @field checkbox string|nil  the character between the brackets
--- @field checkbox_space string|nil whitespace after `]`
--- @field content string|nil   the item content
--- @field prefix string|nil    everything before `content`
--- @field empty boolean|nil    content is empty or whitespace only

--- @param ws string
--- @param tabstop integer
--- @return integer
function M.ws_width(ws, tabstop)
  local w = 0
  for i = 1, #ws do
    if ws:sub(i, i) == '\t' then
      w = w + tabstop - (w % tabstop)
    else
      w = w + 1
    end
  end
  return w
end

--- Build an indent string of the requested display width, following the
--- buffer's 'expandtab' and 'tabstop'.
--- @param width integer
--- @param opts table
--- @return string
function M.make_indent(width, opts)
  if width <= 0 then
    return ''
  end
  if opts.expandtab then
    return string.rep(' ', width)
  end
  local ts = opts.tabstop
  return string.rep('\t', math.floor(width / ts)) .. string.rep(' ', width % ts)
end

--- The characters markdown itself uses inside a checkbox. Configured ones are
--- added to these, so that a buffer written by someone else still reads.
local DEFAULT_CHECKBOX_CLASS = ' xX'

local function class_escape(char)
  return char:match('%w') and char or ('%' .. char)
end

--- Build the character class matching the inside of a checkbox.
--- @param checkbox table|nil `{ checked = ..., unchecked = ... }`
--- @return string
function M.checkbox_class(checkbox)
  local seen, out = {}, {}
  for _, char in ipairs({
    ' ',
    'x',
    'X',
    checkbox and checkbox.checked,
    checkbox and checkbox.unchecked,
  }) do
    if char and #char == 1 and not seen[char] then
      seen[char] = true
      out[#out + 1] = class_escape(char)
    end
  end
  return table.concat(out)
end

--- Decide whether a run of letters is alphabetic or a Roman numeral.
--- A single letter can be read either way (`i`, `V`); such markers are flagged
--- as ambiguous so that callers can settle them from their siblings, and are
--- read by case in the meantime.
local function classify_letters(text)
  local is_upper = text:match('^%u+$') ~= nil
  local is_lower = text:match('^%l+$') ~= nil
  if not (is_upper or is_lower) then
    return nil
  end
  if numbering.is_roman(text) then
    if #text == 1 then
      return { kind = is_upper and 'roman' or 'alpha', ambiguous = true, upper = is_upper }
    end
    return { kind = 'roman', ambiguous = false, upper = is_upper }
  end
  return { kind = 'alpha', ambiguous = false, upper = is_upper }
end

--- A marker is only a marker when it is followed by whitespace or ends the
--- line. That is what keeps `*bold*` and `1.5` out.
local function match_marker(body)
  local text, space = body:match('^([-*+])([ \t]+)')
  if not text then
    text = body:match('^([-*+])$')
    space = text and ''
  end
  if text then
    return { kind = 'bullet', text = text, delim = '', value = nil, upper = false, ambiguous = false }, space
  end

  local digits, delim
  digits, delim, space = body:match('^(%d+)([.)])([ \t]+)')
  if not digits then
    digits, delim = body:match('^(%d+)([.)])$')
    space = digits and ''
  end
  if digits then
    return {
      kind = 'numeric',
      text = digits,
      delim = delim,
      value = tonumber(digits),
      upper = false,
      ambiguous = false,
    }, space
  end

  local letters
  letters, delim, space = body:match('^(%a+)([.)])([ \t]+)')
  if not letters then
    letters, delim = body:match('^(%a+)([.)])$')
    space = letters and ''
  end
  if letters then
    local class = classify_letters(letters)
    if class then
      local value = class.kind == 'roman' and numbering.from_roman(letters)
        or numbering.from_alpha(letters)
      return {
        kind = class.kind,
        text = letters,
        delim = delim,
        value = value,
        upper = class.upper,
        ambiguous = class.ambiguous,
      }, space
    end
  end

  return nil, nil
end

--- @param line string
--- @param opts table
--- @return autolist.Line
function M.parse(line, opts)
  local tabstop = opts.tabstop or 8
  local parsed = { text = line }

  local pos = 1
  local depth = 0
  if opts.blockquote then
    while true do
      local _, stop = line:find('^[ \t]*>', pos)
      if not stop then
        break
      end
      pos = stop + 1
      depth = depth + 1
    end
  end
  parsed.quote = line:sub(1, pos - 1)
  parsed.quote_depth = depth

  local indent = line:match('^[ \t]*', pos)
  parsed.indent = indent
  parsed.indent_width = M.ws_width(indent, tabstop)
  pos = pos + #indent

  local body = line:sub(pos)
  parsed.body = body
  parsed.blank = body == ''
  parsed.thematic_break = false
  if parsed.blank then
    return parsed
  end

  local squeezed = (body:gsub('[ \t]', ''))
  if #squeezed >= 3 and (squeezed:match('^%-+$') or squeezed:match('^%*+$') or squeezed:match('^_+$')) then
    parsed.thematic_break = true
    return parsed
  end

  local marker, space = match_marker(body)
  if not marker then
    return parsed
  end
  parsed.marker = marker
  parsed.marker_text = marker.text .. marker.delim
  parsed.space = space

  local at = pos + #parsed.marker_text + #space
  local rest = line:sub(at)
  local class = opts.checkbox_class or DEFAULT_CHECKBOX_CLASS
  local box, box_space = rest:match('^%[([' .. class .. '])%]([ \t]+)')
  if not box then
    box = rest:match('^%[([' .. class .. '])%]$')
    box_space = box and ''
  end
  if box then
    parsed.checkbox = box
    parsed.checkbox_space = box_space
    at = at + 3 + #box_space
  end

  parsed.content = line:sub(at)
  parsed.prefix = line:sub(1, at - 1)
  parsed.empty = parsed.content:match('^[ \t]*$') ~= nil
  return parsed
end

--- @param marker autolist.Marker
--- @return string
function M.render_marker(marker)
  if marker.kind == 'bullet' then
    return marker.text
  end
  local text
  if marker.kind == 'numeric' then
    text = tostring(marker.value)
  elseif marker.kind == 'alpha' then
    text = numbering.to_alpha(marker.value, marker.upper)
  else
    text = numbering.to_roman(marker.value, marker.upper)
  end
  return text .. marker.delim
end

--- Rebuild a line from a parsed (and possibly modified) representation.
--- @param parsed autolist.Line
--- @return string
function M.render(parsed)
  if not parsed.marker then
    return parsed.quote .. parsed.indent .. parsed.body
  end
  local box = ''
  if parsed.checkbox then
    box = '[' .. parsed.checkbox .. ']' .. parsed.checkbox_space
  end
  return parsed.quote
    .. parsed.indent
    .. M.render_marker(parsed.marker)
    .. parsed.space
    .. box
    .. parsed.content
end

return M
