-- 用户自定义翻译接口：把设置里的一行 records 配置变成标准 provider。
--
-- 行字段（action.json 的 custom_providers）：
--   id          稳定标识（小写字母/数字/._-）
--   name        卡片标题
--   url         请求地址，支持 {text}（原文）、{text_q}（URL 编码）、{from}、{to}
--   method      post_json（默认）或 get
--   body        POST 体模板，用 {text_json} 安全插入原文
--   result_path 响应 JSON 的点路径（如 data.translation / translations.0.text）
--   headers     JSON 对象字符串，可用 {key} 引用设置里的 custom_api_key
local fail = require("lib.providers.fail")

local M = {}

local function nonempty(value)
  return type(value) == "string" and value ~= ""
end

local function json_escape(text)
  local map = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }
  return (string.gsub(text, '[%z\1-\31\\"]', function(char)
    return map[char] or string.format("\\u%04x", string.byte(char))
  end))
end

local function url_escape(text)
  return (string.gsub(text, "[^%w%-%.%_%~]", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

-- 保留未知占位符，便于用户发现拼写错误而不是静默变成空串。
local function substitute(template, values, escape)
  return (string.gsub(template, "{([%w_]+)}", function(key)
    local value = values[key]
    if value == nil then
      return "{" .. key .. "}"
    end
    if escape then
      return escape(key, tostring(value))
    end
    return tostring(value)
  end))
end

-- 点路径：a.b.0.c；空路径表示响应本身。
local function pick_path(body, path)
  if not nonempty(path) then
    return body
  end
  local current = body
  for part in string.gmatch(path, "[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    local value = current[part]
    if value == nil then
      value = current[tonumber(part)]
    end
    if value == nil then
      return nil
    end
    current = value
  end
  return current
end

local function api_key(ctx)
  local ok, value = pcall(ctx.secret.get, "custom_api_key")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

function M.make(row)
  if type(row) ~= "table" then
    return nil
  end
  local base_id = nonempty(row.id) and row.id or ""
  local url = nonempty(row.url) and row.url or ""
  if base_id == "" or url == "" or string.sub(url, 1, 8) ~= "https://" then
    return nil
  end
  local sanitized = string.gsub(string.lower(base_id), "[^a-z0-9._-]", "")
  if sanitized == "" then
    return nil
  end

  local provider = {
    id = "custom." .. sanitized,
    custom_name = nonempty(row.name) and row.name or base_id,
    row = row,
  }

  function provider.supports()
    return true
  end

  function provider.prepare(ctx, text, from, to)
    local values = {
      text = text,
      text_q = url_escape(text),
      text_json = json_escape(text),
      from = from,
      to = to,
    }
    local headers = { accept = "application/json" }
    if nonempty(provider.row.headers) then
      local ok, parsed = pcall(ctx.json.decode, substitute(provider.row.headers, values))
      if ok and type(parsed) == "table" then
        for name, value in pairs(parsed) do
          if type(name) == "string" and type(value) == "string" then
            headers[string.lower(name)] = value
          end
        end
      end
    end
    local key = api_key(ctx)
    if key then
      for name, value in pairs(headers) do
        headers[name] = substitute(value, { key = key, text = text })
      end
    end

    if provider.row.method == "get" then
      return {
        method = "GET",
        url = substitute(provider.row.url, values),
        timeout_ms = 8000,
        headers = headers,
      }
    end
    return {
      method = "POST",
      url = substitute(provider.row.url, values),
      timeout_ms = 8000,
      headers = headers,
      body = substitute(provider.row.body or '{"text":"{text_json}"}', values),
    }
  end

  function provider.parse(ctx, response)
    if response.ok ~= true then
      return nil, { code = "A413_HTTP_FAILED", message = fail.message(ctx, response) }
    end
    if response.status ~= 200 then
      return nil, {
        code = "A413_HTTP_FAILED",
        message = ctx.t("error.http_status") .. " " .. tostring(response.status),
      }
    end
    local ok, body = pcall(ctx.json.decode, response.body)
    if not ok then
      return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
    end
    local value = pick_path(body, provider.row.result_path)
    if type(value) ~= "string" or value == "" then
      return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
    end
    return value
  end

  return provider
end

return M
