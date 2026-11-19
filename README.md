# Moni-Action-Translator

Moni 的翻译动作包（`moni-action-v1` / Lua 5.4）：框选截图或读剪贴板取词，同时调用
阿里、火山、MyMemory 三个内置翻译引擎，并可按设置追加任意 HTTPS 自定义接口；
支持中/英/日/韩/法/德/意/西/葡/俄/阿/荷/瑞典/芬兰/挪威/丹麦/波兰/土耳其等语言的
互译；结果并列展示在通用面板里，支持复制、重译、单引擎重试、历史记录、查词、
面板外观自定义与多面板并存；可在设置页绑定全局热键，密钥保存在系统钥匙串。

## 目录

```text
action.json              # 清单：权限、net.allow、设置页与选项 schema
main.lua                 # 编排：取词 → 语言解析 → 并发请求 → 面板
lib/
  text.lua               # OCR blocks 聚行、中英混排空格、文本清洗、URL 编码/截断
  lang.lua               # 语言规范化、auto 检测、同语言中英互换
  dict.lua               # 查词启发式（英文单词 ≤32 / 汉字 ≤4）
  history.lua            # 历史记录（ctx.store、条数 + 字节双预算、相对时间）
  panel.lua              # PanelModel 组装（含外观 token 与历史面板）
  providers/
    registry.lua         # 翻译引擎 id → provider
    dict_registry.lua    # 词典 provider 注册表
    fail.lua             # 传输层错误码 → 本地化卡片文案
    ali.lua              # 阿里翻译（CSRF token + 表单接口）
    huoshan.lua          # 火山翻译（扩展接口）
    mymemory.lua         # MyMemory 公共接口（GET，无 app_key）
    custom.lua           # 用户自定义 HTTPS 接口（records 配置 → provider）
    youdao_dict.lua      # 有道词典（网页 JSON，音标 + 释义）
locales/                 # zh-CN / en，键与 action.json 的 *_key 对应
tests/fixtures.json      # devtools 离线冲烟：词典 + 三引擎成功（不打包）
tests/fixtures-partial.json  # 单引擎失败降级（不打包）
tests/fixtures-history.json  # 历史面板 + 外观 token（不打包）
tests/fixtures-p3.json   # 自定义接口 + 钥匙串密钥 + 多面板 key（不打包）
tools/pack.py            # 打 zip（不打包）
```

## 本地验证

动作包本身不是 Rust workspace 成员，用宿主仓库的 devtools 校验与离线运行：

```bash
cd ../RustMoni

# 静态校验：清单、entry、语言包
cargo run -p moni-actions-devtools -- check ../Moni-Action-Translator

# 离线运行：fixtures 重放剪贴板 + 词典/四引擎请求
cargo run -p moni-actions-devtools -- run ../Moni-Action-Translator

# P2：历史面板 + 外观（字号/等宽字体/背景色/文字颜色）
cargo run -p moni-actions-devtools -- run ../Moni-Action-Translator \
  --fixtures ../Moni-Action-Translator/tests/fixtures-history.json

# P3：自定义接口（密钥经 {key} 注入 headers）+ 域名白名单 + 多面板
cargo run -p moni-actions-devtools -- run ../Moni-Action-Translator \
  --fixtures ../Moni-Action-Translator/tests/fixtures-p3.json
```

`run` 的 stdout 为 JSON envelope；`expect` 先打印后校验，失败时仍能看到 `panels`
（结果卡片）、`store`、`http_requests` 等记录。当前 fixtures 断言四张卡片均为
`ok` 且 `status = { done = 4, total = 4 }`（词典 + 三引擎）。

## 状态

- 编排、面板、错误降级、devtools fixtures 已就绪；fixtures 以剪贴板 `hello` 离线跑通
  词典 + 阿里 / 火山 / MyMemory 四张结果卡片；
- 2026-11-19 0.4.0：
  - **移除彩云小译**：匿名设备注册链路长期不稳定（初始化失败），保留反而制造噪音；
  - **多语言**：源/目标扩展到中、英、日、韩、法、德、意、西、葡、俄、阿、荷、
    瑞典、芬兰、挪威、丹麦、波兰、土耳其；auto 检测新增假名/谚文/西里尔/阿拉伯；
  - **面板**：宽度 560 → 336（约 0.6×），默认 `position=last`（首次居中、之后固定
    在用户拖到的位置，不再跟随鼠标）；
- 2026-11-18 M7（P2）完成：
  - **历史记录**：`op=history` 打开历史面板，`history_limit`（默认 20，0 = 关闭）同时受
    `ctx.store` 64KB 字节预算约束，超限自动丢弃最旧记录；只保存原文预览（160 字）与
    各引擎译文（600 字），不写日志；
  - **查词**：`dict_mode=auto` 且输入为英文单词（≤32 字符）或 1–4 个汉字时，额外显示
    有道词典卡片（音标 + 释义），重试该卡片只请求词典；
  - **更多引擎**：新增 MyMemory（`api.mymemory.translated.net`，GET，无 app_key；
    免费公共接口，匿名额度有限，偶尔 503 属正常）；
  - **外观**：`font_size` / `font_family` / `panel_bg` / `text_color` 通过
    `PanelModel.appearance` 生效，`#00000000` 表示跟随主题；
  - **动作热键**：宿主设置 → 快捷键新增"动作热键"，可直接给本动作绑定全局组合键。
- 2026-11-18 M0 真实网络验证结论：
  - **火山**：✅ 匿名 `POST /crx/translate/v1/` 返回 `translation` / `detected_language`，
    与 `huoshan.lua` 的解析一致；
  - **阿里**：✅ 先 `GET /api/translate/csrftoken` 取 `{token, parameterName, headerName}`，
    POST 时同时写 header 与表单字段；仅访问首页种 Cookie 会 302 到 `err.taobao.com`。
- 2026-11-18 P3（M8）完成：
  - **自定义接口**：设置 → 服务 → 自定义接口（records），每行一个 HTTPS 地址；`url`
    支持 `{text}` / `{text_q}` / `{from}` / `{to}`，`body` 用 `{text_json}`，`result_path`
    按点路径取译文；`net.allow_option` 让宿主只放行用户实际配置的公网域名；
  - **密钥**：`custom_api_key` 为 `secret` 选项，保存在系统钥匙串，headers 里用 `{key}` 引用；
  - **多面板**：`multi_panel=true` 时不同文本各自保留面板（key = 文本 SHA-1 前 8 位），
    相同文本再次翻译原地更新；
  - **canvas**：宿主已提供通用画布控件；本动作暂未使用（当前结果仍是标准卡片）。
- 未实现：面板内源文编辑、术语表、AI 流式输出。

## 权限

`screen.capture`、`ocr.run`、`clipboard.read`、`clipboard.write`、`ui.form`、`ui.panel`、
`store`、`secret`、`net.fetch`、`notify`；内置网络仅允许 `net.allow` 中的四个域名
（`translate.alibaba.com`、`translate.volcengine.com`、`dict.youdao.com`、
`api.mymemory.translated.net`），另外只放行用户在"自定义接口"里填写的
公网 HTTPS 域名；拒绝明文 HTTP。

## 打包

```bash
python tools/pack.py
# 输出：../util.translator-0.4.0.zip
```

与 `Moni-Action-ImageText` 一致：压缩包根目录直接是 `action.json` 与 `main.lua`，
不含 `tests/`、`tools/`、`.git/`、`*.zip`、`*.sig`。

签名流程见宿主仓库 `docs/ACTION_DEVELOPER_GUIDE.md` §7.3：`zip` 原始字节的
Ed25519 签名写 base64 到同名 `.zip.sig`；私钥不随仓库分发，发布时由持有者签名。
