# 状态与错误

## status 七种
success / partial / clarification_required / blocked / not_supported / auth_required / error

## 处理规则
- 401/403 -> auth_required（引导 bind.account 重新绑定）。
- 无默认家庭 -> blocked（no_house）。
- 业务失败（success=false）-> error（含云端 msg）。
- 写后验证不通过 -> partial（write_unverified）。
- 名称歧义/未找到 -> clarification_required + candidates。
- 未注册 intent -> not_supported。
- 任何 Lua 错误被 invoke.lua 捕获 -> error（E_INTERNAL），不向 LLM 抛裸错误。

## 缓存
拓扑（rooms+devices）缓存 60s；写操作后立即 invalidate。强制刷新：topology.load({force=true})（内部使用）。
