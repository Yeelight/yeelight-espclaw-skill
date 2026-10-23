-- api/gateway.lua：网关域（gateway.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")

local M = {}

local function gw_base(house_id)
    return "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/gateway"
end

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["gateway.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, { method = "GET", path = gw_base(house_id) .. "/r/info/1/100" })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

-- 网关统计：POST /v1/device/r/gatewayswithstats {houseId}
M.routes["gateway.stats.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/r/gatewayswithstats", body = { houseId = house_id },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- 网关-情景关系：POST /v1/scene/r/{gatewayId}/related/sceneId
M.routes["gateway.scene_relation.list"] = function(ctx)
    local req = ctx.req
    local gateway_id = contract.param(req, "gatewayId")
    if not gateway_id then return missing(req, "gatewayId") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/scene/r/" .. util.url_escape(tostring(gateway_id)) .. "/related/sceneId",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { sceneIds = (data.data and data.data.sceneIds) or data.data or {} })
end

M.routes["gateway.detail.get"] = function(ctx)
    local req = ctx.req
    local gateway_id = contract.param(req, "gatewayId") or contract.param(req, "id")
    if not gateway_id then return missing(req, "gatewayId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = gw_base(house_id) .. "/" .. util.url_escape(tostring(gateway_id)) .. "/r/info",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { gateway = data.data or data })
end

M.routes["gateway.thread.get"] = function(ctx)
    local req = ctx.req
    local gateway_id = contract.param(req, "gatewayId") or contract.param(req, "id")
    if not gateway_id then return missing(req, "gatewayId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = gw_base(house_id) .. "/" .. util.url_escape(tostring(gateway_id)) .. "/r/thread-info",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { thread = data.data or data })
end

M.routes["gateway.configure"] = function(ctx)
    local req = ctx.req
    local gateway_id = contract.param(req, "gatewayId") or contract.param(req, "id")
    if not gateway_id then return missing(req, "gatewayId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = {}
    for _, k in ipairs({ "name", "icon", "roomId" }) do
        local v = contract.param(req, k)
        if v ~= nil then body[k] = v end
    end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = gw_base(house_id) .. "/" .. util.url_escape(tostring(gateway_id)) .. "/w/modify",
        body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["gateway.delete"] = function(ctx)
    local req = ctx.req
    local gateway_id = contract.param(req, "gatewayId") or contract.param(req, "id")
    if not gateway_id then return missing(req, "gatewayId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "DELETE",
        path = gw_base(house_id) .. "/" .. util.url_escape(tostring(gateway_id)) .. "/w/info",
        body = {},
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

return M
