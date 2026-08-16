-- Commands only. The plugin never maps a key (NFR-7) and never installs an
-- autocommand that rewrites text (NFR-6).

if vim.g.loaded_autolist then
  return
end
vim.g.loaded_autolist = true

local command = vim.api.nvim_create_user_command

command('AutolistRenumber', function()
  require('autolist').renumber()
end, { desc = 'Renumber the ordered list block around the cursor' })

command('AutolistIndent', function()
  require('autolist').indent()
end, { desc = 'Indent the list item under the cursor and renumber the block' })

command('AutolistDedent', function()
  require('autolist').dedent()
end, { desc = 'Dedent the list item under the cursor and renumber the block' })

command('AutolistToggleCheckbox', function(args)
  local autolist = require('autolist')
  for lnum = args.line1, args.line2 do
    autolist.toggle_checkbox(lnum)
  end
end, { range = true, desc = 'Toggle the checkbox on each line of the range' })

command('AutolistCycleMarkers', function()
  require('autolist').cycle_markers()
end, { desc = 'Switch the list block to the next marker style' })
