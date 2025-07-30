local M = {}
local config = require("jj_signs.config")
local utils = require("jj_signs.utils")
local commands = require("jj_signs.commands")

-- Global module state
local ns = vim.api.nvim_create_namespace("jj_blame")
local annotate_cache = setmetatable({}, { __mode = "v" })
local enabled_buffers = setmetatable({}, { __mode = "v" })
local debounce_timers = {}
local untracked_files = setmetatable({}, { __mode = "k" })
local changed_files = setmetatable({}, { __mode = "k" })
local last_line_by_buf = {}

-- Create the autocommand group
local JJ_SIGNS_GROUP = vim.api.nvim_create_augroup("JjSignsGroup", { clear = true })

-- Clear blame annotations for the current buffer
local function clear_blame_annotations()
	local bufnr = vim.api.nvim_get_current_buf()
	if enabled_buffers[bufnr] then
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	end
end

-- Handle cursor movement - clear blame when line changes
local function on_cursor_moved_vertically()
	local bufnr = vim.api.nvim_get_current_buf()
	local cur_line = vim.api.nvim_win_get_cursor(0)[1]
	local last_line = last_line_by_buf[bufnr]
	if last_line ~= nil and cur_line ~= last_line then
		clear_blame_annotations()
	end
	last_line_by_buf[bufnr] = cur_line
end

-- Check if file has changes and update cache
local function check_file_changes(bufnr, filepath, callback)
	utils.debug_print("Checking file changes: " .. filepath)

	-- Get repository root first
	utils.get_repo_root(filepath, function(repo_root)
		if not repo_root then
			utils.debug_print("No repo root found")
			if callback then
				callback(false)
			end
			return
		end

		-- Clear the change flag first to ensure a clean start
		changed_files[filepath] = nil

		-- Check if file has uncommitted changes
		utils.is_file_changed(filepath, repo_root, function(is_changed)
			if is_changed then
				utils.debug_print("File has changes, marking: " .. filepath)
				changed_files[filepath] = true
			else
				utils.debug_print("File has no changes, clearing flag: " .. filepath)
				changed_files[filepath] = nil
			end

			-- Force-clear the cache to ensure we get fresh blame data
			annotate_cache[bufnr] = nil

			if callback then
				callback(is_changed)
			end
		end)
	end)
end

-- Show blame information for the current line
local function show_blame_for_line()
	local bufnr = vim.api.nvim_get_current_buf()
	if not enabled_buffers[bufnr] then
		utils.debug_print("Buffer not enabled for blame")
		return
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local line = vim.api.nvim_win_get_cursor(0)[1]
	utils.debug_print("Showing blame for line " .. line .. " in " .. filepath)

	if filepath == "" then
		utils.debug_print("Empty filepath")
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		return
	end

	-- If the buffer has unsaved changes, clear annotations and don't show blame
	if vim.bo[bufnr].modified then
		utils.debug_print("Buffer is modified, not showing blame")
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		return
	end

	utils.debug_print("Changed status: " .. tostring(changed_files[filepath] or "nil"))

	-- If the file has uncommitted changes, show the uncommitted indicator
	if changed_files[filepath] then
		utils.debug_print("File has uncommitted changes, showing indicator")
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		local user_config = config.get_config()
		vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
			virt_text = { { "(uncommitted changes)", user_config.uncommitted_highlight_group } },
			virt_text_pos = "eol",
		})
		return
	end

	local mtime = utils.get_file_mtime(filepath)
	local cache = annotate_cache[bufnr]
	local user_config = config.get_config()

	if cache and cache.mtime == mtime then
		utils.debug_print("Using cached blame data")

		-- If file is untracked, don't show any blame info
		if cache.untracked then
			utils.debug_print("File is untracked, not showing blame")
			return
		end

		-- If file has changes since last commit, show a special indicator
		if cache.changed then
			utils.debug_print("Cache indicates file is changed")
			vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
				virt_text = { { "(uncommitted changes)", user_config.uncommitted_highlight_group } },
				virt_text_pos = "eol",
			})
			return
		end

		utils.debug_print("Showing blame for line " .. line)
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

		-- Show blame for current line
		if line <= #cache.lines then
			local blame_info = cache.lines[line]
			if blame_info and blame_info ~= "" then
				utils.debug_print("Setting blame for line " .. line .. ": " .. blame_info)
				vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
					virt_text = { { blame_info, user_config.highlight_group } },
					virt_text_pos = "eol",
				})
			else
				utils.debug_print("No blame info for line " .. line)
			end
		else
			utils.debug_print("Line " .. line .. " is beyond blame data length (" .. #cache.lines .. ")")
		end
	else
		utils.debug_print("No cache hit, getting fresh blame data")
		utils.cache_annotate(
			bufnr,
			filepath,
			annotate_cache,
			untracked_files,
			changed_files,
			debounce_timers,
			user_config,
			show_blame_for_line
		)
	end
end

-- Clean up resources associated with a buffer
local function cleanup_buffer(bufnr)
	utils.debug_print("Cleaning up buffer " .. bufnr)
	enabled_buffers[bufnr] = nil
	if debounce_timers[bufnr] then
		debounce_timers[bufnr]:stop()
		if not debounce_timers[bufnr]:is_closing() then
			debounce_timers[bufnr]:close()
		end
		debounce_timers[bufnr] = nil
	end
	-- Clear buffer-local autocmds on delete
	pcall(vim.api.nvim_clear_autocmds, { group = JJ_SIGNS_GROUP, buffer = bufnr })
	last_line_by_buf[bufnr] = nil
end

-- Try to enable jj blame for a buffer
local function try_enable_jj_blame(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return
	end
	local dir = vim.fn.fnamemodify(filepath, ":p:h")
	utils.debug_print("Checking if file is in jj repo: " .. filepath)
	utils.run_jj({ "root" }, dir, nil, nil, nil, function(_, code)
		if code == 0 then
			utils.debug_print("File is in jj repo, enabling blame")
			enabled_buffers[bufnr] = true

			-- Check if file has uncommitted changes on load
			check_file_changes(bufnr, filepath)

			-- Register buffer-local autocmds with group for easy cleanup
			vim.api.nvim_create_autocmd({ "CursorHold" }, {
				group = JJ_SIGNS_GROUP,
				buffer = bufnr,
				callback = show_blame_for_line,
				desc = "Show jj blame for current line (per buffer)",
			})
			-- Only clear blame on vertical movement (line change)
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				group = JJ_SIGNS_GROUP,
				buffer = bufnr,
				callback = on_cursor_moved_vertically,
				desc = "Clear jj blame annotations on vertical movement (per buffer)",
			})
		else
			utils.debug_print("File is not in jj repo")
			enabled_buffers[bufnr] = false
		end
	end)
end

-- Set up autocommands
local function setup_autocommands()
	-- Handle file write and buffer delete events
	vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete" }, {
		group = JJ_SIGNS_GROUP,
		callback = function(args)
			local filepath = vim.api.nvim_buf_get_name(args.buf)

			if args.event == "BufWritePost" then
				utils.debug_print("BufWritePost for " .. filepath)
				-- After saving, invalidate cache and check if the file has uncommitted changes
				annotate_cache[args.buf] = nil

				local bufnr = args.buf
				if enabled_buffers[bufnr] then
					-- Schedule the check slightly after save to allow jj to recognize changes
					vim.defer_fn(function()
						if vim.api.nvim_buf_is_valid(bufnr) then
							utils.debug_print("Re-checking file changes after save")
							check_file_changes(bufnr, filepath, function(has_changes)
								if vim.api.nvim_buf_is_valid(bufnr) then
									utils.debug_print("Post-save check result: " .. tostring(has_changes))
									show_blame_for_line()
								end
							end)
						end
					end, 100)
				end
			end

			if args.event == "BufDelete" then
				utils.debug_print("BufDelete for " .. filepath)
				cleanup_buffer(args.buf)
				changed_files[filepath] = nil
				untracked_files[filepath] = nil
			end
		end,
	})

	-- Handle text change events - just clear blame annotations
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = JJ_SIGNS_GROUP,
		callback = function(args)
			local bufnr = args.buf
			if enabled_buffers[bufnr] then
				utils.debug_print("Text changed, clearing blame")
				vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			end
		end,
	})

	-- Attempt to enable jj blame for newly loaded buffers
	vim.api.nvim_create_autocmd({ "BufReadPost" }, {
		group = JJ_SIGNS_GROUP,
		callback = function(args)
			try_enable_jj_blame(args.buf)
		end,
	})
end

-- Main setup function
function M.setup(opts)
	utils.debug_print("Setting up jj-signs plugin")

	-- Initialize configuration
	config.setup(opts)

	-- Set up commands
	commands.setup_commands(ns, annotate_cache, enabled_buffers, changed_files, untracked_files, show_blame_for_line)

	-- Set up autocommands
	setup_autocommands()

	-- Add command to manually check a file's changed status
	vim.api.nvim_create_user_command("JjCheckChanges", function()
		local bufnr = vim.api.nvim_get_current_buf()
		local filepath = vim.api.nvim_buf_get_name(bufnr)
		if enabled_buffers[bufnr] then
			utils.debug_print("Manually checking file changes: " .. filepath)
			check_file_changes(bufnr, filepath, function(has_changes)
				utils.debug_print("Manual check result: " .. tostring(has_changes))
				annotate_cache[bufnr] = nil -- Force refresh
				show_blame_for_line()
			end)
		end
	end, {})
end

return M
