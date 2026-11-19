-- OCR blocks → 文本：按 y 聚行、行内按 x 排序，中英混排按字符脚本决定是否补空格。
local M = {}

local function box_of(block)
  local box = block.box or {}
  local x = box.x or 0
  local y = box.y or 0
  local h = box.h or 0
  return x, y, h
end

local function ends_with_cjk(text)
  local last = #text
  while last > 0 do
    local byte = string.byte(text, last)
    if byte >= 0x80 then
      while last > 1 and string.byte(text, last) >= 0x80 and string.byte(text, last) < 0xC0 do
        last = last - 1
      end
      local lead = string.byte(text, last)
      return lead >= 0xE4 and lead <= 0xE9
    end
    if byte ~= 32 then
      return false
    end
    last = last - 1
  end
  return false
end

local function starts_with_cjk(text)
  for index = 1, #text do
    local byte = string.byte(text, index)
    if byte >= 0xE4 and byte <= 0xE9 then
      return true
    end
    if byte ~= 32 then
      return false
    end
  end
  return false
end

local function join_piece(left, right)
  if left == "" then
    return right
  end
  if right == "" then
    return left
  end
  if ends_with_cjk(left) or starts_with_cjk(right) then
    return left .. right
  end
  return left .. " " .. right
end

local function sort_blocks(blocks)
  local items = {}
  for _, block in ipairs(blocks) do
    local text = block.text
    if type(text) == "string" and text ~= "" then
      local x, y, h = box_of(block)
      items[#items + 1] = { text = text, x = x, y = y, h = h }
    end
  end
  table.sort(items, function(left, right)
    if math.abs(left.y - right.y) > 0.001 then
      return left.y < right.y
    end
    return left.x < right.x
  end)
  return items
end

local function group_lines(items)
  local lines = {}
  local current = nil
  for _, item in ipairs(items) do
    local tolerance = math.max(item.h, 0.02) * 0.6
    if current and math.abs(item.y - current.y) <= tolerance then
      current.items[#current.items + 1] = item
    else
      current = { y = item.y, items = { item } }
      lines[#lines + 1] = current
    end
  end
  return lines
end

-- merge = true：行间用空格/中文直连合并；false：每行一个换行。
function M.from_blocks(blocks, merge)
  if type(blocks) ~= "table" or #blocks == 0 then
    return ""
  end
  local lines = group_lines(sort_blocks(blocks))
  local output = ""
  for index, line in ipairs(lines) do
    table.sort(line.items, function(left, right)
      return left.x < right.x
    end)
    local text = ""
    for _, item in ipairs(line.items) do
      text = join_piece(text, item.text)
    end
    if index == 1 then
      output = text
    elseif merge then
      output = join_piece(output, text)
    else
      output = output .. "\n" .. text
    end
  end
  return output
end

function M.normalize(text, max_chars)
  if type(text) ~= "string" then
    return ""
  end
  text = string.gsub(text, "\r\n", "\n")
  text = string.gsub(text, "\r", "\n")
  text = string.gsub(text, "[ \t]+\n", "\n")
  text = string.gsub(text, "\n\n\n+", "\n\n")
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  if max_chars and #text > max_chars then
    text = string.sub(text, 1, max_chars)
  end
  return text
end

function M.join(left, right)
  left = M.normalize(left)
  right = M.normalize(right)
  if left == "" then
    return right
  end
  if right == "" then
    return left
  end
  return left .. "\n" .. right
end

-- 严格 percent-encoding（UTF-8 字节级），用于 GET 接口的查询参数。
function M.urlencode(value)
  if type(value) ~= "string" then
    return ""
  end
  return (string.gsub(value, "([^%w%-%._~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

-- 按字符（而非字节）截断，避免把多字节字符切成乱码。
function M.truncate(text, limit)
  text = text or ""
  if limit == nil or limit <= 0 then
    return text
  end
  local length = utf8.len(text)
  if not length then
    return string.sub(text, 1, limit)
  end
  if length <= limit then
    return text
  end
  local offset = utf8.offset(text, limit + 1)
  if not offset then
    return text
  end
  return string.sub(text, 1, offset - 1) .. "…"
end

return M
