-- 火山翻译（浏览器扩展接口）。
-- 注意：路径与字段来自扩展端抓包，M0 技术验证阶段需以真实响应与 fixtures 复核。

local fail = require("lib.providers.fail")

local M = {
  id = "huoshan",
  name_key = "provider.huoshan",
  endpoint = "https://translate.volcengine.com/crx/translate/v1/",
}

local languages = {
  auto = "auto",
  en = "en",
  ["zh-CN"] = "zh",
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

function M.supports(from, to)
  return languages[from] ~= nil and languages[to] ~= nil
end

function M.prepare(ctx, text, from, to)
  if not M.supports(from, to) then
    return nil, { code = "A412_LANG_UNSUPPORTED", message = ctx.t("error.lang_unsupported") }
  end
  return {
    method = "POST",
    url = M.endpoint,
    timeout_ms = 8000,
    headers = {
      ["content-type"] = "application/json",
      origin = "https://translate.volcengine.com",
      referer = "https://translate.volcengine.com/",
    },
    json = {
      text = text,
      source_language = languages[from],
      target_language = languages[to],
    },
  }
end

function M.parse(ctx, response)
  if response.ok ~= true then
    return nil, {
      code = "A413_HTTP_FAILED",
      message = fail.message(ctx, response),
    }
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
  local value = body.translation
  if value == nil and type(body.data) == "table" then
    value = body.data.translation
  end
  if type(value) ~= "string" or value == "" then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end
  return value
end

return M
