# 家庭 / 房间 / 区域

## 家庭
- `home.list/summary/search`：`POST /v1/house/r/list`，数组响应包 data。
- 多家庭时默认使用绑定保存的 houseId；可用 `parameters.houseId` 覆盖。
- `home.detail.get` / `home.stat.get`：读详情与统计。
- `home.create/update/delete`、`home.lock_all/unlock_all`：管理（delete/lock/unlock 为 R3）。
- 成员：`home.member.list` 及 invite/accept/configure/remove/transfer/quit（remove/transfer/quit 为 R3）。
- 排序：`home.sort.list/configure`（sortType + target + ids）。

## 房间
- 列表 `GET /v2/thing/manage/house/{h}/room/r/info/{page}/100`；详情 `.../room/r/detail/{id}`。
- 创建/改名/更新/删除：`PUT .../room/w/create`、`POST /v1/room/{id}/w/update`、`DELETE .../room/{id}/w/info`。
- 批量：room.batch_create(names)/batch_update(updates)/batch_delete —— 顺序执行，失败即 partial。

## 区域
- `area.list/detail.get/create/update/delete`；`room.area.configure` 维护区域-房间映射（areaId+roomIds）。
