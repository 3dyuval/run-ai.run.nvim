local M = {}

local ns = vim.api.nvim_create_namespace("run_ai_run")

-- Get plugin root directory
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

--- liter-llm binding passthrough
--- Access via require("run-ai-run").liter or require("run-ai-run.liter")
M.liter = require("run-ai-run.liter")

-- Default configuration
M.config = {
  log_level = "debug",
  notify_level = "error",
  spinner = "dots",
  highlight = "DiagnosticInfo",
  skills_path = nil,
  on_sent = nil, -- optional callback fired after prompt is sent

  --- liter-llm provider configs to register on setup
  ---@type liter_llm.CustomProvider[]?
  providers = nil,

  --- liter-llm client options — creates a shared client accessible via M.client
  ---@type liter_llm.ClientOptions?
  liter = nil,

  --- Path to liter-llm shared library (auto-detected if nil)
  ---@type string?
  lib_path = nil,
}

--- Shared liter-llm client instance, created during setup if config.liter is set
---@type liter_llm.Client?
M.client = nil

local log
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

  spinners = require("noice.util.spinners")

  log = require("plenary.log").new({
    plugin = "run-ai-run",
    level = M.config.log_level,
    use_console = false,
    use_file = true,
  })

  notify("info", "=== run-ai-run loaded ===")

  vim.api.nvim_create_user_command("Claude", function(args)
    M.replace(args)
  end, {
    range = true,
    nargs = "*",
    desc = "Send selection to Claude session",
  })

  vim.api.nvim_create_user_command("LlmReplace", function(args)
    M.replace_with_response(args)
  end, {
    range = true,
    nargs = "*",
    desc = "Replace selection with LLM response",
  })

  vim.api.nvim_create_user_command("ClaudeSkillClaude", function(args)
    M.replace(args, {
      skill = plugin_dir .. "/.claude/skills/run-ai-run.nvim.md",
    })
  end, {
    range = true,
    nargs = "*",
    desc = "Send selection to Claude with run-ai-run skill",
  })

  if M.config.skills_path then
    M.load_skills(M.config.skills_path)
  end

  -- Register liter-llm providers
  if M.config.providers then
    for _, provider in ipairs(M.config.providers) do
      local ok, err = pcall(M.liter.register_provider, provider, M.config.lib_path)
      if ok then
        notify("info", "Registered provider: " .. provider.name)
      else
        notify("error", "Failed to register provider " .. provider.name .. ": " .. tostring(err))
      end
    end
  end

  -- Create shared liter-llm client
  if M.config.liter then
    local ok, client = pcall(M.liter.new, M.config.liter, M.config.lib_path)
    if ok then
      M.client = client
      notify("info", "liter-llm client ready (v" .. M.liter.version(M.config.lib_path) .. ")")
    else
      notify("error", "Failed to create liter-llm client: " .. tostring(client))
    end
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
    local name = vim.fn.fnamemodify(file, ":t:r")
    local cmd_name = "ClaudeSkill" .. name:gsub("[^%w]", ""):gsub("^%l", string.upper)

    vim.api.nvim_create_user_command(cmd_name, function(args)
      M.replace(args, { skill = file })
    end, {
      range = true,
      nargs = "*",
      desc = "Send selection to Claude using " .. name .. " skill",
    })

    notify("info", "Loaded skill: " .. name .. " -> :" .. cmd_name)
  end
end

--- Send prompt to the running tmux claude session
---@param prompt string The prompt to send
---@param opts? table Options: on_sent, on_error
function M.run(prompt, opts)
  opts = opts or {}

  local kitty_pid = vim.env.KITTY_PID
  if not kitty_pid then
    local err = "KITTY_PID not set — not running inside kitty"
    notify("error", err)
    if opts.on_error then opts.on_error(err) end
    return
  end

  local session = "kitty-" .. kitty_pid
  notify("info", "Sending to tmux session: " .. session)
  notify("debug", "Prompt: " .. prompt:sub(1, 100))

  local escaped = vim.fn.shellescape(prompt)
  local cmd = string.format("tmux send-keys -t %s %s Enter", vim.fn.shellescape(session), escaped)

  local ok = os.execute(cmd)
  if ok ~= 0 and ok ~= true then
    local err = "Failed to send to tmux session: " .. session
    notify("error", err)
    if opts.on_error then opts.on_error(err) end
    return
  end

  notify("info", "Sent to claude session")
  if opts.on_sent then opts.on_sent() end
end

--- Replace visual selection with Claude's response
---@param args table Command args
---@param opts? table Options: skill (path to skill file)
function M.replace_with_response(args, opts)
  opts = opts or {}

  local query = args.args
  if query == "" then
    query = vim.fn.input("Claude: ")
    if query == "" then
      return
    end
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

  local prompt = query .. "\n\n" .. text
  if opts.skill then
    local f = io.open(opts.skill, "r")
    if f then
      local skill_content = f:read("*a")
      f:close()
      if skill_content ~= "" then
        prompt = "Follow these instructions:\n\n" .. skill_content .. "\n\n---\n\n" .. prompt
      end
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

  local spinner_mark = vim.api.nvim_buf_set_extmark(bufnr, ns, el, 0, {
    virt_text = { { " " .. spinners.spin(spinner_type) .. " Thinking...", hl } },
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
      virt_text = { { " " .. spinners.spin(spinner_type) .. " Thinking...", hl } },
      virt_text_pos = "eol",
    })
  end))

  if not M.client then
    cleanup()
    vim.notify("run-ai-run: no liter-llm client configured", vim.log.levels.ERROR)
    return
  end

  local client = M.client
  vim.schedule_wrap(function()
    local ok, resp = pcall(client.chat, client, {
      model = M.config.liter.model or "openai/gpt-4o",
      messages = { { role = "user", content = prompt } },
    })
    vim.schedule(function()
      cleanup()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if ok and resp.choices and resp.choices[1] then
        local content = resp.choices[1].message.content or ""
        local result = vim.split(content, "\n")
        vim.api.nvim_buf_set_text(bufnr, sl, sc, el, ec, result)
      else
        vim.notify("run-ai-run: " .. tostring(resp), vim.log.levels.ERROR)
      end
    end)
  end)()
end

--- Send visual selection with optional prompt and skill to Claude session
---@param args table Command args
---@param opts? table Options: skill (path to skill file)
function M.replace(args, opts)
  opts = opts or {}

  local query = args.args
  if query == "" then
    query = vim.fn.input("Claude: ")
    if query == "" then
      return
    end
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

  local prompt = query .. "\n\n" .. text
  if opts.skill then
    local f = io.open(opts.skill, "r")
    if f then
      local skill_content = f:read("*a")
      f:close()
      if skill_content ~= "" then
        prompt = "Follow these instructions:\n\n" .. skill_content .. "\n\n---\n\n" .. prompt
      end
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

  local spinner_mark = vim.api.nvim_buf_set_extmark(bufnr, ns, el, 0, {
    virt_text = { { " " .. spinners.spin(spinner_type) .. " Sending...", hl } },
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
      virt_text = { { " " .. spinners.spin(spinner_type) .. " Sending...", hl } },
      virt_text_pos = "eol",
    })
  end))

  M.run(prompt, {
    on_sent = function()
      cleanup()
      if M.config.on_sent then M.config.on_sent() end
    end,
    on_error = function(err)
      cleanup()
      vim.notify("run-ai-run: " .. err, vim.log.levels.ERROR)
    end,
  })
end

return M
