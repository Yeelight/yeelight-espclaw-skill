-- tests/test_endpoints.lua：端点回归测试（锁定与 Runtime 核对过的 URL/方法/形状）
local mock = require("tests.mock")
local router = require("router")

_G.storage_reset()
mock.setup_credentials("house-1")
_G.capability._reset()
require("topology").invalidate()

local seen = {}
mock.mock_http.on({
    respond = function(opts)
        seen[#seen + 1] = (opts.method or "GET") .. " " .. opts.url .. " body=" .. tostring(opts.body or "")
        return "HTTP 200\n" .. json.encode({ success = true, data = {} })
    end,
})

local function invoke(intent, params)
    return router.dispatch({
        contractVersion = "1.0", requestId = "ep", locale = "zh-CN",
        utterance = "", intent = intent, parameters = params or {},
    })
end

local function assert_call(substr, msg)
    local found = false
    for _, c in ipairs(seen) do
        if c:find(substr, 1, true) then found = true end
    end
    mock.assert(found, "expected call " .. substr .. " (" .. tostring(msg) .. "); got " .. table.concat(seen, " | "))
end

-- 成员管理（固定路径 + body 携带 houseId）
invoke("home.member.list")
assert_call("POST https://api.yeelight.com/v1/house/r/memberlistV2", "member list")
invoke("home.member.remove", { memberId = "m1", confirmed = true })
assert_call("POST https://api.yeelight.com/v1/house/w/remove", "member remove")
invoke("home.member.quit", { uid = "u1", confirmed = true })
assert_call("POST https://api.yeelight.com/v1/house/w/quit", "member quit")
invoke("home.member.invite", {})
assert_call("POST https://api.yeelight.com/v1/share/r/housesharebarcode", "member invite")

-- 排序
invoke("home.sort.list")
assert_call("POST https://api.yeelight.com/v1/sort/r/getSort", "sort list")

-- 房间详情 / 批量
invoke("room.detail.get", { roomId = "room-9" })
assert_call("POST https://api.yeelight.com/v1/room/room-9/r/detail", "room detail")
invoke("room.batch_update", { updates = { { roomId = "r1", name = "x" } } })
assert_call("POST https://api.yeelight.com/v1/room/w/batchupdate", "room batch update")

-- 设备
invoke("device.virtual_count.get")
assert_call("POST https://api.yeelight.com/v1/device/r/house-1/virturlNum", "virtual count (cloud typo path)")
invoke("device.attr.list", { deviceId = "d1" })
assert_call("body={\"ids\":\"d1\"}", "attr list ids body")
invoke("entity.capabilities", { deviceId = "d1" })
assert_call("GET https://api.yeelight.com/v2/thing/schema/house/house-1/device/r/info/1/100?crop=false", "capabilities")

-- 面板 / 旋钮
invoke("panel.click", { deviceId = "p1", index = 2 })
assert_call("POST https://api.yeelight.com/v2/thing/control/panel/p1", "panel click")
invoke("panel.button.type.get", { deviceId = "p1" })
assert_call("POST https://api.yeelight.com/v1/panel/r/button/info/p1", "button type")
invoke("panel.button_event.update", { event = { index = 1 } })
assert_call("POST https://api.yeelight.com/v1/panel/w/button/event/update", "button event update")
invoke("panel.button_event.reset", { buttonEventId = "be1" })
assert_call("POST https://api.yeelight.com/v1/panel/w/button/event/be1/reset", "button event reset")
invoke("screen.control.list")
assert_call("POST https://api.yeelight.com/v1/ai/house-1/control/r/info", "screen control")
invoke("knob.get", { deviceId = "k1" })
assert_call("GET https://api.yeelight.com/v1/multi-knob/k1/detail", "knob multi detail")

-- 收藏：batch body 为裸数组
invoke("favorite.update", { favorite = { id = "f1", name = "n" } })
assert_call("POST https://api.yeelight.com/v1/favourite/w/batchupdate body=[{", "favorite update bare array")
invoke("favorite.delete", { id = "f1" })
assert_call("POST https://api.yeelight.com/v1/favourite/w/batchdelete body=[{", "favorite delete bare array")

-- 情景
invoke("scene.update", { sceneId = "s1", scene = { name = "n" } })
assert_call("POST https://api.yeelight.com/v2/thing/manage/house/house-1/scene/s1/w/modify", "scene modify")

-- 网关
invoke("gateway.stats.list")
assert_call("POST https://api.yeelight.com/v1/device/r/gatewayswithstats", "gateway stats")

-- 传感器 / 消息 / 升级 / 进度
invoke("sensor.event.write", { deviceId = "d1", event = { name = "e" } })
assert_call("POST https://api.yeelight.com/v1/sensor/w/insert", "sensor insert")
invoke("message.list")
assert_call("GET https://api.yeelight.com/v1/messagecenter/r/messages", "message list")
invoke("app_upgrade.latest.get")
assert_call("POST https://api.yeelight.com/v1/appupgrade/r/latestfile", "app upgrade")
invoke("upgrade.file.batch_list", { deviceIds = { "d1" } })
assert_call("POST https://api.yeelight.com/v1/upgrade/r/batchlistfile", "upgrade batch")
invoke("progress.get", { taskId = "t1" })
assert_call("POST https://api.yeelight.com/v1/progress/r/t1", "progress")

-- 地理区域
invoke("geo_area.children.list", { parentId = "1" })
assert_call("GET https://api.yeelight.com/v1/area/r/1/children", "geo children")
invoke("geo_area.search", { keyword = "北" })
assert_call("POST https://api.yeelight.com/v1/area/r/areas", "geo search")

-- 物模型
invoke("thing.schema.event.list", { productId = "pid1" })
assert_call("POST https://api.yeelight.com/v1/thing/schema/r/getEvents/pid1", "schema events")
invoke("thing.category.list")
assert_call("POST https://api.yeelight.com/v2/thing/schema/category/r/list", "category")
invoke("thing.property.list")
assert_call("POST https://api.yeelight.com/v2/thing/schema/property/r/list", "property list")
invoke("thing.product_domain.list")
assert_call("POST https://api.yeelight.com/v1/product-domain/r/list", "product domain")

-- ai_voice.list 不发云端请求（安全边界）
local before = #seen
local resp = invoke("ai_voice.list")
mock.assert_eq(resp.status, "blocked", "ai_voice.list blocked")
mock.assert_eq(#seen, before, "ai_voice.list makes no cloud call")

-- topology 填充 groups/scenes
_G.capability._reset()
seen = {}
mock.mock_http.on({
    method = "GET", path_contains = "/room/r/info/1/100",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = {} } }) end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/device/r/all",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { devices = {} } }) end,
})
mock.mock_http.on({
    method = "GET", path_contains = "/group/r/info/1/100",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = { { id = "g1", name = "客厅灯组" } } } }) end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/scene/r/all",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = { { id = "s1", name = "晚安" } } } }) end,
})
require("topology").invalidate()
local ok, topo = require("topology").load({ force = true })
mock.assert(ok, "topology load with groups/scenes")
mock.assert_eq(topo.groups and topo.groups[1] and topo.groups[1].id, "g1", "groups cached")
mock.assert_eq(topo.scenes and topo.scenes[1] and topo.scenes[1].id, "s1", "scenes cached")

-- userMessage 截断
local contract = require("contract")
local req = { requestId = "r", locale = "zh-CN", intent = "t", parameters = {} }
local long = string.rep("灯", 1000)
local resp2 = contract.make(req, "success", long)
mock.assert(#resp2.userMessage <= 1206, "userMessage truncated")
