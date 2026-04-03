--- LuaJIT FFI declarations for liter-llm C API
--- Maps directly to crates/liter-llm-ffi/liter_llm.h
local ffi = require("ffi")

ffi.cdef[[
  // Opaque client handle
  typedef struct LiterLlmClient LiterLlmClient;

  // Stream callback
  typedef void (*LiterLlmStreamCallback)(const char *chunk_json, void *user_data);

  // Hook callbacks
  typedef struct LiterLlmHookCallbacks {
    int32_t (*on_request)(const char *request_json, void *user_data);
    void (*on_response)(const char *request_json, const char *response_json, void *user_data);
    void (*on_error)(const char *request_json, const char *error_message, void *user_data);
    void *user_data;
  } LiterLlmHookCallbacks;

  // Client lifecycle
  LiterLlmClient *literllm_client_new(const char *api_key, const char *base_url, const char *model_hint);
  LiterLlmClient *literllm_client_new_with_config(const char *config_json);
  void literllm_client_free(LiterLlmClient *client);

  // Core operations (return JSON string or NULL on error)
  char *literllm_chat(const LiterLlmClient *client, const char *request_json);
  int32_t literllm_chat_stream(const LiterLlmClient *client, const char *request_json, LiterLlmStreamCallback callback, void *user_data);
  char *literllm_embed(const LiterLlmClient *client, const char *request_json);
  char *literllm_list_models(const LiterLlmClient *client);

  // Multimedia
  char *literllm_image_generate(const LiterLlmClient *client, const char *request_json);
  char *literllm_speech(const LiterLlmClient *client, const char *request_json);
  char *literllm_transcribe(const LiterLlmClient *client, const char *request_json);
  char *literllm_moderate(const LiterLlmClient *client, const char *request_json);
  char *literllm_rerank(const LiterLlmClient *client, const char *request_json);
  char *literllm_search(const LiterLlmClient *client, const char *request_json);
  char *literllm_ocr(const LiterLlmClient *client, const char *request_json);

  // Files
  char *literllm_create_file(const LiterLlmClient *client, const char *request_json);
  char *literllm_retrieve_file(const LiterLlmClient *client, const char *file_id);
  char *literllm_delete_file(const LiterLlmClient *client, const char *file_id);
  char *literllm_list_files(const LiterLlmClient *client, const char *query_json);
  char *literllm_file_content(const LiterLlmClient *client, const char *file_id);

  // Batches
  char *literllm_create_batch(const LiterLlmClient *client, const char *request_json);
  char *literllm_retrieve_batch(const LiterLlmClient *client, const char *batch_id);
  char *literllm_list_batches(const LiterLlmClient *client, const char *query_json);
  char *literllm_cancel_batch(const LiterLlmClient *client, const char *batch_id);

  // Responses
  char *literllm_create_response(const LiterLlmClient *client, const char *request_json);
  char *literllm_retrieve_response(const LiterLlmClient *client, const char *response_id);
  char *literllm_cancel_response(const LiterLlmClient *client, const char *response_id);

  // Utilities
  double literllm_budget_usage(const LiterLlmClient *client);
  const char *literllm_last_error(void);
  void literllm_free_string(char *s);
  const char *literllm_version(void);

  // Provider management
  int32_t literllm_register_provider(const char *config_json);
  int32_t literllm_unregister_provider(const char *name);

  // Hooks
  int32_t literllm_set_hooks(LiterLlmClient *client, const LiterLlmHookCallbacks *callbacks);
]]

local M = {}

--- Resolve the bundled lib directory relative to this file
---@return string
local function bundled_lib_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  local dir = source:match("(.*/)")
  return dir .. "lib"
end

--- Platform-specific library filename and subdirectory
---@return string subdir, string filename
local function platform_lib()
  local os_name = jit and jit.os or "Linux"
  local arch = jit and jit.arch or "x64"

  if os_name == "Linux" then
    local subdir = arch == "arm64" and "linux-arm64" or "linux-x64"
    return subdir, "libliter_llm_ffi.so"
  elseif os_name == "OSX" then
    return "osx-arm64", "libliter_llm_ffi.dylib"
  elseif os_name == "Windows" then
    return "win-x64", "liter_llm_ffi.dll"
  end
  return "linux-x64", "libliter_llm_ffi.so"
end

--- Resolve the user cache directory (populated by download.lua)
---@return string
local function cache_lib_dir()
  return vim.fn.stdpath("data") .. "/run-ai-run/lib"
end

--- Load the shared library
---@param lib_path? string Path to libliter_llm.so/dylib/dll (auto-detected if nil)
---@return ffi.namespace*
function M.load(lib_path)
  if lib_path then
    return ffi.load(lib_path)
  end

  local subdir, filename = platform_lib()

  -- 1. Bundled (shipped with plugin, gitignored for size)
  local bundled = bundled_lib_dir() .. "/" .. subdir .. "/" .. filename
  local ok, lib = pcall(ffi.load, bundled)
  if ok then return lib end

  -- 2. User cache (downloaded at runtime via M.ensure())
  local cached = cache_lib_dir() .. "/" .. subdir .. "/" .. filename
  ok, lib = pcall(ffi.load, cached)
  if ok then return lib end

  -- 3. System-installed
  local names = { "liter_llm_ffi", "liter_llm", "libliter_llm" }
  for _, name in ipairs(names) do
    ok, lib = pcall(ffi.load, name)
    if ok then return lib end
  end

  error(
    "liter-llm shared library not found.\n"
    .. "Tried bundled: " .. bundled .. "\n"
    .. "Tried cache:   " .. cached .. "\n"
    .. "Call require('run-ai-run.liter').ensure(url, callback) to download it."
  )
end

return M
