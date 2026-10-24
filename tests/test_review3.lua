-- tests/test_review3.lua：第三轮审查修复的回归测试
local mock = require("tests.mock")
local router = require("router")
local contract = require("contract")
local risk = require("risk")

_G.storage_reset()
mock.setup_credentials("house-1")
_G.capability._reset()
require("topology").invalidate()

local seen = {}
mock.mock_http.on({
    method = "POST", path_contains = "/v1/controll/device/d1/r/properties",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { properties = {
            { propId = "p", value = true }, { propId = "l", value = 50 },
        } } })
    end,
})
mock.mock_http.on({
    method = "GET", path_contains = "/room/r/info/1/100",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { rows = { { id = "room-1", name = "客厅" } } } })
    end,
})
mock.mock_http.on({
    method = "GET", path_contains = "/device/r/info/",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, total = 3, rows = {
            { id = "d1", name = "客厅吸顶灯", roomId = "room-1" },
            { id = "d2", name = "客厅落地灯", roomId = "room-1" },
            { id = "d3", name = "卧室台灯", roomId = "room-2" },
        } })
    end,
})
mock.mock_http.on({
    method = "GET", path_contains = "/group/r/info/1/100",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = {} } }) end,
})
mock.mock_http.on({
    method = "POST", path_contains = "/v1/scene/r/all",
    respond = function() return "HTTP 200\n" .. json.encode({ success = true, data = { rows = {} } }) end,
})
mock.mock_http.on({
    respond = function(opts)
        seen[#seen + 1] = (opts.method or "GET") .. " " .. opts.url .. " body=" .. tostring(opts.body or "")
        return "HTTP 200\n" .. json.encode({ success = true, data = {} })
    end,
})

local function invoke(intent, params, targets, options)
    return router.dispatch({
        contractVersion = "1.0", requestId = "r3", locale = "zh-CN",
        utterance = "", intent = intent,
        parameters = params or {}, targets = targets, options = options,
    })
end

-- 1) R3 confirmed 必须显式布尔 true
mock.assert(risk.guard({ requestId = "r", locale = "zh-CN", intent = "home.delete",
    parameters = { confirmed = "false" } }) ~= nil, "confirmed='false' rejected")
mock.assert(risk.guard({ requestId = "r", locale = "zh-CN", intent = "home.delete",
    parameters = { confirmed = 1 } }) ~= nil, "confirmed=1 rejected")
mock.assert(risk.guard({ requestId = "r", locale = "zh-CN", intent = "home.delete",
    parameters = { confirmed = true } }) == nil, "confirmed=true passes")

-- 2) prop 注入转义（toggle 走白名单 + URL 转义）
local resp = invoke("node.property.toggle", { deviceId = "d1", prop = "../../evil?x=1" })
mock.assert_eq(resp.status, "blocked", "toggle non-whitelisted prop blocked")
resp = invoke("node.property.toggle", { deviceId = "d1", prop = "p" })
assert_call_helper = nil
local found_escaped = false
for _, c in ipairs(seen) do
    if c:find("/w/properties/p/toggle", 1, true) then found_escaped = true end
end
mock.assert(found_escaped, "toggle prop path clean")

-- 3) node.properties.set 布尔 false 不被吞
seen = {}
resp = invoke("node.properties.set", { deviceId = "d1", properties = { { prop = "p", value = false } } })
local found_false = false
for _, c in ipairs(seen) do
    if c:find('body={"value":false}', 1, true) then found_false = true end
end
mock.assert(found_false, "false value written: " .. table.concat(seen, " | "))

-- 4) entity.list 分页 + roomName 过滤
resp = invoke("entity.list", { pageNo = 2, pageSize = 2 })
mock.assert_eq(resp.status, "success", "paged list ok")
mock.assert_eq(resp.result.pageNo, 2, "pageNo echoed")
mock.assert_eq(#resp.result.items, 1, "page 2 has 1 item (3 total, size 2)")
mock.assert_eq(resp.result.items[1].id, "d3", "page 2 starts at 3rd device")

resp = invoke("entity.list", { roomName = "客厅" })
mock.assert_eq(resp.result.total, 2, "roomName filter total 2")

-- 5) state.query propertyName 过滤
resp = invoke("state.query", { deviceId = "d1", propertyName = "brightness" })
mock.assert_eq(resp.status, "success", "state query filtered ok")
mock.assert(resp.result.properties.l == 50 and resp.result.properties.p == nil,
    "only brightness returned")

-- 6) 歧义候选 ≤5 且精简投影
resp = invoke("light.power.set", { roomName = "客厅", power = true }, { { name = "灯" } })
-- “灯”命中多个 -> clarification（若走 room 分支则 success，跳过）
if resp.status == "clarification_required" and resp.clarification.candidates then
    mock.assert(#resp.clarification.candidates <= 5, "candidates capped at 5")
    for _, c in ipairs(resp.clarification.candidates) do
        mock.assert(c.subDeviceList == nil, "candidate slimmed (no subDeviceList)")
    end
end

-- 7) truncate_utf8 产出合法 UTF-8（utf8.len 对非法序列返回 fail）
local r = { requestId = "r", locale = "zh-CN", intent = "t", parameters = {} }
-- 纯中文 1230B：截断点恰在多字节字符中间
local out = contract.make(r, "success", string.rep("中", 410))
mock.assert(type(out.userMessage) == "string" and #out.userMessage > 0, "truncated non-empty")
mock.assert(utf8.len(out.userMessage) ~= nil, "truncated message is valid UTF-8 (CJK)")
-- 中英混合：截断点落在 ASCII 段
local out2 = contract.make(r, "success", string.rep("中", 399) .. string.rep("a", 33))
mock.assert(utf8.len(out2.userMessage) ~= nil, "truncated message is valid UTF-8 (mixed)")

-- 8) allowlist host 精确匹配
local http = require("http")
local ok, _, err = http.request({ method = "GET", base = "https://api.yeelight.com.evil.com/apis/iot",
    path = "/x", no_auth = true })
mock.assert(not ok and err.code == "E_CONFIG", "evil host rejected")

-- 9) 空 200 body 视为成功
mock.mock_http.on({
    method = "POST", path_contains = "/v1/empty/ok",
    respond = function() return "HTTP 200\n" end,
})
ok, data, err = http.request({ method = "POST", path = "/v1/empty/ok", body = {} })
mock.assert(ok, "empty 200 body success")
mock.assert_eq(err, nil, "empty body no err")

-- 10) FAQ 端点
seen = {}
invoke("thing.product_faq.type.list")
local faq_ok = false
for _, c in ipairs(seen) do
    if c:find("GET https://api.yeelight.com/v1/platform/thing/product_faq/r/faq-types", 1, true) then faq_ok = true end
end
mock.assert(faq_ok, "faq-types endpoint")
invoke("thing.product_faq.detail.get", { faqId = "f1" })
faq_ok = false
for _, c in ipairs(seen) do
    if c:find("GET https://api.yeelight.com/v1/platform/thing/product_faq/r/f1/detail", 1, true) then faq_ok = true end
end
mock.assert(faq_ok, "faq detail endpoint")
