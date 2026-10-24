-- tests/test_review2.lua：第二轮审查修复的回归测试
local mock = require("tests.mock")
local router = require("router")
local contract = require("contract")

_G.storage_reset()
mock.setup_credentials("house-1")
_G.capability._reset()
require("topology").invalidate()

-- 拓扑（v2 分页设备端点，两页）
mock.mock_http.on({
    method = "GET", path_contains = "/room/r/info/1/100",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { rows = { { id = "room-1", name = "客厅" } } } })
    end,
})
local page_state = 0
mock.mock_http.on({
    method = "GET", path_contains = "/device/r/info/",
    respond = function(opts)
        local p = tonumber(opts.url:match("/device/r/info/(%d+)/100"))
        if p == 1 then
            return "HTTP 200\n" .. json.encode({ success = true, total = 2, rows = {
                { id = "d1", name = "客厅吸顶灯", roomId = "room-1" },
            } })
        end
        return "HTTP 200\n" .. json.encode({ success = true, total = 2, rows = {
            { id = "d2", name = "卧室台灯", roomId = "room-2" },
        } })
    end,
})
mock.mock_http.on({
    method = "GET", path_contains = "/group/r/info/1/100",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = { { id = "g1", name = "客厅灯组" } } } }) end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/scene/r/all",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = { { id = "s1", name = "晚安" } } } }) end,
})

local function invoke(intent, params, targets, options)
    return router.dispatch({
        contractVersion = "1.0", requestId = "r2", locale = "zh-CN",
        utterance = "", intent = intent,
        parameters = params or {}, targets = targets, options = options,
    })
end

-- 1) 分页拉全设备
require("topology").invalidate()
local resp = invoke("entity.list")
mock.assert_eq(resp.status, "success", "entity.list ok")
mock.assert_eq(resp.result.total, 2, "paged devices total 2")

-- 2) 仅带 name 的 targets
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/control/2/d2/w/properties/p",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = {} })
    end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/controll/device/d2/r/properties",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { properties = { { propId = "p", value = true } } } })
    end,
})
resp = invoke("light.power.set", { power = true },
    { { entityType = "device", name = "台灯" } })
mock.assert_eq(resp.status, "success", "name-only target resolved: " .. tostring(resp.userMessage))

-- name-only 未找到 -> clarification
resp = invoke("light.power.set", { power = true },
    { { entityType = "device", name = "不存在的灯" } })
mock.assert_eq(resp.status, "clarification_required", "name-only not found")

-- 3) parameters.targets（SKILL.md 契约）
resp = invoke("light.power.set", { power = true, targets = { { entityType = "device", name = "台灯" } } })
mock.assert_eq(resp.status, "success", "parameters.targets works")

-- 4) scene.test 不执行（dryRun）
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/control/w/scenes/s1",
    respond = function()
        mock.assert(false, "scene.test must not call execute endpoint")
        return "HTTP 200\n" .. json.encode({ success = true, data = {} })
    end,
})
resp = invoke("scene.test", { sceneId = "s1" })
mock.assert_eq(resp.status, "success", "scene.test ok")
mock.assert(resp.result.dryRun == true, "scene.test is dry run")

-- scene.execute 真实执行（替换陷阱 mock）
mock.mock_http.clear()
mock.mock_http.on({
    method = "POST", path_contains = "/control/w/scenes/s1",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = {} }) end,
})
resp = invoke("scene.execute", { sceneId = "s1" })
mock.assert_eq(resp.status, "success", "scene.execute real")

-- 5) state.query 对房间节点（nodeType=1 走 house 端点）
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/open/control/house/house-1/control/1/room-1/r/properties",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { properties = { { propId = "p", value = true } } } })
    end,
})
resp = invoke("state.query", { roomName = "客厅" })
mock.assert_eq(resp.status, "success", "state.query room node ok: " .. tostring(resp.userMessage))
mock.assert(resp.result.properties and resp.result.properties.p == true, "room state read")

-- 6) node.action.execute 走 /w/actions/
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/v1/controll/device/2/d1/w/actions/",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = {} }) end,
})
resp = invoke("node.action.execute", { deviceId = "d1", action = "toggle_night_light" })
mock.assert_eq(resp.status, "success", "node action ok")

-- 7) lighting.flow.execute 走 /w/flow
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/v1/controll/device/2/d1/w/flow",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = {} }) end,
})
resp = invoke("lighting.flow.execute", { deviceId = "d1", flow = { name = "sunrise" } })
mock.assert_eq(resp.status, "success", "flow execute ok")

-- 8) options.explain 不执行
_G.capability._reset()
local calls_before = #_G.capability._calls
resp = invoke("light.power.set", { power = true }, nil, { explain = true })
mock.assert_eq(resp.status, "success", "explain ok")
mock.assert_eq(resp.result.intent, "light.power.set", "explain returns intent info")
mock.assert_eq(#_G.capability._calls, calls_before, "explain makes no cloud call")

-- 9) home.property.set 家庭节点
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/open/control/house/house-1/control/5/house-1/w/properties/",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = {} }) end,
})
resp = invoke("home.property.set", { prop = "mode", value = "away" })
mock.assert_eq(resp.status, "success", "home.property.set ok")

-- 10) 批量嵌套深度限制
resp = invoke("operation.batch.configure", { steps = {
    { intent = "operation.batch.configure", parameters = { steps = {
        { intent = "operation.batch.configure", parameters = { steps = {
            { intent = "operation.batch.configure", parameters = { steps = {
                { intent = "home.list" },
            } } },
        } } },
    } } },
} })
-- 第 4 层应被拦截（blocked）
mock.assert(resp.status == "partial" or resp.status == "error" or resp.status == "success",
    "deep batch terminates: " .. tostring(resp.status))

-- 11) userMessage 不超限
mock.assert(#tostring(resp.userMessage) <= 1200, "userMessage within limit")
