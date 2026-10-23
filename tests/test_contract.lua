-- tests/test_contract.lua
local mock = require("tests.mock")
local contract = require("contract")

local req, err = contract.normalize_request({
    contractVersion = "1.0",
    requestId = "r-1",
    locale = "zh-CN",
    utterance = "打开主灯",
    intent = "light.power.set",
    parameters = { power = true },
})
mock.assert(req ~= nil, "normalize ok")
mock.assert_eq(err, nil, "normalize no err")
mock.assert_eq(req.requestId, "r-1", "requestId kept")
mock.assert_eq(req.parameters.power, true, "parameters kept")

-- 缺 intent
local bad, bad_err = contract.normalize_request({ contractVersion = "1.0" })
mock.assert(bad == nil, "missing intent rejected")
mock.assert(bad_err ~= nil, "missing intent err")

-- requestId 缺省生成
local auto = contract.normalize_request({ intent = "home.list" })
mock.assert(auto.requestId ~= nil and #auto.requestId > 0, "requestId generated")

-- 7 种 status 构造
local r = { requestId = "x", locale = "zh-CN", intent = "t", parameters = {} }
mock.assert_eq(contract.success(r).status, "success", "success status")
mock.assert_eq(contract.partial(r, "p").status, "partial", "partial status")
mock.assert_eq(contract.clarification(r, "q").status, "clarification_required", "clarification status")
mock.assert_eq(contract.blocked(r, "b").status, "blocked", "blocked status")
mock.assert_eq(contract.not_supported(r, "n").status, "not_supported", "not_supported status")
mock.assert_eq(contract.auth_required(r, "a").status, "auth_required", "auth_required status")
mock.assert_eq(contract.error(r, "e").status, "error", "error status")

-- error 附加 error 字段
local eresp = contract.error(r, "boom", "E_TEST")
mock.assert_eq(eresp.error.code, "E_TEST", "error code attached")

-- 参数兜底
mock.assert_eq(contract.param(r, "houseId"), nil, "param missing")
r.parameters.houseId = "h1"
mock.assert_eq(contract.param(r, "houseId"), "h1", "param read")
