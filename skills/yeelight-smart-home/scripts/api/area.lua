-- api/area.lua：区域域（area.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")

local M = {}

local function area_base(house_id)
    return "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/area"
end

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["area.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, { method = "GET", path = area_base(house_id) .. "/r/info/1/100" })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["area.detail.get"] = function(ctx)
    local req = ctx.req
    local area_id = contract.param(req, "areaId") or contract.param(req, "id")
    if not area_id then return missing(req, "areaId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET", path = area_base(house_id) .. "/r/detail/" .. util.url_escape(tostring(area_id)),
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { area = data.data or data })
end

M.routes["area.create"] = function(ctx)
    local req = ctx.req
    local name = contract.param(req, "name") or contract.param(req, "areaName")
    if not name then return missing(req, "name") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = { name = tostring(name) }
    local room_ids = contract.param(req, "roomIds")
    if type(room_ids) == "table" then body.roomIds = room_ids end
    local level = contract.param(req, "level")
    if level ~= nil then body.level = level end
    local data, resp2 = common.call(req, {
        method = "PUT", path = area_base(house_id) .. "/w/create", body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale), { area = data.data or data })
end

M.routes["area.update"] = function(ctx)
    local req = ctx.req
    local area_id = contract.param(req, "areaId") or contract.param(req, "id")
    if not area_id then return missing(req, "areaId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = {}
    for _, k in ipairs({ "name", "icon", "roomIds", "level" }) do
        local v = contract.param(req, k)
        if v ~= nil then body[k] = v end
    end
    local data, resp2 = common.call(req, {
        method = "POST", path = area_base(house_id) .. "/" .. util.url_escape(tostring(area_id)) .. "/w/update",
        body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

local function area_delete(req)
    local area_id = contract.param(req, "areaId") or contract.param(req, "id")
    if not area_id then return missing(req, "areaId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "DELETE",
        path = area_base(house_id) .. "/" .. util.url_escape(tostring(area_id)) .. "/w/info",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["area.delete"] = area_delete
M.routes["area.batch_delete"] = area_delete

return M
