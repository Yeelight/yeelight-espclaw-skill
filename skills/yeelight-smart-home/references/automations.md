# 自动化

- 列表 `GET /v1/automations/{h}/r/list/{p}/{s}`；详情 `GET /v2/thing/manage/house/{h}/automation/{id}/r/info`。
- 创建 `PUT .../automation/w/create`（完整 rule payload）；更新 `PUT /v1/automations/{id}/w/update`（全量替换）。
- 启停：`POST /v1/automations/w/enable|disable/{id}`。
- 删除：`DELETE .../automation/{id}/w/info`。
- `automation.explain/capabilities`：读取规则与能力目录，转为解释性摘要。
- schedule：`POST /v1/schedulejob/r/list`（schedule_job.list）。
