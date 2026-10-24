-- api/home.lua：家庭域（home.*、account.info、home.member.*、geo_area.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local auth = require("auth")
local common = require("api.common")

local M = {}

local function home_rows(data)
    -- /v1/house/r/list -> data 里的家庭列表容器名兼容
    local d = type(data) == "table" and (data.data or data) or {}
    if util.is_array(d) then return d end
    for _, key in ipairs({ "houses", "houseList", "rows", "list", "projects" }) do
        if type(d[key]) == "table" and #d[key] > 0 then return d[key] end
    end
    if d.id or d.houseId then return { d } end
    return {}
end

M.routes = {}

M.routes["home.list"] = function(ctx)
    local req = ctx.req
    local data, resp = common.call(req, { method = "POST", path = "/v1/house/r/list", body = {} })
    if not data then return resp end
    local rows = home_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req,
        i18n.t("home_list", req.locale, #rows, common.name_list(summary.items)),
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["home.summary"] = function(ctx)
    return M.routes["home.list"](ctx)
end

M.routes["home.search"] = function(ctx)
    local req = ctx.req
    local word = contract.param(req, "keyword") or contract.param(req, "name") or ""
    local data, resp = common.call(req, { method = "POST", path = "/v1/house/r/list", body = {} })
    if not data then return resp end
    local matched = {}
    for _, h in ipairs(home_rows(data)) do
        local name = tostring(h.name or "")
        if word == "" or name:find(word, 1, true) then matched[#matched + 1] = h end
    end
    return contract.success(req,
        i18n.t("home_list", req.locale, #matched, common.name_list(matched)),
        { total = #matched, items = common.top_n(matched).items })
end

M.routes["account.info"] = function(ctx)
    local req = ctx.req
    local creds, why = auth.require_credentials()
    if not creds then
        return contract.auth_required(req, i18n.t(why == "auth_expired" and "auth_expired" or "not_bound", req.locale))
    end
    local info = {}
    local ok, data = pcall(function()
        local http = require("http")
        local _, d = http.request({
            method = "GET", base = auth.account_base(creds.region),
            path = "/apis/account/user/info",
        })
        return d
    end)
    if ok and type(data) == "table" then
        local d = data.data or data
        info = { nickname = d.nickname or d.name, uid = d.uid }
    end
    -- 不回传任何 token 字段
    info.region = creds.region
    info.houseId = creds.house_id
    info.bizType = creds.biz_type
    return contract.success(req, "ok", info)
end

M.routes["home.detail.get"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/house/" .. util.url_escape(house_id) .. "/r/info",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { detail = data.data or data })
end

M.routes["home.stat.get"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/house/" .. util.url_escape(house_id) .. "/r/stat", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { stat = data.data or data })
end

M.routes["home.property.get"] = function(ctx)
    return M.routes["home.stat.get"](ctx)
end

M.routes["home.create"] = function(ctx)
    local req = ctx.req
    local name = contract.param(req, "name")
    if not name then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("missing_param", req.locale, "name"))
    end
    local data, resp = common.call(req, {
        method = "PUT", path = "/v2/thing/manage/house/w/create",
        body = { name = tostring(name) },
    })
    if not data then return resp end
    return contract.success(req, i18n.t("ok", req.locale), { house = data.data or data })
end

M.routes["home.update"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = {}
    for _, k in ipairs({ "name", "icon", "desc" }) do
        local v = contract.param(req, k)
        if v ~= nil then body[k] = v end
    end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/w/modify",
        body = body,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["home.delete"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/house/" .. util.url_escape(house_id) .. "/w/delete", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["home.lock_all"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/house/" .. util.url_escape(house_id) .. "/lockall", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["home.unlock_all"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/house/" .. util.url_escape(house_id) .. "/unlockall", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- 成员列表：POST /v1/house/r/memberlistV2 {houseId}
M.routes["home.member.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/house/r/memberlistV2", body = { houseId = house_id },
    })
    if not data then return resp2 end
    local d = data.data or data
    local rows = util.is_array(d) and d or (d.members or d.rows or {})
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end
M.routes["home.member.current.get"] = M.routes["home.member.list"]

-- 成员管理（R3 由 risk.guard 拦截确认）
-- Runtime 语义：固定路径 POST，body = payload 字段 + houseId
local function member_action(path, req, required_key)
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = { houseId = house_id }
    local params = req.parameters or {}
    for _, k in ipairs({ "memberId", "userId", "uid", "userRole", "role",
        "shareId", "createTime", "toUID", "targetHouseId", "capability" }) do
        local v = params[k]
        if v ~= nil then body[k] = v end
    end
    if required_key and not body[required_key] then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("missing_param", req.locale, required_key))
    end
    local data, resp2 = common.call(req, { method = "POST", path = path, body = body })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale), { result = data.data or data })
end

M.routes["home.member.invite"] = function(ctx)
    return member_action("/v1/share/r/housesharebarcode", ctx.req)
end
M.routes["home.member.accept_share"] = function(ctx)
    return member_action("/v1/share/w/acceptbarcodeshare", ctx.req, "shareId")
end
M.routes["home.member.configure"] = function(ctx)
    return member_action("/v1/house/w/updateUserRole", ctx.req, "memberId")
end
M.routes["home.member.remove"] = function(ctx)
    return member_action("/v1/house/w/remove", ctx.req, "memberId")
end
M.routes["home.member.transfer"] = function(ctx)
    return member_action("/v1/house/w/transfer", ctx.req, "memberId")
end
M.routes["home.member.quit"] = function(ctx)
    return member_action("/v1/house/w/quit", ctx.req, "uid")
end

M.routes["home.sort.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/sort/r/getSort", body = { houseId = house_id },
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { sort = data.data or data })
end

M.routes["home.sort.configure"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local sort_type = contract.param(req, "sortType")
    local target = contract.param(req, "target")
    if not sort_type or not target then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("missing_param", req.locale, "sortType/target"))
    end
    local items = contract.param(req, "items") or contract.param(req, "ids")
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/sort/" .. util.url_escape(house_id) .. "/w/" .. util.url_escape(tostring(sort_type))
            .. "/" .. util.url_escape(tostring(target)) .. "/add",
        body = { items = items },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- home.property.set：家庭节点属性写（nodeType=5，对齐 Runtime 语义）
M.routes["home.property.set"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local prop = params.prop or params.propName
    local value = params.value
    if not prop or value == nil then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("missing_param", req.locale, "prop/value"))
    end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    if params.dryRun == true then
        return contract.success(req, "dry run only",
            { dryRun = true, plan = { nodeType = 5, nodeId = house_id, property = prop, value = value } })
    end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/open/control/house/" .. util.url_escape(house_id)
            .. "/control/5/" .. util.url_escape(house_id) .. "/w/properties/"
            .. util.url_escape(tostring(prop)),
        body = { value = value },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale), { property = prop })
end

return M
