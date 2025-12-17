
## TODO: Selection as UI-only, Full File as Context

| Aspect | Current Behavior | Desired Behavior |
|--------|------------------|------------------|
| Selection | Sent as context + replaced | UI only (highlight, spinner) |
| Context | Selected text | Entire file |
| Replacement | Replaces selection | Still replaces selection |
| UI (highlight) | On selection | Same |
| UI (spinner) | End of selection | Same |

### Use Case
User selects a function but wants Claude to see the whole file for context (imports, types, related functions) while still replacing only the selection.

### Proposed API

```lua
-- Option 1: Flag in opts
M.replace(args, { context = "file" })  -- vs default "selection"

-- Option 2: Separate command
vim.api.nvim_create_user_command("ClaudeFile", function(args)
  M.replace(args, { context = "file" })
end, { range = true, nargs = "*" })

-- Option 3: Context builder function
M.replace(args, {
  context = function(selection, bufnr)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
})
```

### Prompt Structure

```
[user prompt]

File: [filename]
```lua
[entire file content]
```

Selection (lines X-Y):
```lua
[selected text - for reference only]
```
```

---

## Claude Code Permissions Model

| Factor | Location | Scope | Notes |
|--------|----------|-------|-------|
| `cwd` (plugin default) | `plugin_dir` | Plugin only | Claude can only access files within plugin directory |
| `cwd` (user override) | `opts.project` | Custom | User sets via `setup({ project = "..." })` |
| Project settings | `<cwd>/.claude/settings.json` | Per-project | Checked in, shared with team |
| User settings | `~/.claude/settings.local.json` | Global user | Personal overrides, not checked in |
| Env var | `CLAUDE_CONFIG_DIR` | Global | Override config directory location |

### Permission Resolution Order

1. **User local** (`~/.claude/settings.local.json`) - highest priority
2. **Project** (`<cwd>/.claude/settings.json`) - project-specific
3. **Defaults** - Claude's built-in defaults

### Common User Scenarios

| Scenario | Solution |
|----------|----------|
| User wants Claude to access their whole project | `setup({ project = vim.fn.getcwd() })` |
| User wants to use their global permissions | Permissions from `~/.claude/settings.local.json` always apply |
| User wants plugin-scoped Claude (safe) | Default behavior (`project = plugin_dir`) |
| User wants to allow specific tools | Add to `allowedTools` in settings.local.json |

### Example: User Settings Override

```json
// ~/.claude/settings.local.json
{
  "permissions": {
    "allowedTools": ["Read", "Glob", "Grep", "Bash(git *)"],
    "deniedTools": ["Write", "Edit"]
  }
}
```

### Plugin Config Example

```lua
require("run-ai-run").setup({
  -- Use current working directory instead of plugin dir
  project = vim.fn.getcwd(),
  -- Or use a specific project root
  -- project = vim.fn.finddir(".git/..", vim.fn.expand("%:p:h") .. ";"),
})
```

---

how to handle searching  with **permissions** using claude:

```lua
return {
  {
    "3dyuval/history-api.nvim",
    dependencies = {
      "folke/snacks.nvim",
      "kkharji/sqlite.lua",
    },
    config = function()
      require("history-api").setup({
        create_commands = true,
        enabled_browsers = { "chromium", "brave", "firefox", "zen" },
        browser_paths = {
          firefox = "~/.mozilla/firefox/*.default-release/places.sqlite",
          zen = "~/.zen/*/places.sqlite",
          chromium = "~/.config/chromium/Default/History",
          brave = "~/.config/BraveSoftware/Brave-Browser/Default/History",
        },
      })
    end,
  },
}

--[[[
 To find your actual paths, run these commands in your terminal:
 ```bash
 # Firefox
 ls ~/.mozilla/firefox/*/places.sqlite
 # Zen
 ls ~/.zen/*/places.sqlite
 # Chromium
 ls ~/.config/chromium/Default/History
 # Brave
 ls ~/.config/BraveSoftware/Brave-Browser/Default/History
 ```
 Then update the `browser_paths` with the exact paths found.,
              ]]
--
```


how to handle additional context?
use cage: search all comment blocks for additional information.
add a an option to include external files referenced in comments like in

```lua
-- This document tests for critical keys tested
-- the describe blocks can have semantic/pasitional/organizational meaning
-- or it should test different implementations, to document workarounds
-- made while using highly customized keyboard layout and mappings
-- for more context on the organizational methodology @../../../CLAUDE.md

describe("normal inserts/replace", function()
  it('sould instel before using "r"', function()
    -- todo
  end)

  it('should insert after using "t"', function()
    -- todo
  end)
end)

describe("paste inserts/replace", function()
  it('should paste before using "v"', function()
    -- todo
  end)

  it('should paste after using "V"', function()
    -- todo
  end)

  it('should paste+replace using "-"', function()
    -- todo
  end)
end)

describe("delete and yank", function()
  it("should delete without registers using _xx", function()
    -- todo
  end)

  it('should paste after using "V"', function()
    -- todo
  end)

  it('should paste+replace using "-"', function()
    -- todo
  end)
end)


```


lets say i selected this blocks
```lua
vim.keymap.set({ "o", "x" }, "r`", function()
  code.select_fenced_code_block(true)
  -- TODO: should move cursor into the fence
  -- TEST: add to @./tests/keymaps.test.lua
end, { desc = "Inner code block" })
```

how would the additional context (todos, tests, files) allow for further enhancement prompt window
e.g:
1. allow files to be inserted into query one by one (same as running somtething like git clean or %s/abc/xyz/gc) or using snaks
2. allow events explicitly create different float/snacks in userland { opts = { secondary_context = { run= functions(current) require('ai-run').secondary(current) end } }}
