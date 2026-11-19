-- 翻译历史：落 ctx.store（按动作隔离），受条数与字节双预算约束。
-- 只保存预览与最近一次成功的译文，原文/译文都不会进入日志。
local text_util = require("lib.text")

local M = {}

local KEY = "history.v1"
local PREVIEW_CHARS = 160
local BODY_CHARS = 600
-- 单值上限 64KB；留出 JSON 结构余量（中文字符按 3 字节计）。
local BYTE_BUDGET = 56 * 1024

local function load(ctx)
  local raw = ctx.store.get(KEY)
  if type(raw) ~= "string" or raw == "" then
    return {}
  end
  local ok, value = pcall(ctx.json.decode, raw)
  if not ok or type(value) ~= "table" then
    return {}
  end
  local entries = {}
  for _, item in ipairs(value) do
    if type(item) == "table" and type(item.s) == "string" and type(item.r) == "table" then
      entries[#entries + 1] = item
    end
  end
  return entries
end

local function encode(ctx, entries)
  local ok, raw = pcall(ctx.json.encode, entries)
  if not ok or type(raw) ~= "string" then
    return nil
  end
  return raw
end

local function save(ctx, entries)
  -- 预算按 UTF-8 字节裁剪最旧记录，直到能塞进 store 限额。
  while #entries > 0 do
    local raw = encode(ctx, entries)
    if raw and #raw <= BYTE_BUDGET then
      pcall(ctx.store.set, KEY, raw)
      return
    end
    entries[#entries] = nil
  end
  pcall(ctx.store.remove, KEY)
end

--- 生成一条历史记录；`results` 为 { { id, body }, ... }。
function M.entry(text, from, to, results, now_ms)
  local cleaned = {}
  for _, item in ipairs(results or {}) do
    if type(item.id) == "string" and type(item.body) == "string" and item.body ~= "" then
      cleaned[#cleaned + 1] = {
        id = item.id,
        body = text_util.truncate(item.body, BODY_CHARS),
      }
    end
  end
  if #cleaned == 0 then
    return nil
  end
  return {
    t = now_ms or 0,
    f = from,
    to = to,
    s = text_util.truncate(text, PREVIEW_CHARS),
    r = cleaned,
  }
end

function M.push(ctx, entry, limit)
  if not entry or type(limit) ~= "number" or limit <= 0 then
    return
  end
  local entries = load(ctx)
  table.insert(entries, 1, entry)
  while #entries > limit do
    entries[#entries] = nil
  end
  save(ctx, entries)
end

--- 最新的 `limit` 条（最多 8 张卡片，与 PanelModel 上限一致）。
function M.entries(ctx, limit)
  local entries = load(ctx)
  local count = math.min(#entries, tonumber(limit) or 0, 8)
  local result = {}
  for index = 1, count do
    result[index] = entries[index]
  end
  return result
end

function M.clear(ctx)
  pcall(ctx.store.remove, KEY)
end

--- 相对时间标签（"刚刚 / 12 分钟前 / 3 小时前 / 2 天前"）。
function M.time_label(ctx, timestamp, now_ms)
  local delta = math.max(0, (now_ms or 0) - (timestamp or 0))
  local seconds = math.floor(delta / 1000)
  if seconds < 60 then
    return ctx.t("history.just_now")
  end
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then
    return ctx.t("history.minutes", tostring(minutes))
  end
  local hours = math.floor(minutes / 60)
  if hours < 24 then
    return ctx.t("history.hours", tostring(hours))
  end
  return ctx.t("history.days", tostring(math.floor(hours / 24)))
end

return M
