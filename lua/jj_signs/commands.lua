local M = {}
local config = require("jj_signs.config")
local utils = require("jj_signs.utils")

function M.setup_commands(ns, annotate_cache, enabled_buffers, changed_files, untracked_files, show_blame_fn)
	-- JjBlame command - show blame for current line
	vim.api.nvim_create_user_command("JjBlame", function()
		local bufnr = vim.api.nvim_get_current_buf()
		if enabled_buffers[bufnr] then
			show_blame_fn()
		end
	end, {
		desc = "Show jj blame for current line",
	})

	-- JjBlameToggle command - toggle blame display
	vim.api.nvim_create_user_command("JjBlameToggle", function()
		local bufnr = vim.api.nvim_get_current_buf()
		if not enabled_buffers[bufnr] then
			return
		end

		local showing_blame = vim.b[bufnr].jj_blame_showing or false

		if showing_blame then
			vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			vim.b[bufnr].jj_blame_showing = false
		else
			show_blame_fn()
			vim.b[bufnr].jj_blame_showing = true
		end
	end, {
		desc = "Toggle jj blame display",
	})

	-- JjBlameClear command - clear blame annotations
	vim.api.nvim_create_user_command("JjBlameClear", function()
		local bufnr = vim.api.nvim_get_current_buf()
		if enabled_buffers[bufnr] then
			vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			vim.b[bufnr].jj_blame_showing = false
		end
	end, {
		desc = "Clear jj blame annotations",
	})

	-- JjBlameRefresh command - force refresh blame data
	vim.api.nvim_create_user_command("JjBlameRefresh", function()
		local bufnr = vim.api.nvim_get_current_buf()
		if enabled_buffers[bufnr] then
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			-- utils.debug_print("Forcing refresh of blame data")
			annotate_cache[bufnr] = nil
			changed_files[filepath] = nil
			untracked_files[filepath] = nil -- Clear untracked status on refresh
			show_blame_fn()
		end
	end, {
		desc = "Refresh jj blame data",
	})

	-- JjCheckChanges command (hidden from docs but kept for debugging)
	vim.api.nvim_create_user_command("JjCheckChanges", function()
		local bufnr = vim.api.nvim_get_current_buf()
		local filepath = vim.api.nvim_buf_get_name(bufnr)
		if enabled_buffers[bufnr] then
			local check_file_changes = function(bufnr, filepath, callback)
				utils.get_repo_root(filepath, function(repo_root)
					if not repo_root then
						if callback then
							callback(false)
						end
						return
					end

					changed_files[filepath] = nil

					utils.is_file_changed(filepath, repo_root, function(is_changed)
						if is_changed then
							changed_files[filepath] = true
						else
							changed_files[filepath] = nil
						end

						annotate_cache[bufnr] = nil

						if callback then
							callback(is_changed)
						end
					end)
				end)
			end

			check_file_changes(bufnr, filepath, function(has_changes)
				annotate_cache[bufnr] = nil
				show_blame_fn()
			end)
		end
	end, {
		desc = "Manually check for file changes (debug)",
	})
end

return M
