-- 面板模型组装（moni-action-v1 panel），字段与 core PanelModel 对齐。
local lang_util = require("lib.lang")
local history_util = require("lib.history")
local registry = require("lib.providers.registry")
local dict_registry = require("lib.providers.dict_registry")

local M = {}

local DEFAULT_BUTTONS = { "copy_all", "pin", "screenshot", "close" }

local function toolbar(ctx)
  local buttons = ctx.options and ctx.options.visible_buttons
  if type(buttons) ~= "table" or #buttons == 0 then
    return DEFAULT_BUTTONS
  end
  return buttons
end

-- 设置里的颜色控件允许 #RRGGBB / #RRGGBBAA；面板外观只接受 #RRGGBB。
-- "#00000000" 作为"跟随主题"哨兵（core 的颜色选项不允空串）。
local function sanitize_color(value)
  if type(value) ~= "string" then
    return nil
  end
  if string.upper(value) == "#00000000" then
    return nil
  end
  local hex = string.match(value, "^#(%x%x%x%x%x%x)")
  if not hex then
    return nil
  end
  return "#" .. string.upper(hex)
end

function M.appearance(ctx)
  local options = ctx.options or {}
  local appearance = {}
  local size = tonumber(options.font_size)
  if size and size >= 10 and size <= 28 then
    appearance.font_size = math.floor(size)
  end
  if options.font_family == "mono" then
    appearance.font_family = "monospace"
  end
  local background = sanitize_color(options.panel_bg)
  if background then
    appearance.background = background
  end
  local text_color = sanitize_color(options.text_color)
  if text_color then
    appearance.text_color = text_color
  end
  if next(appearance) == nil then
    return nil
  end
  return appearance
end

local function base_model(ctx, args)
  local options = ctx.options or {}
  local model = {
    version = 1,
    title = ctx.t("panel.title"),
    -- 560 太宽（实测约占半屏）；336 ≈ 原宽度的 0.6，正文仍可读。
    width = 336,
    -- 默认记住上次位置：首次居中，之后固定在用户拖动到的位置（pointer 只在
    -- 首次出现时按指针定位，不会跟随鼠标）。
    position = options.panel_position or "last",
    max_height_ratio = options.panel_max_height or 0.85,
    always_on_top = true,
    close_on_blur = options.close_on_blur == true,
    theme = options.theme or "follow",
    toolbar = toolbar(ctx),
    appearance = args.appearance or M.appearance(ctx),
    status = args.status or { done = 0, total = #args.cards },
    cards = args.cards,
  }
  if args.panel then
    model.panel = args.panel
  end
  if args.key then
    model.key = args.key
  end
  return model
end

function M.model(ctx, args)
  local model = base_model(ctx, args)
  model.subtitle =
    ctx.t("panel.subtitle", lang_util.label(ctx, args.from), lang_util.label(ctx, args.to))
  model.source = { text = args.text, lang = args.from }
  model.languages = {
    source = args.from,
    target = args.to,
    options = lang_util.choices,
  }
  return model
end

local function provider_name(ctx, id)
  local provider = registry[id] or dict_registry[id]
  if provider then
    return ctx.t(provider.name_key)
  end
  return id
end

function M.history_model(ctx, entries, panel, key)
  local now = ctx.time.now_ms()
  local cards = {}
  for index, entry in ipairs(entries) do
    local parts = {}
    for _, result in ipairs(entry.r or {}) do
      parts[#parts + 1] = provider_name(ctx, result.id) .. "：" .. result.body
    end
    cards[#cards + 1] = {
      id = "h" .. index,
      title = ctx.t(
        "history.card_title",
        history_util.time_label(ctx, entry.t, now),
        lang_util.label(ctx, entry.f) .. " → " .. lang_util.label(ctx, entry.to)
      ),
      body = table.concat(parts, "\n\n"),
      meta = entry.s,
      state = "ok",
      actions = { "copy" },
    }
  end

  if #cards == 0 then
    cards[1] = {
      id = "empty",
      title = ctx.t("history.empty_title"),
      body = ctx.t("history.empty"),
      state = "ok",
    }
  end

  local model = base_model(ctx, {
    cards = cards,
    status = { done = #entries, total = #entries },
    panel = panel,
    key = key,
  })
  model.subtitle = ctx.t("history.subtitle", tostring(#entries))
  return model
end

return M
