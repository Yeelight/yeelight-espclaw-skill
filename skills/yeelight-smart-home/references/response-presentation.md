# 回复呈现

- userMessage 为面向用户的一句话（中文优先），直接转述给用户；不要重复 JSON。
- 列表：`共 N 项（显示前 10 项）：a、b、c`，提示用搜索词或分页缩小。
- 歧义：列出候选（含房间标注），让用户选择，不要猜 ID。
- partial：明确列出失败目标与原因。
- blocked（R3）：解释风险并请求确认；确认后重发 confirmed=true。
- result 字段供 LLM 引用关键数值（如 verified/property/expectedValue），不要整体粘贴。
