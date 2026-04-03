--- Async download of liter-llm shared library with progress UI
local M = {}

local CACHE_DIR = vim.fn.stdpath("data") .. "/run-ai-run/lib"

---@return string subdir, string filename
local function platform_info()
  local os_name = jit and jit.os or "Linux"
  local arch = jit and jit.arch or "x64"
  if os_name == "Linux" then
    local subdir = arch == "arm64" and "linux-arm64" or "linux-x64"
    return subdir, "libliter_llm_ffi.so"
  elseif os_name == "OSX" then
    return "osx-arm64", "libliter_llm_ffi.dylib"
  elseif os_name == "Windows" then
    return "win-x64", "liter_llm_ffi.dll"
  end
  return "linux-x64", "libliter_llm_ffi.so"
end

--- Path where the library will be cached
---@return string
function M.cache_path()
  local subdir, filename = platform_info()
  return CACHE_DIR .. "/" .. subdir .. "/" .. filename
end

--- Whether the library is already cached
---@return boolean
function M.is_cached()
  return vim.fn.filereadable(M.cache_path()) == 1
end

local function open_float(lines, width)
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })
  return buf, win
end

local function update_float(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Download the shared library with a floating progress buffer.
---@param url string  Full URL of the .so/.dylib/.dll to download
---@param on_done fun(path: string)  Called with the cached path on success
---@param on_err  fun(msg: string)   Called on failure
function M.download(url, on_done, on_err)
  local dest = M.cache_path()
  local dest_dir = dest:match("(.*/)")
  vim.fn.mkdir(dest_dir, "p")

  local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local spin_i = 1
  local width = 46

  -- Fetch Content-Length via HEAD so we can show real %
  local total_bytes = 0
  local head_job = vim.fn.jobstart({ "curl", "-sI", url }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        local n = line:lower():match("^content%-length:%s*(%d+)")
        if n then total_bytes = tonumber(n) or 0 end
      end
    end,
  })
  vim.fn.jobwait({ head_job }, 5000)

  local buf, win = open_float({
    "  ⠋ liter-llm  0.0MB / ?",
    "  [                    ]   0%",
  }, width)

  -- Poll downloaded file size for progress updates
  local timer = vim.loop.new_timer()
  timer:start(100, 200, vim.schedule_wrap(function()
    if not vim.api.nvim_win_is_valid(win) then
      timer:stop()
      return
    end

    spin_i = (spin_i % #spinners) + 1
    local spinner = spinners[spin_i]

    local done_bytes = vim.fn.getfsize(dest)
    if done_bytes < 0 then done_bytes = 0 end

    local pct = 0
    local bar
    if total_bytes > 0 then
      pct = math.min(100, math.floor(done_bytes * 100 / total_bytes))
      local filled = math.floor(pct / 5)
      bar = string.rep("█", filled) .. string.rep(" ", 20 - filled)
    else
      -- no size info: animate a bouncing block
      local pos = math.floor(vim.loop.now() / 120) % 20
      bar = string.rep(" ", pos) .. "██" .. string.rep(" ", math.max(0, 18 - pos))
    end

    local mb_done = string.format("%.1fMB", done_bytes / 1048576)
    local mb_total = total_bytes > 0 and string.format("%.1fMB", total_bytes / 1048576) or "?"

    update_float(buf, {
      string.format("  %s liter-llm  %s / %s", spinner, mb_done, mb_total),
      string.format("  [%s] %3d%%", bar, pct),
    })
  end))

  vim.fn.jobstart({ "curl", "-L", "--no-progress-meter", "-o", dest, url }, {
    on_exit = function(_, code)
      timer:stop()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if code == 0 then
          on_done(dest)
        else
          vim.fn.delete(dest)
          on_err(string.format("liter-llm: download failed (curl exit %d)", code))
        end
      end)
    end,
  })
end

return M
