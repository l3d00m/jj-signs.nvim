local M = {}

-- Debug function (enable for diagnosing issues)
function M.debug_print(msg)
	vim.api.nvim_echo({ { "JJ-SIGNS-DEBUG: " .. msg, "WarningMsg" } }, false, {})
end

-- Generalized jj command runner: always prepends "jj"
function M.run_jj(cmd_args, cwd, repo_path, on_stdout, on_stderr, on_exit)
	local args = {}
	args[1] = "jj"
	for i, v in ipairs(cmd_args) do
		args[i + 1] = v
	end

	if repo_path then
		table.insert(args, 2, "--repository")
		table.insert(args, 3, repo_path)
	end

	-- Don't add --ignore-working-copy for certain commands where we need to see changes
	if cmd_args[1] ~= "file" then
		table.insert(args, 2, "--ignore-working-copy")
	end

	M.debug_print("Running command: " .. table.concat(args, " "))

	local ok, job_id = pcall(vim.fn.jobstart, args, {
		cwd = cwd,
		stdout_buffered = true,
		on_stdout = on_stdout,
		on_stderr = on_stderr,
		on_exit = on_exit,
	})
	if not ok then
		vim.api.nvim_echo({ { "jj error: could not start job", "ErrorMsg" } }, false, {})
	end

	return job_id
end

-- Get file modification time
function M.get_file_mtime(filepath)
	local stat = vim.uv.fs_stat(filepath)
	return stat and stat.mtime.sec or nil
end

-- Get jj repository root for a file
function M.get_repo_root(filepath, callback)
	local dir = vim.fn.fnamemodify(filepath, ":p:h")
	local repo_root = nil
	M.run_jj(
		{ "root" },
		dir,
		nil,
		function(_, data)
			if data and data[1] and data[1] ~= "" then
				repo_root = vim.trim(data[1])
				M.debug_print("Found repo root: " .. repo_root)
			end
		end,
		nil,
		function(_, code)
			callback(code == 0 and repo_root or nil)
		end
	)
end

-- Cache blame annotations for a file
function M.cache_annotate(bufnr, filepath, annotate_cache, untracked_files, debounce_timers, config, on_done)
	local mtime = M.get_file_mtime(filepath)
	M.debug_print("Starting cache_annotate for " .. filepath)

	-- Debounce logic
	if debounce_timers[bufnr] then
		debounce_timers[bufnr]:stop()
		if not debounce_timers[bufnr]:is_closing() then
			debounce_timers[bufnr]:close()
		end
		debounce_timers[bufnr] = nil
	end

	debounce_timers[bufnr] = vim.defer_fn(function()
		if annotate_cache[bufnr] and annotate_cache[bufnr].loading then
			M.debug_print("Already loading annotations, skipping")
			return
		end
		annotate_cache[bufnr] = { loading = true }

		M.get_repo_root(filepath, function(repo_root)
			if not repo_root then
				M.debug_print("No repo root found, clearing cache")
				annotate_cache[bufnr] = nil
				return
			end

			-- Run the annotate command
			local jj_args = {
				"file",
				"annotate",
				filepath,
				"-T",
				config.blame_format,
			}

			M.run_jj(jj_args, nil, repo_root, function(_, data)
				if not data then
					M.debug_print("No data returned from annotate command")
					return
				end

				M.debug_print("Got blame data: " .. #data .. " lines for " .. filepath)

				annotate_cache[bufnr] = {
					mtime = mtime,
					lines = data,
					loading = false,
				}
				if on_done then
					on_done()
				end
			end, function(_, data)
				if data and data[1] and data[1] ~= "" then
					M.debug_print("Error from annotate command: " .. data[1])
					if data[1]:match("No such path") then
						untracked_files[filepath] = true
						annotate_cache[bufnr] = {
							mtime = mtime,
							lines = {},
							loading = false,
							untracked = true,
						}
					else
						vim.api.nvim_echo({ { "jj error: " .. table.concat(data, " "), "ErrorMsg" } }, false, {})
					end
				end
			end, function(_, code)
				M.debug_print("Annotate command exited with code: " .. code)
				if code ~= 0 and not (annotate_cache[bufnr] and annotate_cache[bufnr].untracked) then
					annotate_cache[bufnr] = nil
				end
			end)
		end)
	end, config.delay)
end

return M
