-- api/panel.lua：面板域（panel.*、screen.control.list）
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

M.routes["panel.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/panel/r/list/" .. util.url_escape(house_id),
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["screen.control.list"] = M.routes["panel.list"]

M.routes["panel.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "panelId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/panel/r/detail/" .. util.url_escape(tostring(device_id)), body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { panel = data.data or data })
end

M.routes["panel.button.type.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/panel/r/button_type/" .. util.url_escape(tostring(device_id)), body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { buttonTypes = data.data or data })
end

-- 先读后写（merge）：读当前按键配置 -> merge -> 更新
M.routes["panel.button.configure"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local button = contract.param(req, "button")
    if not device_id or type(button) ~= "table" or button.index == nil then
        return missing(req, "deviceId/button(index,...)")
    end
    local current, resp = M.routes["panel.get"]({ req = req })
    if current.status ~= contract.STATUSES.SUCCESS then return current, resp end
    local buttons = (current.result and current.result.panel and current.result.panel.buttons) or {}
    local merged = {}
    for _, b in ipairs(buttons) do
        if tostring(b.index) == tostring(button.index) then
            for k, v in pairs(button) do b[k] = v end
        end
        merged[#merged + 1] = b
    end
    local found = false
    for _, b in ipairs(merged) do
        if tostring(b.index) == tostring(button.index) then found = true end
    end
    if not found then merged[#merged + 1] = button end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/panel/w/button/update/" .. util.url_escape(tostring(device_id)),
        body = { buttons = merged },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["panel.button_event.update"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local event = contract.param(req, "event")
    if not device_id or type(event) ~= "table" then return missing(req, "deviceId/event") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/panel/w/button_event/update/" .. util.url_escape(tostring(device_id)),
        body = event,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["panel.button_event.batch_update"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local events = contract.param(req, "events")
    if not device_id or type(events) ~= "table" then return missing(req, "deviceId/events") end
    local failed = {}
    for _, e in ipairs(events) do
        local ok = common.call(req, {
            method = "POST",
            path = "/v1/panel/w/button_event/update/" .. util.url_escape(tostring(device_id)),
            body = e,
        })
        if not ok then failed[#failed + 1] = tostring(type(e) == "table" and (e.index or "?") or e) end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["panel.button_event.reset"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/panel/w/button_event/reset/" .. util.url_escape(tostring(device_id)),
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- panel.click：按 index 执行按键动作（走面板 action）
M.routes["panel.click"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local index = contract.param(req, "index")
    if not device_id or index == nil then return missing(req, "deviceId/index") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/panel/w/click/" .. util.url_escape(tostring(device_id))
            .. "/" .. util.url_escape(tostring(index)),
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

return M
