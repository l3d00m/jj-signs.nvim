local M = {}

local ns = vim.api.nvim_create_namespace("jj_blame")
local annotate_cache = {}
local enabled_buffers = {}

-- Generalized jj command runner
local function run_jj(cmd_args, cwd, repo_path, on_stdout, on_stderr, on_exit)
  local args = vim.deepcopy(cmd_args)
  table.insert(args, 3, "--ignore-working-copy")
  
  -- Add --repository argument for all commands except "jj root"
  if repo_path and cmd_args[2] ~= "root" then
    table.insert(args, 4, "--repository")
    table.insert(args, 5, repo_path)
  end
  
  vim.fn.jobstart(args, {
    cwd = cwd,
    stdout_buffered = true,
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
  })
end

local function get_file_mtime(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat and stat.mtime.sec or nil
end

-- Get repository root for a given file path
local function get_repo_root(filepath, callback)
  local dir = vim.fn.fnamemodify(filepath, ":p:h")
  local repo_root = nil
  
  run_jj({"jj", "root"}, dir, nil,
    function(_, data)
      if data and data[1] and data[1] ~= "" then
        repo_root = vim.trim(data[1])
      end
    end,
    nil,
    function(_, code)
      callback(code == 0 and repo_root or nil)
    end
  )
end

local function cache_annotate(bufnr, filepath, on_done)
  local mtime = get_file_mtime(filepath)
  if annotate_cache[bufnr] and annotate_cache[bufnr].loading then
    return
  end
  annotate_cache[bufnr] = { loading = true }

  get_repo_root(filepath, function(repo_root)
    if not repo_root then
      annotate_cache[bufnr] = nil
      return
    end

    local jj_args = {
      "jj", "file", "annotate", filepath,
      "-T",
      "separate(' ', truncate_end(30, commit.author().name()) ++ ',', commit_timestamp(commit).local().ago(), '-' , truncate_end(50, commit.description().first_line(), '...'), '(' ++ commit.change_id().shortest(8) ++ ')') ++ \"\\n\""
    }

    run_jj(jj_args, nil, repo_root,
      function(_, data)
        if not data then return end
        annotate_cache[bufnr] = {
          mtime = mtime,
          lines = data,
          loading = false
        }
        if on_done then on_done() end
      end,
      function(_, data)
        if data and data[1] and data[1] ~= "" then
          vim.api.nvim_echo({{"jj error: " .. table.concat(data, " "), "ErrorMsg"}}, false, {})
        end
      end,
      function(_, code)
        if code ~= 0 then
          annotate_cache[bufnr] = nil
        end
      end
    )
  end)
end

local function clear_blame_annotations()
  local bufnr = vim.api.nvim_get_current_buf()
  if enabled_buffers[bufnr] then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

local function show_blame_for_line()
  local bufnr = vim.api.nvim_get_current_buf()
  if not enabled_buffers[bufnr] then return end
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  if filepath == "" then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    return
  end

  local mtime = get_file_mtime(filepath)
  local cache = annotate_cache[bufnr]

  if cache and cache.mtime == mtime and cache.lines then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    -- No file number in template, so map lines 1:1
    if line <= #cache.lines then
      local blame_info = cache.lines[line]
      if blame_info and blame_info ~= "" then
        vim.api.nvim_buf_set_extmark(bufnr, ns, line-1, 0, {
          virt_text = {{blame_info, "Comment"}},
          virt_text_pos = "eol",
        })
      end
    end
  else
    cache_annotate(bufnr, filepath, show_blame_for_line)
  end
end

vim.api.nvim_create_autocmd({"BufWritePost", "BufReadPost", "BufDelete"}, {
  callback = function(args)
    annotate_cache[args.buf] = nil
    enabled_buffers[args.buf] = nil
  end
})

-- Only enable plugin for buffer if jj root works in file's directory
local function try_enable_jj_blame(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then return end
  local dir = vim.fn.fnamemodify(filepath, ":p:h")
  run_jj({"jj", "root"}, dir, nil,
    nil, nil,
    function(_, code)
      if code == 0 then
        enabled_buffers[bufnr] = true

        -- Register CursorHold autocmd for this buffer only
        vim.api.nvim_create_autocmd({"CursorHold"}, {
          buffer = bufnr,
          callback = show_blame_for_line,
          desc = "Show jj blame for current line (per buffer)"
        })
        
        -- Register CursorMoved and CursorMovedI autocmds to clear annotations immediately
        vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
          buffer = bufnr,
          callback = clear_blame_annotations,
          desc = "Clear jj blame annotations on cursor movement (per buffer)"
        })
      else
        enabled_buffers[bufnr] = false
      end
    end
  )
end

function M.setup()
  vim.api.nvim_create_user_command('JjBlame', function()
    local bufnr = vim.api.nvim_get_current_buf()
    if enabled_buffers[bufnr] then show_blame_for_line() end
  end, {})
  vim.api.nvim_set_keymap('n', '<leader>jb', ':JjBlame<CR>', { noremap = true, silent = true })

  -- On BufRead, attempt to enable plugin for buffer
  vim.api.nvim_create_autocmd({"BufReadPost"}, {
    callback = function(args)
      try_enable_jj_blame(args.buf)
    end
  })
end

return M
