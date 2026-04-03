# run-ai-run.nvim

Neovim plugin for inline LLM editing and Claude Code integration.

## Setup

```lua
-- lazy.nvim
{
  dir = "/path/to/run-ai.run.nvim",  -- local dev, or use "3dyuval/run-ai.run.nvim"
  opts = {
    skills_path = "~/.config/nvim/.claude/skills",
    liter = {
      api_key = os.getenv("OPENAI_API_KEY"),
      model_hint = "openai/gpt-4o",
    },
  },
}
```

## liter-llm FFI client

`run-ai-run.liter` is a LuaJIT FFI binding to a Rust LLM client. The shared library (`.so`/`.dylib`/`.dll`) is **not bundled** — download it at runtime:

```lua
local liter = require("run-ai-run.liter")

liter.ensure(
  "https://github.com/3dyuval/run-ai.run.nvim/releases/latest/download/libliter_llm_ffi-linux-x64.so",
  function(lib)
    local client = lib.new({ api_key = os.getenv("OPENAI_API_KEY") })
    local res = client:chat({ model = "openai/gpt-4o", messages = {{ role = "user", content = "hi" }} })
    print(res.choices[1].message.content)
  end
)
```

`ensure` opens a **floating progress buffer** while downloading, then calls your callback. Subsequent calls are instant (cached in `stdpath("data")/run-ai-run/lib/`).

## Type annotations (lua_ls)

All types are defined in [`lua/run-ai-run/liter/types.lua`](lua/run-ai-run/liter/types.lua) as EmmyLua annotations.

**To get completions and type checking**, add this to your `lazy.nvim` spec:

```lua
{
  dir = "/path/to/run-ai.run.nvim",
  ---@type run_ai_run.Config
  opts = { ... },
}
```

The key types you get:

| Type | Where used |
|------|-----------|
| **`liter_llm.ClientOptions`** | `liter.new(opts)`, `config.liter` |
| **`liter_llm.ChatRequest`** | `client:chat(request)` |
| **`liter_llm.ChatResponse`** | return of `client:chat()` |
| **`liter_llm.ChatCompletionChunk`** | `client:chat_stream()` callback arg |
| **`liter_llm.EmbeddingRequest`** | `client:embed(request)` |
| **`liter_llm.CustomProvider`** | `liter.register_provider(provider)` |
| **`liter_llm.Hooks`** | `client:set_hooks(hooks)` |

**lua_ls workspace setup** — the `.luarc.json` at the project root configures the runtime. For lazy.nvim to expose types in your config files, add the plugin dir to your lua_ls `library`:

```lua
-- in your lua_ls lspconfig setup:
settings = {
  Lua = {
    workspace = {
      library = {
        "/path/to/run-ai.run.nvim/lua",
        -- or let lazy.nvim handle it:
        -- vim.fn.stdpath("data") .. "/lazy/run-ai.run.nvim/lua",
      },
    },
  },
}
```

Or with `lazydev.nvim` (recommended):

```lua
{
  "folke/lazydev.nvim",
  opts = {
    library = {
      { path = "run-ai.run.nvim/lua", words = { "run.ai.run", "liter" } },
    },
  },
}
```
