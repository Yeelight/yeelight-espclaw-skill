# 灯组

- 列表/搜索/详情：`GET .../group/r/info/{p}/100`、`.../group/{id}/r/info`。
- 创建 `PUT .../group/w/create`（name + deviceIds）；更新成员 `POST .../group/{id}/w/devices`（全量替换）。
- 改名 `POST .../group/{id}/w/modify`；删除 `DELETE .../group/{id}/w/info`（批量同路径）。
- 控制：group 节点 nodeType=4，直接对节点写属性（一次调用控制整组）。
- 拓扑缓存 60s；组成员变更后 invalidate。
