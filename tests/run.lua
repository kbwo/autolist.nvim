-- Run with: nvim --headless -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

vim.opt.runtimepath:prepend(root)
package.path = root .. '/tests/?.lua;' .. package.path

-- Lets a test put the cursor past the last character of a line without being
-- in insert mode, which is where the newline cases start from.
vim.o.virtualedit = 'onemore'
vim.o.swapfile = false

local harness = require('harness')
_G.T = harness

require('autolist').setup({})

-- `-u NONE` skips plugin scripts, so register the commands by hand.
vim.cmd('runtime! plugin/autolist.lua')

local specs = vim.fn.glob(root .. '/tests/specs/*_spec.lua', false, true)
table.sort(specs)
for _, spec in ipairs(specs) do
  local chunk, err = loadfile(spec)
  if not chunk then
    io.write('FAIL  could not load ' .. spec .. '\n      ' .. tostring(err) .. '\n')
    harness.failures[#harness.failures + 1] = spec
  else
    local ok, run_err = pcall(chunk)
    if not ok then
      io.write('FAIL  ' .. spec .. '\n      ' .. tostring(run_err) .. '\n')
      harness.failures[#harness.failures + 1] = spec
    end
  end
end

os.exit(harness.report() and 0 or 1)
