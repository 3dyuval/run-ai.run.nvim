local M = {}

local ns = vim.api.nvim_create_namespace("run_ai_run")

-- Get plugin root directory
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

-- Default configuration
M.config = {
	bin = "/home/yuv/.nvm/versions/node/v20.19.6/bin/claude",
	project = plugin_dir,
	log_level = "debug",
	notify_level = "error", -- nil = off, "debug"/"info"/"warn"/"error" = show in noice
	spinner = "dots",
	highlight = "DiagnosticInfo",
	skills_path = nil, -- path to user's .claude/skills directory
}

local log
local Job
local spinners

-- Log level priority for filtering
local levels = { debug = 1, info = 2, warn = 3, error = 4 }
local vim_levels = {
	debug = vim.log.levels.DEBUG,
	info = vim.log.levels.INFO,
	warn = vim.log.levels.WARN,
	error = vim.log.levels.ERROR,
}

-- Wrapper that logs to file and optionally to noice
local function notify(level, msg)
	if log then
		log[level](msg)
	end
	if M.config.notify_level and levels[level] >= levels[M.config.notify_level] then
		vim.schedule(function()
			vim.notify("[run-ai-run] " .. msg, vim_levels[level])
		end)
	end
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Lazy load dependencies
	Job = require("plenary.job")
	spinners = require("noice.util.spinners")

	-- Setup logging
	log = require("plenary.log").new({
		plugin = "run-ai-run",
		level = M.config.log_level,
		use_console = false,
		use_file = true,
	})

	-- Validate binary
	if vim.fn.executable(M.config.bin) ~= 1 then
		notify("error", "Binary not found: " .. M.config.bin)
		return
	end

	notify("info", "=== run-ai-run loaded ===")
	notify("info", "Binary: " .. M.config.bin)
	notify("info", "Project: " .. M.config.project)

	-- Create commands
	vim.api.nvim_create_user_command("Claude", function(args)
		M.replace(args)
	end, {
		range = true,
		nargs = "*",
		desc = "Replace selection with Claude response",
	})

	vim.api.nvim_create_user_command("ClaudeContinue", function(args)
		M.replace(args, { continue = true })
	end, {
		range = true,
		nargs = "*",
		desc = "Replace selection with Claude response (--continue flag)",
	})

	vim.api.nvim_create_user_command("ClaudeSkillClaude", function(args)
		M.replace(args, {
			skill = plugin_dir .. "/.claude/skills/run-ai-run.nvim.md",
		})
	end, {
		range = true,
		nargs = "*",
		desc = "Replace selection with Claude using run-ai-run skill",
	})

	-- Load user skills from skills_path
	if M.config.skills_path then
		M.load_skills(M.config.skills_path)
	end
end

--- Load skills from a directory and create commands for each
---@param skills_path string Path to the skills directory
function M.load_skills(skills_path)
	local path = vim.fn.expand(skills_path)
	if vim.fn.isdirectory(path) ~= 1 then
		notify("warn", "Skills path not found: " .. path)
		return
	end

	local files = vim.fn.glob(path .. "/*.md", false, true)
	for _, file in ipairs(files) do
		local name = vim.fn.fnamemodify(file, ":t:r") -- filename without extension
		local cmd_name = "ClaudeSkill" .. name:gsub("[^%w]", ""):gsub("^%l", string.upper)

		vim.api.nvim_create_user_command(cmd_name, function(args)
			M.replace(args, { skill = file })
		end, {
			range = true,
			nargs = "*",
			desc = "Replace selection with Claude using " .. name .. " skill",
		})

		notify("info", "Loaded skill: " .. name .. " -> :" .. cmd_name)
	end
end

--- Run Claude with prompt and callbacks (no UI)
---@param prompt string The prompt to send
---@param opts? table Options: continue, on_success, on_error, on_stdout, bin, project
---@return table job The plenary job object
function M.run(prompt, opts)
	opts = opts or {}
	local cfg = vim.tbl_deep_extend("force", M.config, opts)

	local out = {}

	local job_args = { "-p", prompt }
	if opts.continue then
		table.insert(job_args, "--continue")
	end

	notify("info", "=== Claude Start ===")
	notify("debug", "Prompt: " .. prompt:sub(1, 100))

	local job = Job:new({
		command = cfg.bin,
		args = job_args,
		cwd = cfg.project,
		writer = "",
		on_start = function()
			notify("debug", "Job started")
		end,
		on_stderr = function(_, data)
			if data and data ~= "" then
				notify("warn", "stderr: " .. data)
			end
		end,
		on_stdout = function(_, data)
			if not data or data == "" then
				return
			end

			notify("debug", "stdout: " .. data:sub(1, 100))
			table.insert(out, data)

			if opts.on_stdout then
				vim.schedule(function()
					opts.on_stdout(data)
				end)
			end
		end,
		on_exit = function(j, code)
			vim.schedule(function()
				notify("info", "Exit: " .. code)
				notify("debug", "Output: " .. #out .. " lines")

				if code ~= 0 then
					local err = "Failed with code " .. code
					local stderr = j:stderr_result()
					if stderr and #stderr > 0 then
						err = err .. ": " .. table.concat(stderr, "\n")
					end
					notify("error", err)
					if opts.on_error then
						opts.on_error(err)
					end
					return
				end

				local result = table.concat(out, "\n"):gsub("\n$", "")
				notify("info", "Success: " .. #out .. " lines")

				if opts.on_success then
					opts.on_success(result)
				end
			end)
		end,
	})

	job:start()
	notify("debug", "Job dispatched")
	return job
end

--- Strip markdown code fences from result if present
---@param text string
---@return string
local function strip_markdown_fences(text)
	-- Match ```lang\n...\n``` pattern
	local stripped = text:match("^```[^\n]*\n(.-)\n```%s*$")
	if stripped then
		return stripped
	end
	-- Match ```\n...\n``` pattern (no language)
	stripped = text:match("^```\n(.-)\n```%s*$")
	if stripped then
		return stripped
	end
	return text
end

--- Replace visual selection with Claude response (with UI)
---@param args table Command args
---@param opts? table Options: skill (path to skill file), continue (use --continue flag)
function M.replace(args, opts)
	opts = opts or {}

	local query = args.args
	if query == "" then
		query = vim.fn.input("Claude: ")
		if query == "" then
			return
		end
	end

	-- Get selection positions
	local s = vim.fn.getpos("'<")
	local e = vim.fn.getpos("'>")
	local sl, sc, el, ec = s[2] - 1, s[3] - 1, e[2] - 1, e[3]

	-- Get selected text
	local lines = vim.api.nvim_buf_get_text(0, sl, sc, el, ec, {})
	local text = table.concat(lines, "\n")

	if text == "" then
		vim.notify("run-ai-run: no text selected", vim.log.levels.WARN)
		return
	end

	-- Build prompt with optional skill directive
	local prompt = query .. "\n\n" .. text
	if opts.skill then
		local skill_content = ""
		local f = io.open(opts.skill, "r")
		if f then
			skill_content = f:read("*a")
			f:close()
		end
		if skill_content ~= "" then
			prompt = "Follow these instructions:\n\n" .. skill_content .. "\n\n---\n\n" .. prompt
		end
	end
	local bufnr = vim.api.nvim_get_current_buf()

	-- UI state
	local running = true
	local timer = nil

	local hl = M.config.highlight
	local spinner_type = M.config.spinner

	-- Highlight selected text
	local selection_marks = {}
	for i = sl, el do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		local line_len = #line
		local line_start = (i == sl) and math.min(sc, line_len) or 0
		local line_end = (i == el) and math.min(ec, line_len) or line_len
		local mark = vim.api.nvim_buf_set_extmark(bufnr, ns, i, line_start, {
			end_col = line_end,
			hl_group = hl,
		})
		table.insert(selection_marks, mark)
	end

	-- Spinner extmark
	local spinner_mark = vim.api.nvim_buf_set_extmark(bufnr, ns, el, 0, {
		virt_text = { { " " .. spinners.spin(spinner_type) .. " Processing...", hl } },
		virt_text_pos = "eol",
	})

	-- Cleanup UI
	local function cleanup()
		running = false
		if timer then
			timer:stop()
			timer:close()
			timer = nil
		end
		pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, spinner_mark)
		for _, mark in ipairs(selection_marks) do
			pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark)
		end
	end

	-- Spinner animation
	timer = vim.uv.new_timer()
	timer:start(
		0,
		80,
		vim.schedule_wrap(function()
			if not running or not vim.api.nvim_buf_is_valid(bufnr) then
				cleanup()
				return
			end
			pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, el, 0, {
				id = spinner_mark,
				virt_text = { { " " .. spinners.spin(spinner_type) .. " Processing...", hl } },
				virt_text_pos = "eol",
			})
		end)
	)

	-- Run Claude
	M.run(prompt, {
		continue = opts.continue,
		on_stdout = function(data)
			if not running or not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			local display = data
			if #display > 50 then
				display = display:sub(1, 50) .. "..."
			end
			pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, el, 0, {
				id = spinner_mark,
				virt_text = { { " " .. spinners.spin(spinner_type) .. " " .. display, hl } },
				virt_text_pos = "eol",
			})
		end,
		on_success = function(result)
			cleanup()
			result = strip_markdown_fences(result)
			local new = vim.split(result, "\n", { plain = true })
			if vim.api.nvim_buf_is_valid(bufnr) then
				local end_line = vim.api.nvim_buf_get_lines(bufnr, el, el + 1, false)[1] or ""
				local end_col = math.min(ec, #end_line)
				vim.api.nvim_buf_set_text(bufnr, sl, sc, el, end_col, new)
				notify("info", "Replaced with " .. #new .. " lines")
			end
		end,
		on_error = function(err)
			cleanup()
			vim.notify("run-ai-run: " .. err, vim.log.levels.ERROR)
		end,
	})
end

--- Create a job (wrapper around plenary.job)
---@param opts table Same options as plenary.job
---@return table job The plenary job object
function M.job(opts)
	return Job:new(opts)
end

return M
