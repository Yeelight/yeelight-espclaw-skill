-- tests/test_topology.lua
local mock = require("tests.mock")
local topology = require("topology")

_G.storage_reset()
mock.setup_credentials("house-1")
_G.capability._reset()

mock.mock_http.on({
    method = "GET", path_contains = "/room/r/info/1/100",
    respond = function()
        return "HTTP 200\n" .. json.encode({
            success = true, data = { rows = {
                { id = "room-1", name = "客厅" },
                { id = "room-2", name = "卧室" },
            } },
        })
    end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/device/r/all",
    respond = function()
        return "HTTP 200\n" .. json.encode({
            success = true, data = { devices = {
                { id = "d1", name = "客厅吸顶灯", roomId = "room-1", category = "ceiling_lamp" },
                { id = "d2", name = "卧室台灯", roomId = "room-2" },
            } },
        })
    end,
})

local ok, topo, err = topology.load({})
mock.assert(ok, "topology load ok")
mock.assert_eq(topo.house_id, "house-1", "topology house id")
mock.assert_eq(#topo.rooms, 2, "rooms loaded")
mock.assert_eq(#topo.devices, 2, "devices loaded")
mock.assert_eq(topo.devices[1].roomName, "客厅", "room name joined")
mock.assert_eq(topo.devices[1].nodeType, 2, "default nodeType")

-- 缓存：TTL 内不再发请求
local calls_before = #_G.capability._calls
local ok2, topo2 = topology.load({})
mock.assert(ok2, "cache hit ok")
mock.assert_eq(#_G.capability._calls, calls_before, "no extra requests within TTL")

-- force 刷新
local ok3 = topology.load({ force = true })
mock.assert(ok3, "force reload ok")
mock.assert(#_G.capability._calls > calls_before, "force reload requests")

-- 失效后重载
topology.invalidate()
local ok4, topo4 = topology.load({})
mock.assert(ok4, "reload after invalidate")

-- extract_rows 容器兼容
mock.assert_eq(#topology.extract_rows({ data = { rows = { 1, 2 } } }), 2, "extract rows")
mock.assert_eq(#topology.extract_rows({ data = { devices = { 1 } } }), 1, "extract devices")
mock.assert_eq(#topology.extract_rows({ rows = { 1 } }), 1, "extract top rows")
mock.assert_eq(#topology.extract_rows({}), 0, "extract empty")
