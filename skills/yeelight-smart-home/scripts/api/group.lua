-- api/group.lua：灯组域（group.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")

local M = {}

local function group_base(house_id)
    return "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/group"
end

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["group.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET", path = group_base(house_id) .. "/r/info/1/100",
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req,
        i18n.t("group_list", req.locale, #rows, common.name_list(summary.items)),
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["group.structure.list"] = M.routes["group.list"]

M.routes["group.search"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local word = contract.param(req, "keyword") or contract.param(req, "groupName") or ""
    local data, resp2 = common.call(req, { method = "GET", path = group_base(house_id) .. "/r/info/1/100" })
    if not data then return resp2 end
    local matched = {}
    for _, g in ipairs(topology.extract_rows(data)) do
        local name = tostring(g.name or "")
        if word == "" or name:find(word, 1, true) then matched[#matched + 1] = g end
    end
    return contract.success(req, i18n.t("group_list", req.locale, #matched, common.name_list(matched)),
        { total = #matched, items = common.top_n(matched).items })
end

M.routes["group.detail.get"] = function(ctx)
    local req = ctx.req
    local group_id = contract.param(req, "groupId") or contract.param(req, "id")
    if not group_id then return missing(req, "groupId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET", path = group_base(house_id) .. "/" .. util.url_escape(tostring(group_id)) .. "/r/info",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { group = data.data or data })
end

M.routes["group.complex.get"] = M.routes["group.detail.get"]

M.routes["group.create"] = function(ctx)
    local req = ctx.req
    local name = contract.param(req, "name") or contract.param(req, "groupName")
    if not name then return missing(req, "name") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = { name = tostring(name) }
    local device_ids = contract.param(req, "deviceIds")
    if type(device_ids) == "table" then body.deviceIds = device_ids end
    local data, resp2 = common.call(req, {
        method = "PUT", path = group_base(house_id) .. "/w/create", body = body,
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale), { group = data.data or data })
end

M.routes["group.update"] = function(ctx)
    local req = ctx.req
    local group_id = contract.param(req, "groupId") or contract.param(req, "id")
    if not group_id then return missing(req, "groupId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = {}
    for _, k in ipairs({ "name", "icon" }) do
        local v = contract.param(req, k)
        if v ~= nil then body[k] = v end
    end
    local data, resp2 = common.call(req, {
        method = "POST", path = group_base(house_id) .. "/" .. util.url_escape(tostring(group_id)) .. "/w/modify",
        body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["group.members.update"] = function(ctx)
    local req = ctx.req
    local group_id = contract.param(req, "groupId") or contract.param(req, "id")
    local device_ids = contract.param(req, "deviceIds")
    if not group_id or type(device_ids) ~= "table" then return missing(req, "groupId/deviceIds") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = group_base(house_id) .. "/" .. util.url_escape(tostring(group_id)) .. "/w/devices",
        body = { deviceIds = device_ids },
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

local function group_delete(req)
    local group_id = contract.param(req, "groupId") or contract.param(req, "id")
    if not group_id then return missing(req, "groupId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "DELETE",
        path = group_base(house_id) .. "/" .. util.url_escape(tostring(group_id)) .. "/w/info",
        body = {},
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["group.delete"] = group_delete
M.routes["group.batch_delete"] = group_delete

return M
