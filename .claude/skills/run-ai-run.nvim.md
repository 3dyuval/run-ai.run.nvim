# run-ai-run.nvim Code Generation

**Follow all rules from CLAUDE.md** - output only valid Lua code, no explanations, no markdown.

## API

require("run-ai-run").run(prompt, {
  continue = false,                -- --continue flag
  on_success = function(result) end,
  on_error = function(err) end,
  on_stdout = function(data) end,  -- streaming
})

Returns job for cancellation.

## Transform Patterns

Any job delegating work to AI:

BEFORE (plenary.job with claude):
Job:new({
  command = "claude",
  args = { "-p", prompt },
  writer = input,
  on_exit = function(j, code)
    local result = table.concat(j:result(), "\n")
    callback(result)
  end,
}):start()

AFTER:
require("run-ai-run").run(prompt .. "\n\n" .. input, {
  on_success = function(result) callback(result) end,
  on_error = function(err) vim.notify(err, vim.log.levels.ERROR) end,
})

## Shell Jobs

Use run_ai_run.job() for shell commands (same API as plenary.job):

run_ai_run.job({
  command = "git",
  args = { "diff", "--cached" },
  on_exit = function(j, code)
    local result = table.concat(j:result(), "\n")
  end,
}):start()

## Rules

- NEVER require plenary.job directly - use run_ai_run.job()
- Combine prompt + context into single prompt string
- on_exit code check -> on_success + on_error callbacks
- No vim.schedule needed in run() callbacks (already scheduled)
- Remove writer param (content goes in prompt)
