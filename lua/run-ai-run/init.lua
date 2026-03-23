local M = {}

local ns = vim.api.nvim_create_namespace("run_ai_run")

-- Get plugin root directory
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

-- Default configuration
-- TODO [Part 3: OpenAI API Spec] replace bin/project with api_key, base_url, model
M.config = {
	bin = "/home/yuv/.nvm/versions/node/v20.19.6/bin/claude",
	project = plugin_dir,
	log_level = "debug",
	notify_level = "error", -- nil = off, "debug"/"info"/"warn"/"error" = show in noice
	spinner = "dots",
	highlight = "DiagnosticInfo",
	skills_path = nil,
}

-- TODO [Part 1: HTTP via vim.system] swap Job for client module
-- TODO [Part 2: SSE Parsing] spinners.spin → local frame table, drop noice dep
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

	Job = require("plenary.job")
	spinners = require("noice.util.spinners")

	log = require("plenary.log").new({
		plugin = "run-ai-run",
		level = M.config.log_level,
		use_console = false,
		use_file = true,
	})

	-- TODO [Part 3: OpenAI API Spec] replace bin check with api_key validation
	if vim.fn.executable(M.config.bin) ~= 1 then
		notify("error", "Binary not found: " .. M.config.bin)
		return
	end

	notify("info", "=== run-ai-run loaded ===")
	notify("info", "Binary: " .. M.config.bin)
	notify("info", "Project: " .. M.config.project)

	-- TODO [Part 5: Conversation State] rename :Claude → :AIRun, :ClaudeContinue → :AIContinue
	vim.api.nvim_create_user_command("Claude", function(args)
		M.replace(args)
	end, {
		range = true,
		nargs = "*",
		desc = "Replace selection with Claude response",
	})

	-- TODO [Part 5: Conversation State] opts.continue → pass session.messages
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

	if M.config.skills_path then
		M.load_skills(M.config.skills_path)
	end
end

---@param skills_path string Path to the skills directory
function M.load_skills(skills_path)
	local path = vim.fn.expand(skills_path)
	if vim.fn.isdirectory(path) ~= 1 then
		notify("warn", "Skills path not found: " .. path)
		return
	end

	local files = vim.fn.glob(path .. "/*.md", false, true)
	for _, file in ipairs(files) do
		local name = vim.fn.fnamemodify(file, ":t:r")
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
-- TODO [Part 1: HTTP via vim.system] replace body with client:chat(messages, ...)
-- TODO [Part 2: SSE Parsing] on_stdout → on_chunk with per-token deltas
---@param prompt string
---@param opts? table on_success, on_error, on_stdout, continue
---@return table job
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

---@param text string
---@return string
local function strip_markdown_fences(text)
	local stripped = text:match("^```[^\n]*\n(.-)\n```%s*$")
	if stripped then return stripped end
	stripped = text:match("^```\n(.-)\n```%s*$")
	if stripped then return stripped end
	return text
end

--- Replace visual selection with Claude response (with UI)
---@param args table
---@param opts? table skill, continue
function M.replace(args, opts)
	opts = opts or {}

	local query = args.args
	if query == "" then
		query = vim.fn.input("Claude: ")
		if query == "" then return end
	end

	local s = vim.fn.getpos("'<")
	local e = vim.fn.getpos("'>")
	local sl, sc, el, ec = s[2] - 1, s[3] - 1, e[2] - 1, e[3]

	local lines = vim.api.nvim_buf_get_text(0, sl, sc, el, ec, {})
	local text = table.concat(lines, "\n")

	if text == "" then
		vim.notify("run-ai-run: no text selected", vim.log.levels.WARN)
		return
	end

	-- TODO [Part 3: OpenAI API Spec] convert prompt string → messages array
	-- TODO [Part 5: Conversation State] prepend session.messages when opts.continue
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
	local running = true
	local timer = nil
	local hl = M.config.highlight
	local spinner_type = M.config.spinner

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

	-- TODO [Part 2: SSE Parsing] replace spinners.spin with local frame table
	local spinner_mark = vim.api.nvim_buf_set_extmark(bufnr, ns, el, 0, {
		virt_text = { { " " .. spinners.spin(spinner_type) .. " Processing...", hl } },
		virt_text_pos = "eol",
	})

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

	timer = vim.uv.new_timer()
	timer:start(0, 80, vim.schedule_wrap(function()
		if not running or not vim.api.nvim_buf_is_valid(bufnr) then
			cleanup()
			return
		end
		pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, el, 0, {
			id = spinner_mark,
			virt_text = { { " " .. spinners.spin(spinner_type) .. " Processing...", hl } },
			virt_text_pos = "eol",
		})
	end))

	M.run(prompt, {
		continue = opts.continue,
		on_stdout = function(data)
			if not running or not vim.api.nvim_buf_is_valid(bufnr) then return end
			local display = #data > 50 and data:sub(1, 50) .. "..." or data
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
				-- TODO [Part 4: Accept/Reject Flow] stash original, install <CR>/<Esc> keymaps
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

---@param opts table plenary.job options
---@return table job
function M.job(opts)
	return Job:new(opts)
end

return M
