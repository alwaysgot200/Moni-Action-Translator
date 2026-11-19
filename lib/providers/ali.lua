-- 阿里翻译（网页版接口）。
-- 2026-11-18 M0 实测：先 GET /api/translate/csrftoken 拿 token，再在 POST 时
-- 同时带 header 与表单字段；仅访问首页播 Cookie 会 302 到 err.taobao.com。

local fail = require("lib.providers.fail")

local M = {
  id = "ali",
  name_key = "provider.ali",
  origin = "https://translate.alibaba.com",
  endpoint = "https://translate.alibaba.com/api/translate/text",
  csrf_endpoint = "https://translate.alibaba.com/api/translate/csrftoken",
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

local function message(ctx, key, fallback)
  return ctx.t(key) or fallback
end

function M.supports(from, to)
  return languages[from] ~= nil and languages[to] ~= nil
end

function M.prepare(ctx, text, from, to)
  if not M.supports(from, to) then
    return nil, { code = "A412_LANG_UNSUPPORTED", message = ctx.t("error.lang_unsupported") }
  end

  -- 网页接口要求 Cookie + CSRF：同一 cookie jar 内先取 token，再带 header 与表单字段提交。
  local ok, response = pcall(ctx.http.request, {
    method = "GET",
    url = M.csrf_endpoint,
    cookie_jar = "run",
    timeout_ms = 8000,
    headers = {
      accept = "application/json, text/plain, */*",
      referer = M.origin .. "/",
    },
  })
  if not ok then
    return nil, { code = "A413_HTTP_FAILED", message = ctx.t("error.http_failed") }
  end
  if response.status ~= 200 then
    return nil, { code = "A413_HTTP_FAILED", message = fail.message(ctx, response) }
  end
  local decoded_ok, body = pcall(ctx.json.decode, response.body)
  if not decoded_ok or type(body) ~= "table" or type(body.token) ~= "string" then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end

  local header_name = type(body.headerName) == "string" and body.headerName or "X-XSRF-TOKEN_PROPERTY_ITEM"
  local parameter_name = type(body.parameterName) == "string" and body.parameterName or "_csrf"

  return {
    method = "POST",
    url = M.endpoint,
    cookie_jar = "run",
    timeout_ms = 8000,
    headers = {
      ["content-type"] = "application/x-www-form-urlencoded",
      origin = M.origin,
      referer = M.origin .. "/",
      [header_name] = body.token,
    },
    form = {
      query = text,
      srcLang = languages[from],
      tgtLang = languages[to],
      domain = "general",
      [parameter_name] = body.token,
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
      message = message(ctx, "error.http_status", "HTTP " .. tostring(response.status)) .. " " .. tostring(response.status),
    }
  end

  local ok, body = pcall(ctx.json.decode, response.body)
  if not ok or type(body) ~= "table" then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end

  local value = body.translateText
  if value == nil and type(body.data) == "table" then
    value = body.data.translateText
    if value == nil and type(body.data.translations) == "table" then
      local first = body.data.translations[1]
      value = type(first) == "table" and first.translation or first
    end
  end
  if type(value) ~= "string" or value == "" then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end
  return value
end

return M
