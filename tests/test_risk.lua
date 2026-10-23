-- tests/test_risk.lua
local mock = require("tests.mock")
local risk = require("risk")

-- 风险分级
mock.assert_eq(risk.risk_of("home.delete"), "R3", "R3 home.delete")
mock.assert_eq(risk.risk_of("device.unbind"), "R3", "R3 device.unbind")
mock.assert_eq(risk.risk_of("home.member.remove"), "R3", "R3 member remove")
mock.assert_eq(risk.risk_of("room.create"), "R2", "R2 room.create")
mock.assert_eq(risk.risk_of("scene.update"), "R2", "R2 scene.update")
mock.assert_eq(risk.risk_of("light.power.set"), "R1", "R1 control")
mock.assert_eq(risk.risk_of("home.list"), "R0", "R0 read")

local function req_of(intent, params)
    return { requestId = "r", locale = "zh-CN", intent = intent, parameters = params or {}, utterance = "" }
end

-- R3 未确认拦截
local resp = risk.guard(req_of("home.delete", {}))
mock.assert(resp ~= nil and resp.status == "blocked", "R3 unconfirmed blocked")
mock.assert(resp.clarification ~= nil, "R3 blocked has clarification")

-- R3 确认放行
mock.assert(risk.guard(req_of("home.delete", { confirmed = true })) == nil, "R3 confirmed passes")

-- 敏感属性拦截
resp = risk.guard(req_of("state.query", { property = "password" }))
mock.assert(resp ~= nil and resp.status == "blocked", "sensitive prop blocked")

resp = risk.guard(req_of("node.property.set", { prop = "wifi_password", value = "x" }))
mock.assert(resp ~= nil and resp.status == "blocked", "sensitive write blocked")

-- 可写白名单
resp = risk.guard(req_of("node.property.set", { prop = "admin_flag", value = 1 }))
mock.assert(resp ~= nil and resp.status == "blocked", "non-whitelisted prop blocked")

mock.assert(risk.guard(req_of("node.property.set", { prop = "l", value = 50 })) == nil,
    "whitelisted prop passes")
mock.assert(risk.guard(req_of("light.brightness.set", { brightness = 50 })) == nil,
    "light intent passes")
