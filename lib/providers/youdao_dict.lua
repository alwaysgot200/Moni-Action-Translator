-- 有道词典（网页 JSON 接口，无需 app_key）。
-- 英文词取 ec.word（音标 + 释义）；中文词取 ce.word；兜底用 web_trans 的网页释义。
local fail = require("lib.providers.fail")
local text_util = require("lib.text")

local M = {
  id = "dict",
  name_key = "provider.youdao_dict",
  endpoint = "https://dict.youdao.com/jsonapi",
}

local MAX_LINES = 4

function M.prepare(ctx, text)
  return {
    method = "GET",
    url = M.endpoint .. "?q=" .. text_util.urlencode(text),
    timeout_ms = 6000,
    headers = {
      accept = "application/json, text/plain, */*",
      referer = "https://dict.youdao.com/",
    },
  }
end

local function push_line(lines, prefix, value)
  if #lines >= MAX_LINES or type(value) ~= "string" or value == "" then
    return
  end
  lines[#lines + 1] = (prefix and prefix .. " " or "") .. value
end

local function collect_trs(container, lines)
  local trs = container and container.trs
  if type(trs) ~= "table" then
    return
  end
  for _, group in ipairs(trs) do
    for _, tr in ipairs(group.tr or {}) do
      local l = tr.l
      if type(l) == "table" then
        local pos = type(l.pos) == "string" and l.pos or nil
        if type(l.i) == "table" then
          for _, definition in ipairs(l.i) do
            push_line(lines, pos and (pos .. ".") or nil, definition)
          end
        end
        if type(l["#tran"]) == "string" then
          push_line(lines, pos and (pos .. ".") or nil, l["#tran"])
        end
      elseif type(l) == "string" then
        push_line(lines, nil, l)
      end
    end
  end
end

local function web_definitions(body, lines)
  local web = body.web_trans
  local groups = type(web) == "table" and web["web-translation"] or nil
  if type(groups) ~= "table" then
    return
  end
  for _, group in ipairs(groups) do
    for _, item in ipairs(group.trans or {}) do
      push_line(lines, nil, item.value)
    end
  end
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

  local lines, phonetic = {}, nil
  local ec_word = type(body.ec) == "table" and body.ec.word or nil
  if type(ec_word) == "table" then
    if ec_word[1] then
      ec_word = ec_word[1]
    end
    phonetic = ec_word.usphone or ec_word.ukphone
    collect_trs(ec_word, lines)
  end

  local ce_word = type(body.ce) == "table" and body.ce.word or nil
  if #lines == 0 and type(ce_word) == "table" then
    local first = ce_word[1] or ce_word
    phonetic = phonetic or first.phone
    collect_trs(first, lines)
  end

  if #lines == 0 then
    web_definitions(body, lines)
  end
  if #lines == 0 then
    return nil, { code = "A414_PROVIDER_FAILED", message = ctx.t("error.provider_failed") }
  end

  return {
    body = table.concat(lines, "\n"),
    meta = phonetic,
  }
end

return M
