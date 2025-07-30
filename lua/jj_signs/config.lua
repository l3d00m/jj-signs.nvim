local M = {}

-- Default configuration
M.defaults = {
	-- Customize blame format
	blame_format = "separate(' ', truncate_end(30, commit.author().name()) ++ ',', commit_timestamp(commit).local().ago(), '-' , truncate_end(50, commit.description().first_line(), '...'), '(' ++ commit.change_id().shortest(8) ++ ')') ++ \"\\n\"",

	-- Visual appearance options
	highlight_group = "Comment",
	uncommitted_highlight_group = "WarningMsg",

	-- Behavior options
	delay = 200, -- milliseconds to wait before showing blame
	skip_untracked = true, -- skip showing blame for untracked files
	warn_on_changed_files = true, -- show warning for changed files

	-- Key mappings
	mappings = {
		enable = true,
		blame = "<leader>jb",
		toggle = "<leader>jt",
		clear = "<leader>jc",
		refresh = "<leader>jr",
	},
}

-- Current configuration (will be populated in setup)
local current_config = {}

-- Setup configuration
function M.setup(opts)
	current_config = vim.tbl_deep_extend("force", M.defaults, opts or {})

	-- Apply keymaps if enabled
	if current_config.mappings.enable then
		vim.api.nvim_set_keymap(
			"n",
			current_config.mappings.blame,
			":JjBlame<CR>",
			{ noremap = true, silent = true, desc = "Show jj blame for current line" }
		)

		vim.api.nvim_set_keymap(
			"n",
			current_config.mappings.toggle,
			":JjBlameToggle<CR>",
			{ noremap = true, silent = true, desc = "Toggle jj blame display" }
		)

		vim.api.nvim_set_keymap(
			"n",
			current_config.mappings.clear,
			":JjBlameClear<CR>",
			{ noremap = true, silent = true, desc = "Clear jj blame annotations" }
		)

		vim.api.nvim_set_keymap(
			"n",
			current_config.mappings.refresh,
			":JjBlameRefresh<CR>",
			{ noremap = true, silent = true, desc = "Refresh jj blame data" }
		)
	end
end

-- Get current configuration
function M.get_config()
	return current_config
end

return M
