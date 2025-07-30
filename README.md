# jj-signs.nvim

Neovim blame annotation using [jj](https://github.com/jj-vcs/jj).

> [!WARNING]
> This has been completely vibecoded (AI) and I'm not a lua expert. Use with a lot of caution and expect bugs.

<img width="783" height="112" alt="image" src="https://github.com/user-attachments/assets/7170f65e-8e9f-45d2-8f7d-7f3f6a69bd92" />

## Features

- Annotates the current line using `jj file annotate` as virtual text in nvim
- Only enabled for buffers inside a jj repo (detected automatically)
- Caches blame per file and refreshes on modification
- Shows special indicators for files with uncommitted changes
- Handles untracked files gracefully
- Customizable blame format and visual appearance
- Lightweight with minimal performance impact

## Install

For [LazyVim](https://www.lazyvim.org/):

```lua
{
  "l3d00m/jj-signs.nvim",
  config = function()
    require("jj_signs").setup({
      -- Optional configuration (defaults shown)
      blame_format = "separate(' ', truncate_end(30, commit.author().name()) ++ ',', commit_timestamp(commit).local().ago(), '-' , truncate_end(50, commit.description().first_line(), '...'), '(' ++ commit.change_id().shortest(8) ++ ')') ++ \"\\n\"",
      highlight_group = "Comment",
      uncommitted_highlight_group = "WarningMsg",
      delay = 200,
      skip_untracked = true,
      warn_on_changed_files = true,
      mappings = {
        enable = true,
        blame = '<leader>jb',
        toggle = '<leader>jt',
        clear = '<leader>jc',
        refresh = '<leader>jr'
      }
    })
  end,
  lazy = false,
},
```
