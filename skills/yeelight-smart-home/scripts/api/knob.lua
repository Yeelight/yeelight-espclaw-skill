-- api/knob.lua：旋钮域（knob.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")

local M = {}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["knob.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/multi-knob/" .. util.url_escape(tostring(device_id)) .. "/r/detail",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { knob = data.data or data })
end

M.routes["knob.configure"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local config = contract.param(req, "config")
    if not device_id or type(config) ~= "table" then return missing(req, "deviceId/config") end
    local body = util.merge(config, { deviceId = tostring(device_id) })
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/multi-knob/update", body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["knob.reset"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local index = contract.param(req, "index")
    if not device_id or index == nil then return missing(req, "deviceId/index") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/multi-knob/" .. util.url_escape(tostring(device_id))
            .. "/" .. util.url_escape(tostring(index)) .. "/reset",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

return M
