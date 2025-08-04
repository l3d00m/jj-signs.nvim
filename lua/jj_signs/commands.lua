local M = {}
local utils = require("jj_signs.utils")

function M.setup_commands(ns, annotate_cache, enabled_buffers, untracked_files, show_blame_fn)
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

	-- JjBlameRefresh command - force refresh blame data
	vim.api.nvim_create_user_command("JjBlameRefresh", function()
		local bufnr = vim.api.nvim_get_current_buf()
		if enabled_buffers[bufnr] then
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			utils.debug_print("Forcing refresh of blame data")
			annotate_cache[bufnr] = nil
			untracked_files[filepath] = nil -- Clear untracked status on refresh
			show_blame_fn()
		end
	end, {
		desc = "Refresh jj blame data",
	})
end

return M
