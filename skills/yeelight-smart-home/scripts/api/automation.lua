-- api/automation.lua：自动化域（automation.*、schedule_job.list）
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

M.routes["automation.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/automations/" .. util.url_escape(house_id) .. "/r/list/1/100",
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["automation.list.page"] = M.routes["automation.list"]
M.routes["automation.rule.list"] = M.routes["automation.list"]
M.routes["automation.supported.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/automations/r/list", body = { houseId = house_id },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end
M.routes["automation.supported.v2.list"] = M.routes["automation.supported.list"]

M.routes["automation.detail.get"] = function(ctx)
    local req = ctx.req
    local automation_id = contract.param(req, "automationId") or contract.param(req, "id")
    if not automation_id then return missing(req, "automationId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id)
            .. "/automation/" .. util.url_escape(tostring(automation_id)) .. "/r/info",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { automation = data.data or data })
end

M.routes["automation.create"] = function(ctx)
    local req = ctx.req
    local rule = contract.param(req, "automation") or contract.param(req, "rule")
    if type(rule) ~= "table" then return missing(req, "automation(rule payload)") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "PUT",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/automation/w/create",
        body = rule,
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale), { automation = data.data or data })
end

-- 全量替换
M.routes["automation.update"] = function(ctx)
    local req = ctx.req
    local automation_id = contract.param(req, "automationId") or contract.param(req, "id")
    local rule = contract.param(req, "automation") or contract.param(req, "rule")
    if not automation_id or type(rule) ~= "table" then return missing(req, "automationId/automation") end
    local body = util.merge(rule, { id = tostring(automation_id) })
    local data, resp2 = common.call(req, {
        method = "PUT", path = "/v1/automations/" .. util.url_escape(tostring(automation_id)) .. "/w/update",
        body = body,
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

local function automation_toggle(enable)
    return function(ctx)
        local req = ctx.req
        local automation_id = contract.param(req, "automationId") or contract.param(req, "id")
        if not automation_id then return missing(req, "automationId") end
        local data, resp2 = common.call(req, {
            method = "POST",
            path = "/v1/automations/w/" .. (enable and "enable" or "disable")
                .. "/" .. util.url_escape(tostring(automation_id)),
            body = {},
        })
        if not data then return resp2 end
        return contract.success(req, i18n.t("ok", req.locale))
    end
end

M.routes["automation.enable"] = automation_toggle(true)
M.routes["automation.disable"] = automation_toggle(false)

local function automation_delete(req)
    local automation_id = contract.param(req, "automationId") or contract.param(req, "id")
    if not automation_id then return missing(req, "automationId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "DELETE",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id)
            .. "/automation/" .. util.url_escape(tostring(automation_id)) .. "/w/info",
        body = {},
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["automation.delete"] = automation_delete
M.routes["automation.batch_delete"] = automation_delete

M.routes["schedule_job.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/schedulejob/r/list", body = { houseId = house_id },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

return M
