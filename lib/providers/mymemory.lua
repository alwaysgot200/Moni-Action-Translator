-- MyMemory 公共翻译接口（无需 app_key；匿名额度有限，超限只影响该卡片）。
local fail = require("lib.providers.fail")
local text_util = require("lib.text")

local M = {
  id = "mymemory",
  name_key = "provider.mymemory",
  endpoint = "https://api.mymemory.translated.net/get",
}

-- 与主流程语言代码一致；MyMemory 不接受 auto，主流程已把 auto 归一为具体语言。
local languages = {
  en = "en",
  ["zh-CN"] = "zh-CN",
  ja = "ja",
  ko = "ko",
  fr = "fr",
  de = "de",
  es = "es",
  pt = "pt",
  it = "it",
  ru = "ru",
  ar = "ar",
  nl = "nl",
  sv = "sv",
  fi = "fi",
  no = "no",
  da = "da",
  pl = "pl",
  tr = "tr",
}

-- GET 接口，URL 过长会被网关拒绝；按 UTF-8 字节限制输入。
local MAX_TEXT_BYTES = 1200

function M.supports(from, to)
  return languages[from] ~= nil and languages[to] ~= nil
end

function M.prepare(ctx, text, from, to)
  if not M.supports(from, to) then
    return nil, { code = "A412_LANG_UNSUPPORTED", message = ctx.t("error.lang_unsupported") }
  end
  if #text > MAX_TEXT_BYTES then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.text_too_long") }
  end
  local pair = text_util.urlencode(languages[from] .. "|" .. languages[to])
  return {
    method = "GET",
    url = M.endpoint .. "?q=" .. text_util.urlencode(text) .. "&langpair=" .. pair,
    timeout_ms = 8000,
    headers = { accept = "application/json" },
  }
end

local function decode_entities(text)
  local entities = {
    ["&quot;"] = '"',
    ["&#39;"] = "'",
    ["&apos;"] = "'",
    ["&amp;"] = "&",
    ["&lt;"] = "<",
    ["&gt;"] = ">",
  }
  return (string.gsub(text, "&[%w#]+;", function(entity)
    return entities[entity] or entity
  end))
end

function M.parse(ctx, response)
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
  if not ok or type(body) ~= "table" then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end
  if body.quotaFinished == true then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.quota_exhausted") }
  end

  local data = body.responseData
  local value = type(data) == "table" and data.translatedText or nil
  if type(value) ~= "string" or value == "" then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end

  -- 公共语料库偶尔返回 "MYMEMORY WARNING: ..." 文本，按失败处理而不是展示给用户。
  if string.find(value, "MYMEMORY WARNING", 1, true) then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.quota_exhausted") }
  end

  return decode_entities(value)
end

return M
