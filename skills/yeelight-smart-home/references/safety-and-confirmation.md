# 安全与确认

## 风险车道
- R0 只读：无确认。
- R1 控制（light.*、node.property.*）：无聊天确认，但写后必须读回验证。
- R2 管理写（room/area/group/scene/automation CRUD、rename/move、favorite、panel/knob 配置）：
  支持 dryRun 预览；确认后直接执行。
- R3 高危（home.delete、gateway.delete、device.remove/unbind、home.member.remove/transfer/quit、
  home.lock_all/unlock_all）：必须先聊天确认，重发时带 `parameters.confirmed=true`。
  LLM 不得自行添加 confirmed。

## 敏感属性（读写均拦截）
password、passwd、token、secret、credential、auth、wifi_password、camera_stream、
audio_stream、privacy_mode、location、gps、phone、mobile、email 等。

## 可写白名单（node.property.set 等）
p、l、c、ct、tp、power、brightness、color、color_temperature、curtain_position、
fan_speed、mode、volume。白名单外一律 blocked。

## 其他
- token 绝不进入 LLM 参数/日志/响应（http.lua 内部注入，输出经 redact）。
- allowlist 仅 Yeelight 域名。
- 批量操作顺序执行，失败即 partial 并列明目标。
