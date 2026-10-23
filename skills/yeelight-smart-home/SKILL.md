---
name: yeelight-smart-home
description: >
  Control and manage a Yeelight Pro smart home from ESP-Claw: homes, rooms,
  areas, devices, groups, scenes, automations, gateways, lighting control,
  product knowledge and diagnostics. Requires one-time Yeelight account
  binding via QR code and HTTP access to *.yeelight.com.
author: Yeelight
metadata:
  cap_groups:
    - cap_lua
    - cap_http_request
  category:
    - utility
    - network
  peripherals:
    - display
  tags:
    - yeelight
    - smart-home
    - lighting
    - scene
---

# Yeelight Smart Home (ESP-Claw)

You control a Yeelight Pro smart home by running Lua scripts through the
`lua_run_script` capability. All cloud access is HTTP-only (no MCP).

## Invocation

Run `{CUR_SKILL_DIR}/scripts/invoke.lua` with an args object:

```json
{
  "contractVersion": "1.0",
  "requestId": "unique-id",
  "locale": "zh-CN",
  "utterance": "把客厅灯调到 60%",
  "intent": "light.brightness.set",
  "parameters": {"roomName": "客厅", "deviceName": "主灯", "brightness": 60}
}
```

The script prints a single JSON response (`contractVersion`, `requestId`,
`status`, `userMessage`, optional `result`/`clarification`/`error`). Status is
one of: `success`, `partial`, `clarification_required`, `blocked`,
`not_supported`, `auth_required`, `error`. Read `status` and `userMessage`
first; surface `userMessage` to the user verbatim when present.

## Absolute rules

1. First-time use (status `auth_required`): ask the user to bind an account.
   Run with `intent="bind.account"`, then guide them to scan the QR code
   displayed on the device screen (or open the URL shown in `result`).
   Poll by re-running `bind.account` with
   `parameters.resume={qrCodeId=..., deviceId=...}`.
2. Never invent device/room/scene IDs. Use `entity.list` /
   `target_resolver` output. When a name matches several entities, the
   response is `clarification_required` with candidates — ask the user to
   choose; never guess.
3. Never ask for or accept account passwords or tokens. Binding is QR-only.
4. R3 destructive intents (delete home/gateway/device, member remove or
   transfer, lock/unlock all, unbind) require the user's explicit
   confirmation first, then re-run with `parameters.confirmed=true`.
   Never add `confirmed` on your own initiative.
5. Do not claim success unless `status` is `success`. `partial` means some
   targets failed — report `userMessage` which names them.
6. Never print or relay the `Authorization` header, tokens, or raw
   credential files.
7. Intents listed as not supported in
   `{CUR_SKILL_DIR}/assets/intent-map.json` return `not_supported`; do not
   retry them or approximate with other intents.
8. List responses are capped (top N + total). To narrow results, re-run the
   same intent with `parameters.pageNo` / a `roomName` / a search word.
9. Large-parameter payloads: set `options.explain=true` to request
   `intent.explain`-style guidance for that intent's expected parameters.

## High-frequency routing

| Utterance pattern | Intent |
|---|---|
| 开/关/调亮度/色温/颜色 <灯> | `light.power.set` / `light.brightness.set` / `light.color_temperature.set` / `light.color.set` |
| 打开/关闭 <房间/区域/全屋> 的灯 | same intents with nodeType room/area/home targets |
| 执行/运行/启动 <情景> | `scene.execute` |
| 现在有哪些灯 / 设备 | `entity.list` / `device.list` |
| 有哪些家庭 / 房间 | `home.list` / `room.list` |
| 列出自动化 / 启用 / 停用 | `automation.list` / `automation.enable` / `automation.disable` |
| 这个设备什么状态 | `state.query` |
| 灯不亮了 / 帮我检查 | `diagnose.device` |
| 绑定账号 / 重新绑定 | `bind.account` |

## Parameter quick reference

- Light control: `parameters` = `{roomName?, deviceName?, areaName?,
  groupName?, brightness? (0-100), colorTemperature? (K or profile),
  color? (RGB int or name), power? (on/off)}`.
- Scene execute: `{sceneName}` or `{sceneId}`.
- State query: `{deviceId}` or `{deviceName}` + optional `{roomName}`;
  `{propertyName}` to filter.
- Batch/bulk: `parameters.targets=[{...}, ...]`; failures yield `partial`.
- `parameters.dryRun=true` previews a write without executing.

## References

- `{CUR_SKILL_DIR}/references/README.md` — shortest-path router to all guides
- `{CUR_SKILL_DIR}/assets/intent-map.json` — every intent → support level + handler module
- `{CUR_SKILL_DIR}/references/cloud-api-map.md` — cloud endpoints used per intent
- `{CUR_SKILL_DIR}/references/safety-and-confirmation.md` — R0–R3 risk lanes
- `{CUR_SKILL_DIR}/references/device-runtime.md` — binding, token, limits, errors
