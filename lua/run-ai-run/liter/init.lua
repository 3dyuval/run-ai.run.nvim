--- liter-llm Lua binding
--- Universal LLM client powered by Rust FFI
---
--- Usage:
---   local liter = require("run-ai-run.liter")
---   local client = liter.new({ api_key = os.getenv("OPENAI_API_KEY") })
---   local response = client:chat({
---     model = "openai/gpt-4o",
---     messages = { { role = "user", content = "Hello!" } },
---   })
---   print(response.choices[1].message.content)

local ffi = require("ffi")
local ffi_loader = require("run-ai-run.liter.ffi")
local errors = require("run-ai-run.liter.errors")

---@class liter_llm.Client
---@field private _handle ffi.cdata*
---@field private _lib ffi.namespace*
---@field private _hooks_ref? ffi.cdata*  prevent GC of hook struct
local Client = {}
Client.__index = Client

local M = {}

--- Loaded library singleton
---@type ffi.namespace*?
local _lib = nil

--- Get or load the shared library
---@param lib_path? string
---@return ffi.namespace*
local function get_lib(lib_path)
  if not _lib or lib_path then
    _lib = ffi_loader.load(lib_path)
  end
  return _lib
end

--- Call an FFI function that returns char* JSON, handle errors and free the string
---@param lib ffi.namespace*
---@param ptr ffi.cdata*
---@return table
local function json_result(lib, ptr)
  if ptr == nil then
    error(errors.last(lib).message, 2)
  end
  local json_str = ffi.string(ptr)
  lib.literllm_free_string(ptr)
  return vim.json.decode(json_str)
end

--- Create a new LLM client
---@param opts liter_llm.ClientOptions
---@param lib_path? string Path to shared library
---@return liter_llm.Client
function M.new(opts, lib_path)
  local lib = get_lib(lib_path)
  local handle

  -- If only api_key given, use simple constructor
  if not opts.cache and not opts.budget and not opts.timeout_secs and not opts.extra_headers then
    handle = lib.literllm_client_new(
      opts.api_key,
      opts.base_url,
      opts.model_hint
    )
  else
    local config_json = vim.json.encode(opts)
    handle = lib.literllm_client_new_with_config(config_json)
  end

  if handle == nil then
    error(errors.last(lib).message)
  end

  local self = setmetatable({
    _handle = ffi.gc(handle, lib.literllm_client_free),
    _lib = lib,
  }, Client)

  return self
end

--- Create client from TOML config file path or JSON config string
---@param config_json string JSON config string
---@param lib_path? string
---@return liter_llm.Client
function M.from_config(config_json, lib_path)
  local lib = get_lib(lib_path)
  local handle = lib.literllm_client_new_with_config(config_json)
  if handle == nil then
    error(errors.last(lib).message)
  end
  return setmetatable({
    _handle = ffi.gc(handle, lib.literllm_client_free),
    _lib = lib,
  }, Client)
end

--- Chat completion
---@param request liter_llm.ChatRequest
---@return liter_llm.ChatResponse
function Client:chat(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_chat(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Streaming chat completion
---@param request liter_llm.ChatRequest
---@param on_chunk fun(chunk: liter_llm.ChatCompletionChunk)
---@return integer 0 on success, -1 on error
function Client:chat_stream(request, on_chunk)
  local req_json = vim.json.encode(request)
  local callback = ffi.cast("LiterLlmStreamCallback", function(chunk_json, _)
    if chunk_json ~= nil then
      local ok, chunk = pcall(vim.json.decode, ffi.string(chunk_json))
      if ok then
        on_chunk(chunk)
      end
    end
  end)
  local result = self._lib.literllm_chat_stream(self._handle, req_json, callback, nil)
  callback:free()
  if result ~= 0 then
    error(errors.last(self._lib).message)
  end
  return result
end

--- Generate embeddings
---@param request liter_llm.EmbeddingRequest
---@return liter_llm.EmbeddingResponse
function Client:embed(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_embed(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- List available models
---@return liter_llm.ModelsListResponse
function Client:list_models()
  local ptr = self._lib.literllm_list_models(self._handle)
  return json_result(self._lib, ptr)
end

--- Generate images
---@param request table
---@return table
function Client:image_generate(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_image_generate(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Text-to-speech
---@param request table
---@return table
function Client:speech(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_speech(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Transcribe audio
---@param request table
---@return table
function Client:transcribe(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_transcribe(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Content moderation
---@param request table
---@return table
function Client:moderate(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_moderate(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Rerank results
---@param request table
---@return table
function Client:rerank(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_rerank(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Web search
---@param request table
---@return table
function Client:search(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_search(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- OCR
---@param request table
---@return table
function Client:ocr(request)
  local req_json = vim.json.encode(request)
  local ptr = self._lib.literllm_ocr(self._handle, req_json)
  return json_result(self._lib, ptr)
end

--- Get budget usage
---@return number
function Client:budget_usage()
  return tonumber(self._lib.literllm_budget_usage(self._handle)) or 0
end

--- Set lifecycle hooks
---@param hooks liter_llm.Hooks
function Client:set_hooks(hooks)
  local cb = ffi.new("LiterLlmHookCallbacks")

  if hooks.on_request then
    cb.on_request = function(req_json, _)
      local ok = hooks.on_request(ffi.string(req_json))
      return (ok == false) and -1 or 0
    end
  end

  if hooks.on_response then
    cb.on_response = function(req_json, resp_json, _)
      hooks.on_response(ffi.string(req_json), ffi.string(resp_json))
    end
  end

  if hooks.on_error then
    cb.on_error = function(req_json, err_msg, _)
      hooks.on_error(ffi.string(req_json), ffi.string(err_msg))
    end
  end

  -- prevent GC
  self._hooks_ref = cb

  local result = self._lib.literllm_set_hooks(self._handle, cb)
  if result ~= 0 then
    error(errors.last(self._lib).message)
  end
end

-- Static utilities --

--- Register a custom provider
---@param provider liter_llm.CustomProvider
function M.register_provider(provider, lib_path)
  local lib = get_lib(lib_path)
  local json = vim.json.encode(provider)
  local result = lib.literllm_register_provider(json)
  if result == -1 then
    error(errors.last(lib).message)
  end
end

--- Unregister a custom provider
---@param name string
function M.unregister_provider(name, lib_path)
  local lib = get_lib(lib_path)
  local result = lib.literllm_unregister_provider(name)
  if result == -1 then
    error(errors.last(lib).message)
  end
end

--- Get library version
---@return string
function M.version(lib_path)
  local lib = get_lib(lib_path)
  local ptr = lib.literllm_version()
  return ffi.string(ptr)
end

--- Re-export errors module
M.errors = errors

return M
