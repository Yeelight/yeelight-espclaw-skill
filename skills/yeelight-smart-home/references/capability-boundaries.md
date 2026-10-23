# 能力边界（明确不支持）

- **MCP**：完全不使用（无 cap_mcp_client/server、无 JSON-RPC/SSE）。
- WiFi 灯 LAN 直连（需 raw socket / C 组件）；LAN 发现、BLE 配网、第三方账号扫码绑定。
- 固件升级写入（仅只读列表/进度）；OAuth/账号密码登录。
- `device.storage.get`：Runtime 即 stub，返回 not_supported。
- `lighting.experience.apply`：Runtime 明确 blocked。
- `lighting.design.import`：暂 not_supported（/v1/meta/import + 轮询为后续 stretch）。
- 情景执行批量网关 fallback（/v1/thing/device/w/scenes）：暂未实现，无网关直接 blocked。
- 商照项目（bizType=1）首期不支持（字段保留）。
- 244 产品全量目录不内置（用 product.pedia.search 在线查询）。
