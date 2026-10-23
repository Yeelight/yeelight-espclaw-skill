# yeelight-espclaw-skill

面向 [ESP-Claw](https://github.com/espressif/esp-claw)（ESP-Mosaico 设备端 AI 代理）的 Yeeline Pro 智能家庭 Skill。**完全独立**：纯 Lua 实现，仅通过 `cap_http_request` 直调 Yeelight 云端 REST，不使用任何 MCP 能力，也不依赖 Yeelight Host 版 skill / `yeelight-home` Runtime。

## 仓库结构

```
skills/yeelight-smart-home/   # ESP-Claw Skill 包（可整体提交到 esp-claw-skills-lab）
├── SKILL.md                  # frontmatter + LLM 使用规则
├── assets/                   # intent 目录 / intent 映射 / 设备词表 / schema
├── references/               # 面向 LLM 的参考文档（API 映射、风险、边界等）
└── scripts/                  # Lua 实现（入口 invoke.lua，<64KB）
tests/                        # Lua 5.4 单元测试（mock capability/storage）
tools/                        # 辅助脚本（生成 intent-map 等）
```

## 快速开始

在 ESP-Claw 设备上安装本 Skill 后，LLM 通过以下方式调用：

```
lua_run_script(path="{CUR_SKILL_DIR}/scripts/invoke.lua", args={
  contractVersion="1.0", requestId="r-1", locale="zh-CN",
  utterance="把客厅灯调到60%", intent="light.brightness.set",
  parameters={roomName="客厅", deviceName="主灯", brightness=60}
})
```

首次使用需完成账号绑定（QR 扫码）：

```
lua_run_script(path="{CUR_SKILL_DIR}/scripts/invoke.lua",
               args={contractVersion="1.0", requestId="r-2",
                     locale="zh-CN", intent="bind.account", parameters={}})
```

## 开发与测试

```bash
# 本地单元测试（Lua 5.4）
lua tests/run.lua

# 生成 assets/intent-map.json（以 router.lua 为唯一事实来源）
lua tools/gen_intent_map.lua

# Skills Lab 校验（克隆 esp-claw-skills-lab 后）
pnpm validate-packages
```

## 安全要点

- 账号 token 仅保存在设备 `storage` 专用目录，不进入 LLM 参数、日志或响应。
- HTTP allowlist 仅限 `*.yeelight.com` / `api-dev.yeedev.com`。
- R3 高危操作（删除家庭/设备/网关、成员转移等）必须二次确认（`parameters.confirmed=true`）。
- 敏感属性读写一律拦截。

## License

MIT
