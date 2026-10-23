# 贡献指南

## 基本约束（必须遵守）

1. **只用 Lua**：`skills/yeelight-smart-home/scripts/` 下所有逻辑使用 Lua 5.4，兼容 ESP-Claw 运行时（标准库 + `json`/`capability`/`storage`/`delay`/`system` 模块）。
2. **不用 MCP**：禁止引入 `cap_mcp_client` / `cap_mcp_server` / JSON-RPC / SSE。
3. **只用 HTTP**：云端访问统一走 `scripts/http.lua` 封装的 `cap_http_request`；域名 allowlist 仅 Yeelight。
4. **不复用 Host Runtime**：不 import、不调用、不复制 `yeelight-home`（Go）或 Host 版 skill（Node）代码；仅可参考其接口语义。
5. **入口体积**：`invoke.lua` 及每个脚本 ≤64KB；`lua_run_script` 输出 ≤4KB。
6. **token 安全**：token 只能在 `auth.lua`/`http.lua` 内部流转，禁止出现在 `print`、响应、错误信息、文档示例中。

## 提交流程

1. Fork / 分支开发（`feat/xxx`）。
2. 本地跑通：`lua tests/run.lua`，新增逻辑需补测试。
3. 若改动 intent 集合：更新 `scripts/router.lua` 并执行 `lua tools/gen_intent_map.lua` 同步 `assets/intent-map.json`。
4. PR 描述需说明：影响 intent、风险等级（R0–R3）、是否新增云端端点。

## 代码风格

- 4 空格缩进；模块返回局部表 `M`；`local` 优先。
- 面向 LLM 的文案走 `i18n.lua`，不硬编码中文/英文字符串。
- 云端端点集中在 `api/*.lua`，禁止散落在语义层。
