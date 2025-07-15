# jj-signs.nvim

> [!WARNING]
> This has been completely vibecoded (AI) and I'm not a lua expert. Use with a lot of caution and expect bugs.

Neovim blame annotation using [jj](https://github.com/martinvonz/jj).

## Features

- Annotates the current line using `jj file annotate` as virtual text in nvim
- Only enabled for buffers inside a jj repo (detected automatically)
- Caches blame per file and refreshes on modification
- Blame format:
  ```
  author , ago - first line of description (commit_id)
  ```
- No extra features or config

## Install

For [LazyVim](https://www.lazyvim.org/):

```lua
{
  "l3d00m/jj-signs.nvim",
  config = function()
    require("jj_signs").setup()
  end,
  lazy = false,
},
```

## Usage

- Pausing the cursor on a line shows blame for that line as virtual text
- `:JjSigns` or `<leader>jb` shows blame on demand

## Requirements

- [jj](https://github.com/martinvonz/jj) must be in your `$PATH`
- Neovim 0.10+ (for `nvim_buf_set_extmark`)
