-- util.translator —— 截图/剪贴板/输入取词，并发调用多个翻译引擎，结果写入面板。
-- 网络与各引擎字段差异全部封装在 lib/providers/*.lua；本文件只负责编排与降级。

local text_util = require("lib.text")
local lang_util = require("lib.lang")
local panel_util = require("lib.panel")
local history_util = require("lib.history")
local dict_util = require("lib.dict")
local registry = require("lib.providers.registry")
local dict_registry = require("lib.providers.dict_registry")
local custom_util = require("lib.providers.custom")

local MAX_CHARS = 5000
local DEFAULT_PROVIDERS = { "ali", "huoshan", "mymemory" }

local function opt(ctx, key, default)
  local value = ctx.options and ctx.options[key]
  if value == nil then
    return default
  end
  return value
end

-- 用户自定义接口（设置 → 服务里的对象列表），每次运行按当前配置重建。
local function custom_providers(ctx)
  local out = {}
  local rows = opt(ctx, "custom_providers", {})
  if type(rows) ~= "table" then
    return out
  end
  for _, row in ipairs(rows) do
    local provider = custom_util.make(row)
    if provider then
      out[provider.id] = provider
    end
  end
  return out
end

local function provider_of(ctx, id)
  return registry[id] or dict_registry[id] or custom_providers(ctx)[id]
end

-- 查词模式：auto 且输入是单词时追加词典卡片（与翻译结果并列，不替代引擎）。
-- 有道词典只支持中英，其它语言对不送词典。
local function dict_provider_id(ctx, text, from, to)
  if opt(ctx, "dict_mode", "auto") ~= "auto" or not dict_util.is_lookup(text) then
    return nil
  end
  local pair = (from == "en" and to == "zh-CN") or (from == "zh-CN" and to == "en")
  if not pair then
    return nil
  end
  local ids = opt(ctx, "dict_providers", { "youdao" })
  if type(ids) ~= "table" then
    return nil
  end
  local id = ids[1]
  if id and dict_registry[id] then
    return id
  end
  return nil
end

local function fail(ctx, code, key)
  return { ok = false, code = code, message = ctx.t(key) }
end

local function pick_text(ctx)
  local mode = opt(ctx, "run_mode", "screenshot")
  if mode == "clipboard" then
    local text = ctx.clipboard.read("text")
    if type(text) ~= "string" or text == "" then
      return nil, "A101_NO_TEXT"
    end
    return text
  end

  if mode == "input" then
    local ok, values = pcall(ctx.ui.form, {
      title = ctx.t("form.title"),
      fields = {
        text = { type = "string", default = "", label_key = "form.text" },
      },
    })
    if not ok then
      return nil, "A502_CANCELLED"
    end
    if type(values.text) ~= "string" or values.text == "" then
      return nil, "A101_NO_TEXT"
    end
    return values.text
  end

  local ok, grab = pcall(ctx.capture.pick_region, { hint = ctx.t("hint.pick_region") })
  if not ok then
    return nil, "A502_CANCELLED"
  end
  local ocr = ctx.ocr.recognize(grab.asset, { return_boxes = true })
  local merged = text_util.from_blocks(ocr.blocks, opt(ctx, "merge_paragraphs", true))
  if merged == "" then
    return nil, "A101_NO_TEXT"
  end
  return merged
end

local function provider_ids(ctx, params)
  if params.op == "retry" and type(params.provider) == "string" then
    return { params.provider }
  end
  local ids = opt(ctx, "providers", DEFAULT_PROVIDERS)
  if type(ids) ~= "table" or #ids == 0 then
    ids = DEFAULT_PROVIDERS
  end
  -- 自定义接口总是追加在已选引擎之后（它们本身就是用户显式配置的）。
  local merged = {}
  for _, id in ipairs(ids) do
    merged[#merged + 1] = id
  end
  local custom = custom_providers(ctx)
  local custom_ids = {}
  for id in pairs(custom) do
    custom_ids[#custom_ids + 1] = id
  end
  table.sort(custom_ids)
  for _, id in ipairs(custom_ids) do
    merged[#merged + 1] = id
  end
  return merged
end

local function provider_label(ctx, provider)
  if type(provider.custom_name) == "string" then
    return provider.custom_name
  end
  return ctx.t(provider.name_key)
end

local function card_title(ctx, provider, text)
  local name = provider_label(ctx, provider)
  if provider.id == "dict" then
    return name .. " · " .. text
  end
  return name
end

local function loading_cards(ctx, ids, dict_id, text)
  local cards = {}
  if dict_id and dict_registry[dict_id] then
    local provider = dict_registry[dict_id]
    cards[#cards + 1] = {
      id = dict_id,
      title = card_title(ctx, provider, text),
      state = "loading",
    }
  end
  for _, id in ipairs(ids) do
    local provider = provider_of(ctx, id)
    if provider then
      cards[#cards + 1] = { id = id, title = card_title(ctx, provider, text), state = "loading" }
    end
  end
  return cards
end

local function collect(ctx, ids, text, from, to, dict_id)
  local requests, cards = {}, {}
  if dict_id and dict_registry[dict_id] then
    local provider = dict_registry[dict_id]
    local req, err = provider.prepare(ctx, text, from, to)
    if req then
      req.id = dict_id
      requests[#requests + 1] = req
      cards[#cards + 1] = {
        id = dict_id,
        title = card_title(ctx, provider, text),
        state = "loading",
      }
    elseif err then
      cards[#cards + 1] = {
        id = dict_id,
        title = card_title(ctx, provider, text),
        state = "error",
        error = err.message or ctx.t("error.provider_failed"),
        actions = { "retry" },
      }
    end
  end
  for _, id in ipairs(ids) do
    local provider = provider_of(ctx, id)
    if provider then
      local req, err = provider.prepare(ctx, text, from, to)
      if req then
        req.id = id
        requests[#requests + 1] = req
        cards[#cards + 1] = { id = id, title = card_title(ctx, provider, text), state = "loading" }
      else
        cards[#cards + 1] = {
          id = id,
          title = card_title(ctx, provider, text),
          state = "error",
          error = err and err.message or ctx.t("error.provider_failed"),
          actions = { "retry" },
        }
      end
    end
  end
  return requests, cards
end

local function translate(ctx, ids, text, from, to, dict_id)
  local requests, cards = collect(ctx, ids, text, from, to, dict_id)
  if #requests == 0 then
    return cards
  end

  local ok, results = pcall(ctx.http.batch, requests, { concurrency = 4 })
  if not ok or type(results) ~= "table" then
    for _, card in ipairs(cards) do
      if card.state == "loading" then
        card.state = "error"
        card.error = ctx.t("error.http_failed")
        card.actions = { "retry" }
      end
    end
    return cards
  end

  local by_id = {}
  for _, result in ipairs(results) do
    by_id[result.id] = result
  end
  for _, card in ipairs(cards) do
    local result = by_id[card.id]
    if card.state == "loading" then
      local provider = provider_of(ctx, card.id)
      if not result or not provider then
        card.state = "error"
        card.error = ctx.t("error.http_failed")
        card.actions = { "retry" }
      else
        local translated, err = provider.parse(ctx, result)
        if translated then
          card.state = "ok"
          if type(translated) == "table" then
            card.body = translated.body
            card.meta = translated.meta
          else
            card.body = translated
          end
          card.actions = { "copy", "retry" }
        else
          card.state = "error"
          card.error = err and err.message or ctx.t("error.provider_failed")
          card.actions = { "retry" }
        end
      end
    end
  end
  return cards
end

local function update_panel(ctx, handle, model)
  if not handle then
    return false
  end
  -- 用户已关闭面板（A411）属于正常终止，不升级为动作失败。
  local ok = pcall(ctx.ui.panel.update, handle, model)
  return ok
end

-- 多面板：同一段文本落到同一个实例；关闭面板不会影响其它结果。
local function panel_key_for(ctx, text)
  if opt(ctx, "multi_panel", false) ~= true then
    return nil
  end
  local ok, digest = pcall(ctx.crypto.hash, "sha1", text)
  if ok and type(digest) == "string" and #digest >= 8 then
    return "t-" .. string.lower(string.sub(digest, 1, 8))
  end
  return "t-" .. tostring(ctx.time.now_ms())
end

function run(ctx)
  local params = ctx.params or {}
  local op = params.op
  local text

  if op == "history" then
    local limit = tonumber(opt(ctx, "history_limit", 20)) or 0
    local handle = params.panel
    local key = params.key
    if not handle and opt(ctx, "multi_panel", false) == true then
      key = key or "history"
    end
    local model = panel_util.history_model(ctx, history_util.entries(ctx, limit), handle, key)
    if handle then
      update_panel(ctx, handle, model)
    else
      local ok, value = pcall(ctx.ui.panel.open, model)
      if ok and type(value) == "string" then
        handle = value
      end
    end
    return { ok = true, keep_open = handle ~= nil, panel = handle }
  end

  if op == "retranslate" or op == "retry" then
    text = params.text
  elseif op == "append" then
    local more, err = pick_text(ctx)
    if not more then
      return fail(ctx, err, err == "A502_CANCELLED" and "error.cancelled" or "error.no_text")
    end
    text = text_util.join(params.text or "", more)
  else
    local picked, err = pick_text(ctx)
    if not picked then
      return fail(ctx, err, err == "A502_CANCELLED" and "error.cancelled" or "error.no_text")
    end
    text = picked
  end

  text = text_util.normalize(text, MAX_CHARS)
  if text == "" then
    return fail(ctx, "A101_NO_TEXT", "error.no_text")
  end

  local from, to, lang_err = lang_util.resolve(
    params.from or opt(ctx, "source_lang", "auto"),
    params.to or opt(ctx, "target_lang", "zh-CN"),
    text
  )
  if not from then
    return fail(ctx, lang_err or "A412_LANG_UNSUPPORTED", "error.lang_unsupported")
  end

  local ids, dict_id
  if op == "retry" and type(params.provider) == "string" then
    -- 重试词典卡片时只跑词典，避免把单词再发给全部翻译引擎。
    if dict_registry[params.provider] then
      ids = {}
      dict_id = params.provider
    else
      ids = { params.provider }
    end
  else
    ids = provider_ids(ctx, params)
    dict_id = dict_provider_id(ctx, text, from, to)
  end

  local handle = params.panel
  local key = params.key
  if not handle and key == nil then
    key = panel_key_for(ctx, text)
  end
  local model = panel_util.model(ctx, {
    text = text,
    from = from,
    to = to,
    key = key,
    cards = loading_cards(ctx, ids, dict_id, text),
  })
  if handle then
    update_panel(ctx, handle, model)
  else
    local ok, value = pcall(ctx.ui.panel.open, model)
    if ok and type(value) == "string" then
      handle = value
    else
      handle = nil
    end
  end

  local cards = translate(ctx, ids, text, from, to, dict_id)
  local done, ok_count = 0, 0
  local results = {}
  for _, card in ipairs(cards) do
    if card.state ~= "loading" then
      done = done + 1
    end
    if card.state == "ok" then
      ok_count = ok_count + 1
      results[#results + 1] = { id = card.id, body = card.body }
    end
  end
  model = panel_util.model(ctx, {
    text = text,
    from = from,
    to = to,
    key = key,
    cards = cards,
    status = { done = done, total = #cards },
    panel = handle,
  })
  update_panel(ctx, handle, model)

  local entry = history_util.entry(text, from, to, results, ctx.time.now_ms())
  history_util.push(ctx, entry, tonumber(opt(ctx, "history_limit", 20)) or 0)

  if ok_count == 0 then
    -- 全部引擎失败：保留错误卡片供查看/重试，但整体按失败上报（§5.9）。
    return {
      ok = false,
      code = "A414_PROVIDER_FAILED",
      message = ctx.t("error.provider_failed"),
      panel = handle,
      keep_open = handle ~= nil,
    }
  end

  return {
    ok = true,
    keep_open = handle ~= nil,
    text = text,
    from = from,
    to = to,
    panel = handle,
  }
end
