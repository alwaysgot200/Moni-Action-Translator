-- 查词启发式：短英文单词或 1–4 个汉字走词典 provider，避免把句子送进词典。
local M = {}

local LATIN_WORD_MAX = 32
local CJK_WORD_MAX = 4

local function is_cjk(code)
  return code >= 0x4E00 and code <= 0x9FFF
end

function M.is_lookup(text)
  if type(text) ~= "string" then
    return false
  end
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  local length = utf8.len(text)
  if not length or length == 0 then
    return false
  end

  if string.match(text, "^[%a%-'’]+$") then
    return length <= LATIN_WORD_MAX
  end

  local cjk_count = 0
  for _, code in utf8.codes(text) do
    if not is_cjk(code) then
      return false
    end
    cjk_count = cjk_count + 1
  end
  return cjk_count > 0 and cjk_count <= CJK_WORD_MAX
end

return M
