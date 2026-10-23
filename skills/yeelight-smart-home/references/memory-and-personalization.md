# 记忆 / 个性化（本地能力）

存储于设备 storage `yeelight-smart-home/`：
- memory.json：用户偏好（最多 50 条，同文去重）。memory.remember/list/forget/pause/resume。
- memory_pause.json：暂停标记；暂停期间 memory.list 返回 paused=true。
- recommendation.json：推荐记录与反馈。
- lesson.json：运维经验教训（operation.lesson.record/list）。

红线：
- 不记录密码/token/精确位置等敏感内容；调用方应避免把敏感 utterance 存入 memory。
- 记忆只影响表达与默认值建议，不影响控制安全策略。
