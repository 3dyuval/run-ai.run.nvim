--- OpenAI-compatible HTTP client using vim.system + curl
---@module 'run-ai-run.client'
local M = {}

---@class ClientConfig
---@field api_key string
---@field base_url string e.g. "https://api.openai.com"
---@field model string e.g. "gpt-4.1"
---@field temperature? number default 0.2

---@class Client
---@field config ClientConfig

--- Create a new client instance.
---@param config ClientConfig
---@return Client
function M.new(config)
  -- TODO: validate required fields (api_key, base_url, model)
  local client = { config = config }

  --- Send a chat completion request with streaming.
  ---@param messages table Array of {role, content} message objects
  ---@param opts? table Extra request options (temperature, max_tokens, etc.)
  ---@param on_chunk fun(delta: string) Called per streamed token
  ---@param on_done fun(full_text: string) Called when stream completes
  ---@param on_error fun(err: string) Called on failure
  function client:chat(messages, opts, on_chunk, on_done, on_error)
    opts = opts or {}

    -- TODO:
    -- 1. build request body: { model, messages, stream=true, temperature, ...opts }
    -- 2. build curl argv:
    --    { "curl", "-s", "-N", "--no-buffer", "-X", "POST",
    --      config.base_url .. "/v1/chat/completions",
    --      "-H", "Authorization: Bearer " .. config.api_key,
    --      "-H", "Content-Type: application/json",
    --      "-d", vim.json.encode(body) }
    -- 3. create sse parser: require("run-ai-run.sse").new(on_chunk, function()
    --      on_done(accumulated_text)
    --    end)
    -- 4. vim.system(curl_cmd, {
    --      text = true,
    --      stdout = function(err, chunk)
    --        if chunk then parser:feed(chunk) end
    --      end,
    --    }, function(result)
    --      if result.code ~= 0 then on_error(result.stderr) end
    --    })
  end

  return client
end

return M
