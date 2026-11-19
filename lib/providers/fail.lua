-- 传输层错误（超时/拦截/超大）由宿主返回错误码与英文技术文案；
-- 卡片展示必须走动作自己的语言包，这里按错误码映射成本地化文案。
local M = {}

local KEYS = {
  A501_TIMEOUT = "error.timeout",
  A503_TOO_LARGE = "error.too_large",
  A509_NETWORK_BLOCKED = "error.network_blocked",
}

function M.message(ctx, response)
  local code = response.error and response.error.code
  return ctx.t(KEYS[code] or "error.http_failed")
end

return M
