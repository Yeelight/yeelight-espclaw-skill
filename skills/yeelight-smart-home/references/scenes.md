# 情景

- 列表：`POST /v2/thing/manage/house/{h}/scene/r/info/{p}/100`；详情 `POST /v1/scene/{id}/r/detail`。
- 执行 `scene.execute`：按 fallback 链（见 cloud-api-map.md）。
  「当前情景无有效网关」-> blocked（提示用户检查网关）。
- `scene.test`：等价 dryRun 预览（plan 不执行）。
- 创建 `PUT .../scene/w/create`；更新 `POST /v1/scene/{id}/w/modify`（**全量替换**，
  payload 需完整 actions）；删除 `DELETE .../scene/{id}/w/info`。
- 场景 payload 形状见 payload-shapes.md；创建/更新需要完整动作数组，缺失时返回 clarification。
