--- SSE (Server-Sent Events) chunk parser for OpenAI streaming responses
---@module 'run-ai-run.sse'
local M = {}

--- Create a new SSE parser instance.
--- Feed it raw curl stdout chunks; it calls on_chunk(delta) per token
--- and on_done() when [DONE] is received.
---
---@param on_chunk fun(delta: string) Called for each text delta
---@param on_done fun() Called when stream ends
---@return table parser
function M.new(on_chunk, on_done)
  -- TODO: initialize buffer state
  -- buf = ""
  local parser = {}

  --- Feed a raw chunk from curl stdout into the parser.
  ---@param chunk string Raw bytes from curl --no-buffer
  function parser:feed(chunk)
    -- TODO:
    -- 1. buf = buf .. chunk
    -- 2. split buf on "\n\n" to extract complete events
    -- 3. for each event line starting with "data: ":
    --    a. if line == "data: [DONE]" → call on_done(), return
    --    b. strip "data: " prefix, pcall(vim.json.decode)
    --    c. extract choices[1].delta.content
    --    d. if non-empty string → call on_chunk(delta)
    -- 4. keep incomplete remainder in buf
  end

  return parser
end

return M
