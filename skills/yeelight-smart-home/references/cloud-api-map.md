# 云端 REST 端点映射（基线：yeelight-home Runtime 同版本语义）

Base：cn `https://api.yeelight.com/apis/iot`；sg/us/eu 分别为 api-sg/api-us/api-de；
dev `http://api-dev.yeedev.com/apis/iot`。Account 基址去掉 `/apis/iot`；Pedia 为 `https://api.yeelight.com/apis/c`。

## 读
- 家庭：`POST /v1/house/r/list`；`GET /v1/house/{id}/r/info`；`POST /v1/house/{id}/r/stat`
- 房间：`GET /v2/thing/manage/house/{h}/room/r/info/{page}/100`；
  区域：`GET .../area/r/info/{p}/100`、`GET .../area/{id}/r/info`、
  更新 `POST .../area/{id}/w/modify`
- 设备：`POST /v1/device/r/all`（body houseId）；`POST /v1/device/{id}/r/detail`；
  `GET /v2/thing/manage/house/{h}/device/{id}/r/complex`；`POST /v1/device/r/attrs`（body ids）；
  虚拟设备数 `POST /v1/device/r/{houseId}/virturlNum`（云端即此拼写）；
  能力 `GET /v2/thing/schema/house/{h}/device/r/info/1/100?crop=false`（本地过滤设备）
- 灯组：`GET .../group/r/info/{p}/100`；情景列表 `POST /v1/scene/r/all`（body houseId）、
  `POST .../scene/r/info/{p}/100`；`POST /v1/scene/{id}/r/detail`
- 自动化：`GET /v1/automations/{h}/r/list/{p}/{s}`；`GET .../automation/{id}/r/info`
- 网关：`GET .../gateway/r/info/{p}/100`；`GET .../gateway/{id}/r/info`；`.../r/thread-info`；
  统计 `POST /v1/device/r/gatewayswithstats`；情景关系 `POST /v1/scene/r/{gwId}/related/sceneId`
- 面板/旋钮：`GET /v1/panel/r/list/{h}`；`POST /v1/panel/r/detail/{id}`；`POST /v1/multi-knob/{id}/r/detail`
- 收藏：`POST /v1/favourite/r/all`；排序：`POST /v1/sort/{h}/r/entity/device/all`
- 消息/传感器/能耗/天气：`GET /v1/messagecenter/r/messages`；`POST /v1/device/r/sensors`；
  `POST /v1/sensor/r/events`；事件写入 `POST /v1/sensor/w/insert`（test: `/w/test`）；
  `GET /v1/energy/devices/{id}/r/summary`；`POST /v1/weather/r/{id}/{type}/queryWeather`
- 地理区域：`GET /v1/area/r/{parentId}/children`；搜索 `POST /v1/area/r/areas` {name}
- 物模型/产品：`POST /v1/thing/schema/r/list`；事件 `POST /v1/thing/schema/r/getEvents/{pid}`；
  分类 `POST /v2/thing/schema/category/r/list`；组件 `POST /v2/thing/schema/component/r/list`；
  属性 `POST /v2/thing/schema/property/r/list`；产品域 `POST /v1/product-domain/r/list`；
  `GET /v2|v3/thing/schema/product/r/info?pids=`；
  `POST {pedia}/v1/pedia/product/r/search`；`POST /v1/platform/thing/product_faq/r/list`
- 升级只读：`POST /v1/upgrade/r/listfile`、`POST /v1/upgrade/r/batchlistfile`、
  `POST /v1/upgrade/r/progress`、`POST /v1/progress/r/{key}`；
  App 升级 `POST /v1/appupgrade/r/latestfile`；OTA `POST /v1/ota/upgrade/r/batchListFilesByVersion`；
  AI 语音产品 `GET /v1/ai/voice/product/r/list`（ai_voice.list 为安全边界投影，不调云端）

## 状态 / 控制
- 读状态：设备 `POST /v1/controll/device/{id}/r/properties[/{prop}]`；
  节点 `POST /v1/open/control/house/{h}/control/{nt}/{nid}/r/properties[/{prop}]`
- 写属性：`POST /v1/open/control/house/{h}/control/{nt}/{nid}/w/properties/{prop}` body `{value, command?, duration?, delay?, index?}`
- 调节：`.../w/properties/{prop}/adjust`（value=增量）；切换：`.../w/properties/{prop}/toggle`
- nodeType：1 房间、2 设备、3 自定义组、4 Mesh 灯组、5 家庭
- 属性 ID：p 开关、l 亮度(1-100)、ct 色温(2700-6500)、c 颜色(RGB int)、tp 窗帘开合度

## 情景执行（含 fallback 链）
1. `POST /v1/open/control/house/{h}/control/w/scenes/{sceneId}`
2. `POST /v1/controll/device/w/scene/{sceneId}`
3. `POST /v1/thing/device/w/scene/{sceneId}`
报「当前情景无有效网关」时 -> blocked（批量网关 fallback 未实现，见 capability-boundaries.md）。

## 管理（写）
- 房间 CRUD：`PUT .../room/w/create`、`POST /v1/room/{id}/w/update`、`DELETE .../room/{id}/w/info`、
  详情 `POST /v1/room/{id}/r/detail`、批量更新 `POST /v1/room/w/batchupdate`、
  区域映射 `POST .../room/{roomId}/w/areas`（body: houseId + id + areaId/addAreaList/removeAreaList）
- 设备：`POST /v1/device/{id}/w/update`（改名/移动）、`DELETE .../device/{id}/w/info`（移除）、`.../w/unbind`
- 灯组：`PUT .../group/w/create`、`POST .../group/{id}/w/modify`、`.../w/devices`、`DELETE .../w/info`
- 情景：`PUT .../scene/w/create`、`POST /v1/scene/{id}/w/modify`、`DELETE .../scene/{id}/w/info`
- 自动化：`PUT .../automation/w/create`、`PUT /v1/automations/{id}/w/update`、
  `POST /v1/automations/w/enable|disable/{id}`、`DELETE .../automation/{id}/w/info`
- 家庭：`PUT /v2/thing/manage/house/w/create`、`POST /v2/thing/manage/house/{id}/w/modify`、
  `POST /v1/house/{id}/w/delete`、`/lockall`、`/unlockall`
- 成员（固定路径，body = payload + houseId）：
  invite `POST /v1/share/r/housesharebarcode`；accept `POST /v1/share/w/acceptbarcodeshare`；
  configure `POST /v1/house/w/updateUserRole`；remove `POST /v1/house/w/remove`；
  transfer `POST /v1/house/w/transfer`；quit `POST /v1/house/w/quit`；
  列表 `POST /v1/house/r/memberlistV2`
- 面板/旋钮：`POST /v1/panel/w/button/update/{id}`；按键事件 `POST /v1/panel/w/button/event/update`
  （batch: `/update/batch`；reset: `/v1/panel/w/button/event/{id}/reset`）；
  按键类型 `POST /v1/panel/r/button/info/{id}`；点击 `POST /v2/thing/control/panel/{resId}`；
  屏控制 `POST /v1/ai/{h}/control/r/info`；
  旋钮 `GET /v1/multi-knob/{id}/detail`（单旋钮回退 `GET /v1/knobs/{id}/detail`）、
  `POST /v1/multi-knob/update`、`POST /v1/multi-knob/{id}/{idx}/reset`
- 收藏：`POST /v1/favourite/w/insert`（单条对象）；batch 端点 body 为**裸数组**：
  `w/batchinsert`、`w/batchupdate`、`w/batchdelete`（单条 update/delete 也走 batch）
- 排序：`POST /v1/sort/r/getSort`；`POST /v1/sort/{h}/w/{type}/{target}/add`；
  设备排序 `POST /v1/node/r/1/{target}/device`
