--- Error handling for liter-llm
local M = {}

--- Parse error string from FFI into structured error
---@param raw string Error string like "[RateLimited] Rate limit exceeded"
---@return liter_llm.Error
function M.parse(raw)
  local kind, message = raw:match("^%[(%w+)%]%s*(.*)")
  if kind then
    return { kind = kind, message = message }
  end
  return { kind = "Unknown", message = raw }
end

--- Create an error from the FFI last_error thread-local
---@param lib ffi.namespace* The loaded FFI library
---@return liter_llm.Error
function M.last(lib)
  local ffi = require("ffi")
  local ptr = lib.literllm_last_error()
  if ptr == nil then
    return { kind = "Unknown", message = "unknown error" }
  end
  return M.parse(ffi.string(ptr))
end

return M
