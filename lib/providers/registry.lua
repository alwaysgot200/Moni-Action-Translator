-- 引擎注册表：id → provider 模块。新增引擎只需加模块并在此登记。
local M = {
  ali = require("lib.providers.ali"),
  huoshan = require("lib.providers.huoshan"),
  mymemory = require("lib.providers.mymemory"),
}

return M
