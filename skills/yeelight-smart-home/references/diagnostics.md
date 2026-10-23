# 诊断

- `diagnose.device`：本地组装 —— 状态读回（state）+ 拓扑在线状态 -> findings[]（ok/info/warn/error）。
  常见结论：power off、device offline、state read failure（指向网关/网络问题）。
- `diagnose.gateway`：网关列表/详情摘要（Thread 信息用 gateway.thread.get）。
- `diagnose.scene/automation`：读取配置详情生成摘要。
- `automation.explain` = diagnose.automation。
- 诊断只读，不修改任何状态。
