# 设备端运行时（token / QR / 限制 / 错误码）

## 绑定（唯一鉴权方式）
- `bind.account`：创建二维码（`POST /apis/account/user/scan-login/query/qrcode/{deviceId}`，
  deviceId 必须为 MAC 形态如 `F8:24:41:XX:XX:XX`，URL 中 `:` 编码为 %3A——已实测云端接受）
  -> 设备屏展示 -> 用户用 Yeelight App 扫码 -> 轮询
  （`POST /apis/account/user/scan-login/check/qrcode/{qrCodeId}`，status=LOGIN 成功 / EXPIRED 过期）。
- **二维码内容是 `cli&<MAC>&<qrCodeId>`**（Runtime BuildQRPayload 协议），不是 qrCodeId 本身；
  云端响应无 qrContent 字段，由 skill 本地构造。未扫码时 check 返回 status=CREATED（success=true）。
- 凭证（Authorization/Client-Id/houseId/bizType/region）保存于设备 storage
  `yeelight-smart-home/credentials.json`；**绝不出现在脚本输出、日志、错误信息**。
- 状态 `auth_required` 表示未绑定或 token 过期（解析 JWT exp），引导重新绑定。

## Header 注入（http.lua 统一处理）
`Authorization: Bearer ...`、`Client-Id`、`houseId`+`house-id`、`bizType(0=消费者)`、
`Accept: application/json`、`Accept-Language: zh-CN`。

## 运行时限制
- 脚本 ≤64KB；`lua_run_script` 输出 ≤4KB；同步超时默认 60s。
- HTTP：timeout 1–120000ms；响应 body ≤65535 字节（可 save_path 落盘再读）。
- 只能 HTTPS/HTTP，无原始 socket；无 response header（拿不到 Mcp-Session-Id 等）。
- storage 为共享 DATA 根目录，本 skill 只写 `yeelight-smart-home/` 子目录。

## 错误码（http.lua 内部）
| code | 含义 | 映射 status |
|---|---|---|
| E_NO_AUTH / not_bound | 未绑定 | auth_required |
| E_AUTH_EXPIRED (401) | token 过期 | auth_required |
| E_FORBIDDEN (403) | 无权限 | blocked |
| E_BUSINESS | 云端 success=false | error |
| E_HTTP | 非 2xx | error |
| E_NETWORK / E_DECODE | 网络/解析失败 | error |

## allowlist
api.yeelight.com、api-sg/api-us/api-de.yeelight.com、api-dev.yeedev.com；其余一律拒绝。
