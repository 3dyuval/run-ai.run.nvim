# run-ai.run.nvim — Learning Dictionary

Building a Neovim plugin with an OpenAI-compatible HTTP backend, SSE streaming, and an accept/reject diff flow.

---

## Part 1: HTTP via vim.system

Neovim's built-in async subprocess API. Replaces plenary.job for HTTP calls.

### 1.1 vim.system basics
```lua
vim.system({"cmd", "arg"}, { text = true }, function(result)
  -- result.code, result.stdout, result.stderr
end)
```
Non-blocking. Callback fires on the main loop via `vim.schedule` automatically.

### 1.2 curl as HTTP client
```lua
vim.system({
  "curl", "-s", "-X", "POST", url,
  "-H", "Authorization: Bearer " .. key,
  "-H", "Content-Type: application/json",
  "-d", vim.json.encode(body),
}, { text = true }, callback)
```
No external deps. Works in any Neovim 0.10+ environment.

### 1.3 Streaming with curl
For SSE: add `--no-buffer -N` flags. Use `stdout` handler (per-chunk) instead of waiting for full result.
```lua
vim.system(cmd, {
  text = true,
  stdout = function(err, chunk) -- fires incrementally
    if chunk then parse_sse(chunk) end
  end,
}, on_exit)
```

### 1.4 Error handling
`result.code ~= 0` signals failure. `result.stderr` has the message. Always validate before JSON decode.

---

## Part 2: SSE Parsing

Server-Sent Events — the wire format for OpenAI streaming responses.

### 2.1 Wire format
```
data: {"choices":[{"delta":{"content":"Hello"}}]}

data: {"choices":[{"delta":{"content":" world"}}]}

data: [DONE]
```
Each event is `data: <json>\n\n`. `[DONE]` terminates the stream.

### 2.2 Chunk buffering
curl delivers chunks that may span multiple events or split one mid-line. A buffer is required:
```lua
local buf = ""
local function feed(chunk)
  buf = buf .. chunk
  -- split on \n\n, process complete events, keep remainder
end
```

### 2.3 Extracting delta text
```lua
local ok, decoded = pcall(vim.json.decode, json_str)
if ok then
  local delta = decoded.choices
    and decoded.choices[1]
    and decoded.choices[1].delta
    and decoded.choices[1].delta.content
  if delta then on_chunk(delta) end
end
```

### 2.4 [DONE] sentinel
```lua
if line == "data: [DONE]" then on_done() return end
```

---

## Part 3: OpenAI API Spec

The messages-based chat completions API. Works with OpenAI, Anthropic (compat), OpenRouter, Ollama.

### 3.1 Messages array
```lua
{
  { role = "system",    content = "You are a code assistant." },
  { role = "user",      content = "Refactor this:\n\n" .. code },
  { role = "assistant", content = "..." },  -- for multi-turn
  { role = "user",      content = "Now add types." },
}
```

### 3.2 Chat completions request
```lua
POST /v1/chat/completions
{
  model = "gpt-4.1",
  messages = [...],
  stream = true,
  temperature = 0.2,
}
```

### 3.3 Configurable base_url
Different providers share the same spec:
```lua
base_url = "https://api.openai.com"          -- OpenAI
base_url = "https://api.anthropic.com/v1"    -- Anthropic compat
base_url = "http://localhost:11434/v1"       -- Ollama
```

### 3.4 Client construction
```lua
local client = require("run-ai-run.client").new({
  api_key  = "sk-...",
  base_url = "https://api.openai.com",
  model    = "gpt-4.1",
})
client:chat(messages, opts, on_chunk, on_done, on_error)
```

---

## Part 4: Accept/Reject Diff Flow

Show AI result before committing it to the buffer. Let the user confirm or discard.

### 4.1 Stash original
```lua
local original = vim.api.nvim_buf_get_text(bufnr, sl, sc, el, ec, {})
```
Capture before writing. Used to restore on reject.

### 4.2 Apply result
```lua
local new_lines = vim.split(result, "\n", { plain = true })
vim.api.nvim_buf_set_text(bufnr, sl, sc, el, ec, new_lines)
```

### 4.3 One-shot keymap for reject
```lua
vim.keymap.set("n", "<Esc>", function()
  vim.api.nvim_buf_set_text(bufnr, sl, sc, el, ec, original)
  vim.keymap.del("n", "<Esc>", { buffer = bufnr })
  vim.keymap.del("n", "<CR>",  { buffer = bufnr })
end, { buffer = bufnr, nowait = true })

vim.keymap.set("n", "<CR>", function()
  vim.keymap.del("n", "<Esc>", { buffer = bufnr })
  vim.keymap.del("n", "<CR>",  { buffer = bufnr })
end, { buffer = bufnr, nowait = true })
```

### 4.4 diffthis preview (optional, heavier)
```lua
-- Open scratch split with original, run :diffthis on both
vim.cmd("leftabove vnew")
local scratch = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, original)
vim.cmd("diffthis")
vim.api.nvim_set_current_win(original_win)
vim.cmd("diffthis")
```

---

## Part 5: Conversation State

Multi-turn context: accumulate messages across calls instead of each call being independent.

### 5.1 Session table
```lua
local session = {
  messages = {},
  system = "You are a Neovim plugin developer assistant.",
}
```

### 5.2 Appending turns
```lua
table.insert(session.messages, { role = "user",      content = prompt })
table.insert(session.messages, { role = "assistant", content = result })
```

### 5.3 Reset vs continue
`M.replace()` — starts fresh, no history.
`M.replace_continue()` — appends to existing session.messages.

### 5.4 System prompt injection
Always prepend as first message:
```lua
local full_messages = { { role = "system", content = session.system } }
vim.list_extend(full_messages, session.messages)
```
