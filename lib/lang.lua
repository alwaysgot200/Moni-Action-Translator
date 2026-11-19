-- 语言代码规范化与源/目标解析。
local M = {}

-- 与各引擎映射表保持同一集合；顺序即设置页与面板下拉的顺序。
M.choices = {
  "auto",
  "zh-CN",
  "en",
  "ja",
  "ko",
  "fr",
  "de",
  "es",
  "pt",
  "it",
  "ru",
  "ar",
  "nl",
  "sv",
  "fi",
  "no",
  "da",
  "pl",
  "tr",
}

local aliases = {
  auto = "auto",
  en = "en",
  zh = "zh-CN",
  ["zh-cn"] = "zh-CN",
  ["zh_cn"] = "zh-CN",
  ["zh-CN"] = "zh-CN",
  ja = "ja",
  jp = "ja",
  ko = "ko",
  kr = "ko",
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
  nb = "no",
  da = "da",
  pl = "pl",
  tr = "tr",
}

local swaps = {
  ["zh-CN"] = "en",
  en = "zh-CN",
}

function M.canonical(code)
  if type(code) ~= "string" then
    return nil
  end
  return aliases[code] or aliases[string.lower(code)]
end

-- 解码一个 UTF-8 码位（调用方保证首字节 >= 0x80）。
local function codepoint_at(text, index, length)
  local first = string.byte(text, index)
  if not first then
    return nil, index + 1
  end
  if first < 0x80 then
    return first, index + 1
  end
  local second = string.byte(text, index + 1)
  if not second then
    return nil, index + 1
  end
  if first < 0xE0 then
    return ((first - 0xC0) * 64) + (second - 0x80), index + 2
  end
  local third = string.byte(text, index + 2)
  if not third then
    return nil, index + 1
  end
  if first < 0xF0 then
    return ((first - 0xE0) * 4096) + ((second - 0x80) * 64) + (third - 0x80), index + 3
  end
  return nil, index + 4
end

-- 轻量脚本启发式：按字符块统计中日韩/西里尔/阿拉伯，auto 时给出最可能的源语言。
function M.detect(text)
  local counts = { zh = 0, ja = 0, ko = 0, ru = 0, ar = 0, latin = 0 }
  local length = #text
  local index = 1
  while index <= length do
    local byte = string.byte(text, index)
    local code, next_index
    if byte >= 0x80 then
      code, next_index = codepoint_at(text, index, length)
    else
      code, next_index = byte, index + 1
    end
    index = next_index
    if code then
      if code >= 0x3040 and code <= 0x30FF then
        counts.ja = counts.ja + 1
      elseif code >= 0xAC00 and code <= 0xD7A3 then
        counts.ko = counts.ko + 1
      elseif (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0x3400 and code <= 0x4DBF) then
        counts.zh = counts.zh + 1
      elseif (code >= 0x0400 and code <= 0x04FF) then
        counts.ru = counts.ru + 1
      elseif code >= 0x0600 and code <= 0x06FF then
        counts.ar = counts.ar + 1
      elseif (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A) then
        counts.latin = counts.latin + 1
      end
    end
  end
  if counts.ja > 0 then
    return "ja"
  end
  if counts.ko > 0 then
    return "ko"
  end
  if counts.zh > 0 then
    return "zh-CN"
  end
  if counts.ar > 0 and counts.ar >= counts.latin then
    return "ar"
  end
  if counts.ru > 0 and counts.ru >= counts.latin then
    return "ru"
  end
  return "en"
end

function M.label(ctx, code)
  local key = "lang." .. (M.canonical(code) or "auto")
  return ctx.t(key)
end

-- 源=目标时按 Quicker 习惯中英互换；其它语言回退到英语（英语则回退中文）。
-- 第三返回值保留给调用方的错误位（当前所有语言对都由引擎映射兜底，恒为 nil）。
function M.resolve(from, to, text)
  local source = M.canonical(from) or "auto"
  local target = M.canonical(to) or "zh-CN"
  if source == "auto" then
    source = M.detect(text)
  end
  if source == target then
    target = swaps[source] or (source == "en" and "zh-CN" or "en")
  end
  return source, target, nil
end

return M
