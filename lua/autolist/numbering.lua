--- Conversions between the ordinal value of a list item and the text used to
--- write it: decimal digits, alphabetic letters and Roman numerals.
local M = {}

local ROMAN_PAIRS = {
  { 1000, 'M' },
  { 900, 'CM' },
  { 500, 'D' },
  { 400, 'CD' },
  { 100, 'C' },
  { 90, 'XC' },
  { 50, 'L' },
  { 40, 'XL' },
  { 10, 'X' },
  { 9, 'IX' },
  { 5, 'V' },
  { 4, 'IV' },
  { 1, 'I' },
}

local ROMAN_DIGITS = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }

--- @param n integer
--- @param upper boolean
--- @return string
function M.to_roman(n, upper)
  if n < 1 then
    n = 1
  end
  local out = {}
  for _, pair in ipairs(ROMAN_PAIRS) do
    while n >= pair[1] do
      out[#out + 1] = pair[2]
      n = n - pair[1]
    end
  end
  local s = table.concat(out)
  return upper and s or s:lower()
end

--- @param text string
--- @return integer|nil
function M.from_roman(text)
  local upper = text:upper()
  local total, prev = 0, 0
  for i = #upper, 1, -1 do
    local v = ROMAN_DIGITS[upper:sub(i, i)]
    if not v then
      return nil
    end
    if v < prev then
      total = total - v
    else
      total = total + v
      prev = v
    end
  end
  return total
end

--- True only for canonically written Roman numerals, so that `iix` or `vv` are
--- treated as ordinary letters instead of numbers.
--- @param text string
--- @return boolean
function M.is_roman(text)
  if text == '' or not text:upper():match('^[IVXLCDM]+$') then
    return false
  end
  local n = M.from_roman(text)
  return n ~= nil and n >= 1 and M.to_roman(n, true) == text:upper()
end

--- Bijective base 26: a=1 … z=26, aa=27 …
--- @param n integer
--- @param upper boolean
--- @return string
function M.to_alpha(n, upper)
  if n < 1 then
    n = 1
  end
  local out = ''
  while n > 0 do
    local rem = (n - 1) % 26
    out = string.char(97 + rem) .. out
    n = (n - 1 - rem) / 26
  end
  return upper and out:upper() or out
end

--- @param text string
--- @return integer|nil
function M.from_alpha(text)
  local n = 0
  for i = 1, #text do
    local d = text:sub(i, i):lower():byte() - 96
    if d < 1 or d > 26 then
      return nil
    end
    n = n * 26 + d
  end
  return n
end

return M
