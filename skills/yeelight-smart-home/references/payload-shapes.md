# Payload 形状速查

## 控制写（w/properties/{prop}）
```json
{"value": 60, "command": "set", "duration": 500, "delay": 0, "index": 1}
```
- set 端点：`command` 仅在非 set 时携带。
- adjust 端点（`.../w/properties/{prop}/adjust`）：body 仅 `{"value": <delta>}`，不带 command。
- toggle 端点（`.../w/properties/{prop}/toggle`）：body 为 `{}`。

## 情景创建/更新（全量）
```json
{"name": "观影", "actions": [{"targetType": 2, "targetId": "d1", "properties": {"l": 15, "ct": 2700}}]}
```

## 自动化规则（全量）
```json
{"name": "回家开灯", "conditions": [...], "actions": [...], "enabled": true}
```
条件/动作结构以 thing.schema 查询结果为准。

## 批量
- `parameters.targets`：`[{"id": "d1", "nodeType": 2}, ...]`
- `operation.batch.configure`：`{"steps": [{"intent": "...", "parameters": {...}}]}`

## 分页
路径式 `/r/info/{pageNo}/{pageSize}`（默认 100）；fuzzy 搜索默认 1/20；pedia limit ≤50。
