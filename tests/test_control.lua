-- tests/test_control.lua：灯控端到端（拓扑 -> 解析 -> 写 -> 验证）
local mock = require("tests.mock")
local router = require("router")

_G.storage_reset()
mock.setup_credentials("house-1")
_G.capability._reset()
require("topology").invalidate()

-- 拓扑
mock.mock_http.on({
    method = "GET", path_contains = "/room/r/info/1/100",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { rows = {
            { id = "room-1", name = "客厅" },
        } } })
    end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/device/r/all",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { devices = {
            { id = "d1", name = "客厅吸顶灯", roomId = "room-1" },
        } } })
    end,
})

-- 设备状态（可变）
local device_state = { p = false, l = 50, ct = 4000 }
local room_state = { p = false }

mock.mock_http.on({
    method = "POST", path_contains = "/v1/controll/device/d1/r/properties",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { properties = {
            { propId = "p", value = device_state.p },
            { propId = "l", value = device_state.l },
            { propId = "ct", value = device_state.ct },
            { propId = "c", value = device_state.c },
        } } })
    end,
})

-- 房间节点读（先于通用写 matcher 注册，避免被吞掉）
mock.mock_http.on({
    method = "POST", path_contains = "/control/1/room-1/r/properties",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { properties = {
            { propId = "p", value = room_state.p },
        } } })
    end,
})

-- 写端点：更新 device_state
mock.mock_http.on({
    method = "POST", path_contains = "/v1/open/control/house/house-1/control/",
    respond = function(opts)
        local prop = opts.url:match("/w/properties/([%w_]+)")
        local adjust = opts.url:find("/adjust", 1, true) ~= nil
        if prop then
            local body = json.decode(opts.body or "{}")
            local is_room = opts.url:find("/control/1/", 1, true) ~= nil
            local target = is_room and room_state or device_state
            if adjust then
                local cur = target[prop] or 0
                target[prop] = (tonumber(cur) or 0) + (tonumber(body.value) or 0)
            else
                target[prop] = body.value
            end
        end
        return "HTTP 200\n" .. json.encode({ success = true, data = {} })
    end,
})

local function invoke(intent, params, targets)
    local req = {
        contractVersion = "1.0", requestId = "r-test", locale = "zh-CN",
        utterance = "", intent = intent,
        parameters = params or {}, targets = targets,
    }
    return router.dispatch(req)
end

-- 开灯（显式 target）
local resp = invoke("light.power.set", { power = true },
    { { entityType = "device", id = "d1", name = "吸顶灯" } })
mock.assert_eq(resp.status, "success", "power set success")
mock.assert(resp.result.verified, "power verified")
mock.assert_eq(device_state.p, true, "device state power true")

-- 亮度设置（按名称解析）
resp = invoke("light.brightness.set", { deviceName = "吸顶灯", brightness = 60 })
mock.assert_eq(resp.status, "success", "brightness set success")
mock.assert_eq(device_state.l, 60, "brightness written")

-- 亮度越界 -> clarification
resp = invoke("light.brightness.set", { deviceName = "吸顶灯", brightness = 200 })
mock.assert_eq(resp.status, "clarification_required", "brightness out of range")

-- 亮度调节
device_state.l = 50
resp = invoke("light.brightness.adjust", { deviceName = "吸顶灯", delta = 30 })
mock.assert_eq(resp.status, "success", "adjust success")
mock.assert_eq(device_state.l, 80, "adjust applied")

-- 色温
resp = invoke("light.color_temperature.set", { deviceName = "吸顶灯", colorTemperature = 5500 })
mock.assert_eq(resp.status, "success", "ct set success")
mock.assert_eq(device_state.ct, 5500, "ct written")

-- 颜色（hex）
resp = invoke("light.color.set", { deviceName = "吸顶灯", color = "#FF0000" })
mock.assert_eq(resp.status, "success", "color set success")
mock.assert_eq(device_state.c, 16711680, "color written")

-- 名称歧义
resp = invoke("light.power.set", { roomName = "客厅", power = false }, nil)
-- roomName 无 deviceName -> 房间节点控制，应走 room node 端点
mock.assert(resp.status == "success", "room node control ok: " .. tostring(resp.status))
mock.assert(resp.result ~= nil, "room control result")

-- 未知设备 -> clarification
resp = invoke("light.power.set", { deviceName = "不存在的灯" })
mock.assert_eq(resp.status, "clarification_required", "unknown device clarification")

-- state.query
resp = invoke("state.query", { deviceId = "d1" })
mock.assert_eq(resp.status, "success", "state query ok")
mock.assert(resp.result.properties ~= nil, "state properties")

-- R3 未确认被拦截（router 层）
resp = invoke("device.unbind", { deviceId = "d1" })
mock.assert_eq(resp.status, "blocked", "device.unbind blocked")

-- dryRun
resp = invoke("light.brightness.set", { deviceName = "吸顶灯", brightness = 10, dryRun = true })
mock.assert_eq(resp.status, "success", "dry run success")
mock.assert(resp.result.dryRun, "dry run flag")
mock.assert_eq(device_state.l, 80, "dry run does not write")

-- entity.list
resp = invoke("entity.list", {})
mock.assert_eq(resp.status, "success", "entity list ok")
mock.assert_eq(resp.result.total, 1, "entity total")

-- 场景执行（无网关 -> blocked via fallback）
mock.mock_http.on({
    method = "POST", path_contains = "/control/w/scenes/scene-1",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = false, msg = "当前情景无有效网关" })
    end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/controll/device/w/scene/scene-1",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = {} }) end,
})
resp = invoke("scene.execute", { sceneId = "scene-1" })
mock.assert_eq(resp.status, "success", "scene execute fallback ok")

-- lighting design plan
resp = invoke("lighting.design.plan", { scene = "movie", deviceName = "吸顶灯" })
mock.assert_eq(resp.status, "success", "design plan ok")
mock.assert(resp.result.dryRun, "design plan is dry run")
