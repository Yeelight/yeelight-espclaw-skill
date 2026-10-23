-- api/favorite.lua：收藏/排序域（favorite.*、home.sort.* 已在 home.lua）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")

local M = {}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["favorite.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/favourite/r/all", body = {},
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["favorite.plan"] = M.routes["favorite.list"]

local function fav_body(req)
    local body = {}
    for _, k in ipairs({ "id", "favoriteId", "targetType", "targetId", "name", "icon", "rank", "roomId", "valid" }) do
        local v = contract.param(req, k)
        if v ~= nil then body[k] = v end
    end
    return body
end

M.routes["favorite.add"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/favourite/w/insert", body = fav_body(req),
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale), { favorite = data.data or data })
end

-- 单条 update/delete 走 batch 端点（Runtime 语义：读-合并-批处理）
M.routes["favorite.update"] = function(ctx)
    local req = ctx.req
    local item = contract.param(req, "favorite")
    if type(item) ~= "table" then item = fav_body(req) end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/favourite/w/batchupdate", body = { item },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["favorite.delete"] = function(ctx)
    local req = ctx.req
    local fav_id = contract.param(req, "id") or contract.param(req, "favoriteId")
    if not fav_id then return missing(req, "id") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/favourite/w/batchdelete", body = { { id = tostring(fav_id) } },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- batch 端点 body 为裸数组
local function fav_batch(method, req)
    local items = contract.param(req, "items") or contract.param(req, "favorites")
    if type(items) ~= "table" or #items == 0 then return missing(req, "items") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/favourite/w/" .. method, body = items,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["favorite.batch_add"] = function(ctx) return fav_batch("batchinsert", ctx.req) end
M.routes["favorite.batch_update"] = function(ctx) return fav_batch("batchupdate", ctx.req) end
M.routes["favorite.batch_delete"] = function(ctx) return fav_batch("batchdelete", ctx.req) end

return M
