-- api/room.lua：房间域（room.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")

local M = {}

local function room_base(house_id)
    return "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/room"
end

local function room_page(house_id)
    return room_base(house_id) .. "/r/info/1/100"
end

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["room.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, { method = "GET", path = room_page(house_id) })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req,
        i18n.t("room_list", req.locale, contract.param(req, "houseId") or "", #rows,
            common.name_list(summary.items)),
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["room.search"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local word = contract.param(req, "keyword") or contract.param(req, "roomName") or ""
    local data, resp2 = common.call(req, { method = "GET", path = room_page(house_id) })
    if not data then return resp2 end
    local matched = {}
    for _, r in ipairs(topology.extract_rows(data)) do
        local name = tostring(r.name or "")
        if word == "" or name:find(word, 1, true) then matched[#matched + 1] = r end
    end
    return contract.success(req, i18n.t("room_list", req.locale, "", #matched, common.name_list(matched)),
        { total = #matched, items = common.top_n(matched).items })
end

M.routes["room.detail.get"] = function(ctx)
    local req = ctx.req
    local room_id = contract.param(req, "roomId") or contract.param(req, "id")
    if not room_id then return missing(req, "roomId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/room/" .. util.url_escape(tostring(room_id)) .. "/r/detail", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { room = data.data or data })
end

M.routes["room.create"] = function(ctx)
    local req = ctx.req
    local name = contract.param(req, "name") or contract.param(req, "roomName")
    if not name then return missing(req, "name") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "PUT", path = room_base(house_id) .. "/w/create", body = { name = tostring(name) },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale), { room = data.data or data })
end

M.routes["room.batch_create"] = function(ctx)
    local req = ctx.req
    local names = contract.param(req, "names")
    if type(names) ~= "table" or #names == 0 then return missing(req, "names") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local failed = {}
    for _, name in ipairs(names) do
        local data, resp2 = common.call(req, {
            method = "PUT", path = room_base(house_id) .. "/w/create", body = { name = tostring(name) },
        })
        if not data then failed[#failed + 1] = tostring(name) end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale,
            "failed rooms: " .. table.concat(failed, "、")), { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["room.rename"] = function(ctx)
    local req = ctx.req
    local room_id = contract.param(req, "roomId") or contract.param(req, "id")
    local name = contract.param(req, "name") or contract.param(req, "roomName")
    if not room_id or not name then return missing(req, "roomId/name") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/room/" .. util.url_escape(tostring(room_id)) .. "/w/update",
        body = { name = tostring(name) },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["room.update"] = function(ctx)
    local req = ctx.req
    local room_id = contract.param(req, "roomId") or contract.param(req, "id")
    if not room_id then return missing(req, "roomId") end
    local body = {}
    for _, k in ipairs({ "name", "icon" }) do
        local v = contract.param(req, k)
        if v ~= nil then body[k] = v end
    end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/room/" .. util.url_escape(tostring(room_id)) .. "/w/update",
        body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["room.batch_update"] = function(ctx)
    local req = ctx.req
    local updates = contract.param(req, "updates") or contract.param(req, "rooms")
    if type(updates) ~= "table" or #updates == 0 then return missing(req, "updates") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/room/w/batchupdate", body = { rooms = updates },
    })
    if not data then return resp2 end
    require("topology").invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

local function room_delete(req)
    local room_id = contract.param(req, "roomId") or contract.param(req, "id")
    if not room_id then return missing(req, "roomId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "DELETE",
        path = room_base(house_id) .. "/" .. util.url_escape(tostring(room_id)) .. "/w/info",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["room.delete"] = room_delete
M.routes["room.batch_delete"] = room_delete

M.routes["room.area.configure"] = function(ctx)
    local req = ctx.req
    local room_id = contract.param(req, "roomId")
    if not room_id then return missing(req, "roomId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    -- Runtime 语义：payload 字段（areaId/addAreaList/removeAreaList...）+ houseId + id
    local body = { houseId = house_id, id = tostring(room_id) }
    local params = req.parameters or {}
    for _, k in ipairs({ "areaId", "addAreaList", "removeAreaList", "areaIds" }) do
        if params[k] ~= nil then body[k] = params[k] end
    end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id)
            .. "/room/" .. util.url_escape(tostring(room_id)) .. "/w/areas",
        body = body,
    })
    if not data then return resp2 end
    require("topology").invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

return M
