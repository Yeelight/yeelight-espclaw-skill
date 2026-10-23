# 设备控制参考

## 属性词汇（propId）
- `p` 开关：boolean（on/off/开/关）
- `l` 亮度：1–100 整数；adjust 用增量 ±100
- `ct` 色温：2700–6500K；adjust 增量 ±3800
- `c` 颜色：RGB 整数或 `#RRGGBB` 或颜色名（红/绿/蓝/白/黄/青/紫/橙）
- `tp` 窗帘开合度：%

## 控制流程（light.* / node.property.*）
1. risk.guard（R1 无需确认）
2. 解析目标：显式 targets/deviceId > deviceName(+roomName 限定) > roomName 房间节点(nodeType=1)
   > groupName 灯组节点(nodeType=4) > 全屋 home 节点(nodeType=5)
3. 逐目标写属性；写后读回验证（默认 3 次 × 400ms；数值容差 ±1）
4. 全部验证通过 -> success；部分失败 -> partial（列明失败目标）；写失败 -> error

## 特殊行为
- `dryRun=true`：只返回 plan 不执行。
- adjust：先读当前值，计算期望绝对值（clamp 1–100 / 0–6500），写增量后按期望值验证。
- 名称歧义 -> clarification_required（候选 ≤5，含房间标注）。
- 灯效 `lighting.flow.execute`：走属性写 `flow`，value 为参数表。
