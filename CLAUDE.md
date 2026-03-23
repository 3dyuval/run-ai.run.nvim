# run-ai.run.nvim

Neovim plugin that sends selections to an AI (OpenAI-compatible API) and replaces them with the response. Features streaming, spinner UI, skill templates, and an accept/reject diff flow.

## Active skill: learning-coach

This directory is a learning-coach project. When the user invokes exercises, tests, or asks to practice, run the learning-coach skill against DICTIONARY.md.

## Stack

- **Language:** Lua (Neovim LuaJIT)
- **Transport:** `vim.system` + curl (no external deps)
- **API spec:** OpenAI chat completions (`/v1/chat/completions`)
- **Streaming:** SSE (`data: {...}` lines)

## File layout

```
lua/run-ai-run/
├── init.lua      -- public API, commands, UI (replace, accept/reject)
├── client.lua    -- HTTP client: vim.system + curl, streaming
└── sse.lua       -- SSE chunk parser and buffer
```

## Conventions

- All public functions documented with `---@param` / `---@return`
- No blocking calls — everything async via callbacks
- `vim.schedule()` required before any nvim API call in async callbacks
- `pcall()` around all extmark operations
- No `plenary` or `noice` dependencies in client/sse modules

## Key commands (when implemented)

- `:AIRun` — replace selection, fresh context
- `:AIContinue` — replace selection, append to session
- `:AISkill{Name}` — replace using skill prompt prefix

## Testing

Run from plugin root. No test framework set up yet.
