

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
