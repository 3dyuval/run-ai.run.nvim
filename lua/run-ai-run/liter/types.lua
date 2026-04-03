--- EmmyLua type annotations for liter-llm Lua binding
--- These mirror the TypeScript types from packages/typescript/src/types.ts

---@class liter_llm.ClientOptions
---@field api_key string
---@field base_url? string
---@field model_hint? string
---@field cache? liter_llm.CacheConfig
---@field budget? liter_llm.BudgetConfig
---@field timeout_secs? number
---@field extra_headers? table<string, string>

---@class liter_llm.CacheConfig
---@field max_entries? integer
---@field ttl_seconds? integer
---@field backend? string
---@field backend_config? table<string, string>

---@class liter_llm.BudgetConfig
---@field global_limit? number
---@field model_limits? table<string, number>
---@field enforcement? "hard"|"soft"

-- Messages --

---@class liter_llm.SystemMessage
---@field role "system"
---@field content string
---@field name? string

---@class liter_llm.UserMessage
---@field role "user"
---@field content string|liter_llm.ContentPart[]
---@field name? string

---@class liter_llm.AssistantMessage
---@field role "assistant"
---@field content? string
---@field tool_calls? liter_llm.ToolCall[]
---@field refusal? string

---@class liter_llm.ToolMessage
---@field role "tool"
---@field content string
---@field tool_call_id string
---@field name? string

---@alias liter_llm.Message liter_llm.SystemMessage|liter_llm.UserMessage|liter_llm.AssistantMessage|liter_llm.ToolMessage

-- Content parts --

---@class liter_llm.TextPart
---@field type "text"
---@field text string

---@class liter_llm.ImageUrlPart
---@field type "image_url"
---@field image_url { url: string, detail?: "auto"|"low"|"high" }

---@alias liter_llm.ContentPart liter_llm.TextPart|liter_llm.ImageUrlPart

-- Tools --

---@class liter_llm.ToolCall
---@field id string
---@field type "function"
---@field function { name: string, arguments: string }

---@class liter_llm.FunctionDefinition
---@field name string
---@field description? string
---@field parameters? table
---@field strict? boolean

---@class liter_llm.ChatCompletionTool
---@field type "function"
---@field function liter_llm.FunctionDefinition

-- Response format --

---@class liter_llm.ResponseFormatText
---@field type "text"

---@class liter_llm.ResponseFormatJson
---@field type "json_object"

---@class liter_llm.ResponseFormatJsonSchema
---@field type "json_schema"
---@field json_schema { name: string, schema: table, strict?: boolean }

---@alias liter_llm.ResponseFormat liter_llm.ResponseFormatText|liter_llm.ResponseFormatJson|liter_llm.ResponseFormatJsonSchema

-- Chat request/response --

---@class liter_llm.ChatRequest
---@field model string
---@field messages liter_llm.Message[]
---@field temperature? number
---@field top_p? number
---@field max_tokens? number
---@field tools? liter_llm.ChatCompletionTool[]
---@field response_format? liter_llm.ResponseFormat
---@field stream? boolean
---@field stop? string|string[]
---@field seed? integer
---@field frequency_penalty? number
---@field presence_penalty? number
---@field n? integer
---@field user? string

---@class liter_llm.Usage
---@field prompt_tokens integer
---@field completion_tokens integer
---@field total_tokens integer

---@class liter_llm.Choice
---@field index integer
---@field message liter_llm.AssistantMessage
---@field finish_reason "stop"|"length"|"tool_calls"|"content_filter"

---@class liter_llm.ChatResponse
---@field id string
---@field object string
---@field created integer
---@field model string
---@field choices liter_llm.Choice[]
---@field usage? liter_llm.Usage

-- Streaming --

---@class liter_llm.ChatCompletionChunk
---@field id string
---@field object string
---@field created integer
---@field model string
---@field choices liter_llm.StreamChoice[]

---@class liter_llm.StreamChoice
---@field index integer
---@field delta liter_llm.Delta
---@field finish_reason? string

---@class liter_llm.Delta
---@field role? string
---@field content? string
---@field tool_calls? liter_llm.ToolCall[]

-- Embeddings --

---@class liter_llm.EmbeddingRequest
---@field model string
---@field input string|string[]
---@field dimensions? integer
---@field encoding_format? "float"|"base64"

---@class liter_llm.EmbeddingData
---@field index integer
---@field embedding number[]
---@field object string

---@class liter_llm.EmbeddingResponse
---@field object string
---@field data liter_llm.EmbeddingData[]
---@field model string
---@field usage liter_llm.Usage

-- Models --

---@class liter_llm.Model
---@field id string
---@field object string
---@field created integer
---@field owned_by string

---@class liter_llm.ModelsListResponse
---@field object string
---@field data liter_llm.Model[]

-- Hooks --

---@class liter_llm.Hooks
---@field on_request? fun(request_json: string): boolean  Return false to reject
---@field on_response? fun(request_json: string, response_json: string)
---@field on_error? fun(request_json: string, error_message: string)

-- Errors --

---@alias liter_llm.ErrorKind
---| "Authentication"
---| "RateLimited"
---| "BadRequest"
---| "ContextWindowExceeded"
---| "ContentPolicy"
---| "NotFound"
---| "ServerError"
---| "ServiceUnavailable"
---| "Timeout"
---| "Network"
---| "Streaming"
---| "EndpointNotSupported"
---| "InvalidHeader"
---| "Serialization"
---| "BudgetExceeded"
---| "HookRejected"

---@class liter_llm.Error
---@field kind liter_llm.ErrorKind
---@field message string

-- Custom provider --

---@class liter_llm.CustomProvider
---@field name string
---@field base_url string
---@field model_prefixes? string[]
---@field api_key_header? string
---@field default_headers? table<string, string>

return {}
