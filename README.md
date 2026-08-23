# autolist.nvim

Keeps the shape of a markdown list — markers, numbering, indentation,
checkboxes — so you can write the content and let the editor keep it tidy.

The design rule behind everything here: **nothing happens that you did not
ask for.** No key is mapped, no autocommand watches your typing, and no line
you did not touch is rewritten behind your back. The plugin publishes commands
and functions; which keys they sit on is yours to decide.

The full requirements this implements are in [`docs/requirements.md`](docs/requirements.md)
(Japanese).

## Requirements

Neovim 0.9 or newer. No other plugins.

## Install

With `lazy.nvim`:

```lua
{
  'kbwo/autolist.nvim',
  ft = 'markdown',
  config = function()
    require('autolist').setup()
  end,
}
```

`setup()` is optional — the defaults already work for markdown. Call it only
to override something.

## Mapping it to keys

The plugin deliberately maps nothing. Every entry point tells you whether it
did anything, so your mapping can fall through to whatever else that key does
— your own default, or another plugin's.

The expression helpers (`cr`, `o`, `shift_o`, `tab`, `shift_tab`) return a key
sequence when autolist wants the key and `nil` when it does not:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(event)
    local autolist = require('autolist')
    local opts = { buffer = event.buf, expr = true }

    vim.keymap.set('i', '<CR>', function() return autolist.cr() or '<CR>' end, opts)
    vim.keymap.set('i', '<Tab>', function() return autolist.tab() or '<Tab>' end, opts)
    vim.keymap.set('i', '<S-Tab>', function() return autolist.shift_tab() or '<S-Tab>' end, opts)

    vim.keymap.set('n', 'o', function() return autolist.o() or 'o' end, opts)
    vim.keymap.set('n', 'O', function() return autolist.shift_o() or 'O' end, opts)

    vim.keymap.set('n', '<leader>lr', '<Cmd>AutolistRenumber<CR>', { buffer = event.buf })
    vim.keymap.set('n', '<leader>lc', '<Cmd>AutolistToggleCheckbox<CR>', { buffer = event.buf })
    vim.keymap.set('n', '<leader>lm', '<Cmd>AutolistCycleMarkersBlock<CR>', { buffer = event.buf })
    vim.keymap.set('n', '<leader>ls', '<Cmd>AutolistCycleMarkersSiblings<CR>', { buffer = event.buf })
    vim.keymap.set('n', '>>', '<Cmd>AutolistIndent<CR>', { buffer = event.buf })
    vim.keymap.set('n', '<<', '<Cmd>AutolistDedent<CR>', { buffer = event.buf })
  end,
})
```

If `<CR>` is already taken by a completion plugin, chain it instead of
replacing it:

```lua
vim.keymap.set('i', '<CR>', function()
  return autolist.cr() or require('other-plugin').cr() or '<CR>'
end, { buffer = event.buf, expr = true })
```

## What it does

### Carrying a list on

Pressing your `<CR>` mapping on a list item starts the next one: same
indentation, same marker, same delimiter, with an ordered marker counting up.

```markdown
- apple|          →   - apple
                      - |

1. apple|         →   1. apple
                      2. |

    a) apple|     →       a) apple
                          b) |
```

A checkbox is carried over but always starts unchecked, however you left the
one above:

```markdown
- [x] done|       →   - [x] done
                      - [ ] |
```

Breaking in the middle of an item moves the rest of the text into the new one.
A list written entirely with the same number (`1.` `1.` `1.`, which markdown
renders as a sequence anyway) keeps writing that same number.

### Opening a line above or below

Your `o` and `O` mappings write the marker too, so adding an item without
going through the end of the current one works the same way. The line under
the cursor is left whole, wherever in it the cursor happens to be.

```markdown
- apple|          →  o  →   - apple
                            - |

2. apple|         →  O  →   2. |
                            2. apple
```

An item added below counts on from the current one; an item added above takes
over its place in the list, and with it its number. The items further down
keep the numbers they had — run `:AutolistRenumber` when you want the list
consecutive again.

Unlike `<CR>`, this does not leave the list: on an item with no content it
adds another empty item rather than clearing the one you are standing on.

### Leaving a list

Pressing the same key on an item with no content removes it, so ending a list
does not mean deleting the marker by hand. An item holding nothing but a
checkbox counts as empty too.

```markdown
- apple           →   - apple
- |                   |
```

### Renumbering

`:AutolistRenumber` makes the numbers in the list block under the cursor
consecutive again after you deleted, reordered or re-indented something.

```markdown
1. a                   1. a
5. b     →  renumber → 2. b
2. c                   3. c
```

This runs only when you ask for it. Nothing watches the buffer and renumbers
as you type.

Levels count independently of each other, and a level keeps the number it
starts from — a list beginning at `3.` becomes `3. 4. 5.`, not `1. 2. 3.`.
Letters (`a) b) c)`) and Roman numerals (`I. II. III.`) count as sequences too.

### Indenting

`:AutolistIndent` and `:AutolistDedent` move the item under the cursor one
level, taking its continuation lines and nested items along, and fix the
numbering as part of the same action.

An item indented next to siblings that already exist joins their numbering; an
item that ends up alone at a level it just created starts from the beginning.

```markdown
1. a                       1. a
    1. x   →  indent b  →      1. x
2. b                           2. b
3. c                       2. c
```

### Checkboxes

`:AutolistToggleCheckbox` flips `[ ]` and `[x]` on the current line, or on
every line of a range. It leaves items without a checkbox alone rather than
adding one.

### Marker styles

A style is the marker together with whether the item carries a checkbox. The
tick inside the box is not part of it — that is your record of what is done,
not a matter of appearance. The default order is `-` → `- [ ]` → `*` → `1.` →
`1)` → `a)` → `I.` and around again.

Two commands move items to the next style, differing only in what they take
with them, because a nested list often wants a different marker per level:

- `:AutolistCycleMarkersBlock` — every item of the block, at every level
- `:AutolistCycleMarkersSiblings` — only the run the cursor is in; its parent
  and its nested items are untouched

Both take a `!` to walk the cycle backwards, so a step too far comes straight
back, and both wrap around at the ends.

```markdown
- 親                                  - 親
    - 子   →  siblings, three times →     1. 子
    - 子                                  2. 子
- 親                                  - 親
```

Where the next style has a checkbox, items without one gain an unchecked box
and items that already have one keep their tick. Where it has none, the box is
removed, so a full turn brings the list back as it was.

```markdown
- 買い物                       - [ ] 買い物
- 洗濯          →  cycle  →    - [ ] 洗濯
```

Turning a list into an ordered one numbers each level from the beginning. A
style that is not in `cycle` lands on the start of it.

### Turning plain text into a list

Notes often get written with nothing but indentation for structure.
`:AutolistMakeList` gives those lines a marker, leaving the indentation exactly
as it was — so the nesting the text already had becomes the nesting of the list.

```
ccmanager                              - ccmanager
    write a skill    →  :%AutolistMakeList →     - write a skill
    delete a worktree                          - delete a worktree
```

It marks the lines of the range you give it and nothing else — it does not
hunt for where the text begins and ends, because guessing wrong would rewrite
lines you never pointed at. Lines that are already items, blank lines,
thematic breaks and code blocks are left alone.

The marker is the first entry of `cycle`; for any other style, run
`:AutolistCycleMarkersBlock` afterwards.

### Where it stays out of the way

Things that merely look like list markers are left alone: fenced and indented
code blocks, emphasis such as `*bold*`, thematic breaks like `---`, and a `1.`
that appears mid-sentence. On any other line, and in any buffer whose filetype
is not enabled, every entry point reports that it did nothing, so your keys
behave exactly as they otherwise would.

Lists inside blockquotes are handled like any other list, with the `>` markers
preserved.

## Configuration

Defaults:

```lua
require('autolist').setup({
  filetypes = {
    markdown = {
      -- Order the marker styles are cycled through. An entry may carry a
      -- checkbox, which makes having one part of the style.
      cycle = { '-', '- [ ]', '*', '1.', '1)', 'a)', 'I.' },
      -- Characters written between the brackets.
      checkbox = { checked = 'x', unchecked = ' ' },
      -- Treat a leading '>' as part of the item prefix.
      blockquote = true,
      -- Recognise code blocks and stay out of them.
      code_blocks = true,
    },
  },
})
```

Enable another filetype by adding an entry; it inherits the same defaults:

```lua
require('autolist').setup({
  filetypes = {
    text = {},
    markdown = { cycle = { '-', '1.' } },
  },
})
```

Set an entry to `false` to disable a filetype.

Indentation follows the buffer: `'shiftwidth'`, `'tabstop'` and `'expandtab'`
are read from the buffer you are editing, so the plugin writes indentation the
same way you do.

## Lua API

Every function returns `true` when it acted and `false` when it did not.

| Function | Does |
| --- | --- |
| `setup(opts)` | Override the defaults. Optional. |
| `newline()` | Continue the list, or leave it from an empty item. |
| `open_below()` / `open_above()` | Add an item on the line below or above, leaving the current line whole. |
| `indent()` / `dedent()` | Move the item one level and renumber the block. |
| `renumber()` | Renumber the block under the cursor. |
| `toggle_checkbox(lnum?)` | Flip the checkbox on a line. |
| `cycle_markers_block(opts?)` | Switch every item of the block to the next marker style. `{ reverse = true }` for the previous. |
| `cycle_markers_siblings(opts?)` | The same, for only the siblings at the cursor. |
| `make_list(first?, last?)` | Turn plain lines into list items. Defaults to the cursor line. |
| `cr()` / `o()` / `shift_o()` / `tab()` / `shift_tab()` | For `expr` mappings: a key sequence, or `nil` to fall through. `o()` and `shift_o()` start insert mode as well, the way `o` and `O` do. |
| `at_item_prefix()` | Whether the cursor is in an item's indent/marker/checkbox. For callers that cannot use an `expr` mapping. |

If another plugin already owns the key, route autolist through its mapping
table rather than shadowing it. With `nvim-cmp`:

```lua
['<Tab>'] = cmp.mapping(function(fallback)
  local autolist = require('autolist')
  if cmp.visible() then
    cmp.select_next_item()
  elseif autolist.at_item_prefix() and autolist.indent() then
    return
  else
    fallback()      -- whatever <Tab> did before cmp took it
  end
end, { 'i' }),
```

## Tests

```sh
make test
```

The suite drives real buffers, and its cases are the input/output examples from
the requirements document.

## License

MIT. See [`LICENSE`](LICENSE).
