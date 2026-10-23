-- api/panel.lua：面板域（panel.*、screen.control.list）
-- 端点基线（yeelight-home Runtime）：
--   panel.list        GET  /v1/panel/r/list/{houseId}
--   panel.get         POST /v1/panel/r/detail/{deviceId}
--   button.type.get   POST /v1/panel/r/button/info/{deviceId}[/{buttonType}]
--   button.configure  POST /v1/panel/w/button/update/{deviceId}
--   button_event.*    POST /v1/panel/w/button/event/update | update/batch | {id}/reset
--   panel.click       POST /v2/thing/control/panel/{resId}
--   screen.control    POST /v1/ai/{houseId}/control/r/info
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
    local button_type = contract.param(req, "buttonType")
    local path = "/v1/panel/r/button/info/" .. util.url_escape(tostring(device_id))
    if button_type then path = path .. "/" .. util.url_escape(tostring(button_type)) end
    local data, resp2 = common.call(req, { method = "POST", path = path, body = {} })
    if not data then return resp2 end
    return contract.success(req, "ok", { buttons = data.data or data })
end

-- 先读后写（merge）：读当前按键配置 -> merge -> 更新
M.routes["panel.button.configure"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local button = contract.param(req, "button")
    if not device_id or type(button) ~= "table" or button.index == nil then
        return missing(req, "deviceId/button(index,...)")
    end
    local current = M.routes["panel.get"]({ req = req })
    if current.status ~= contract.STATUSES.SUCCESS then return current end
    local panel = current.result and current.result.panel or {}
    local buttons = panel.buttons or panel.buttonList or {}
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
    local event = contract.param(req, "event")
    if type(event) ~= "table" then return missing(req, "event") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/panel/w/button/event/update", body = event,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["panel.button_event.batch_update"] = function(ctx)
    local req = ctx.req
    local events = contract.param(req, "events")
    if type(events) ~= "table" or #events == 0 then return missing(req, "events") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/panel/w/button/event/update/batch", body = { events = events },
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["panel.button_event.reset"] = function(ctx)
    local req = ctx.req
    local event_id = contract.param(req, "buttonEventId") or contract.param(req, "eventId")
    if not event_id then return missing(req, "buttonEventId") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/panel/w/button/event/" .. util.url_escape(tostring(event_id)) .. "/reset",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- panel.click：POST /v2/thing/control/panel/{resId}，payload 直传
M.routes["panel.click"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "resId")
    if not device_id then return missing(req, "deviceId") end
    local payload = {}
    for _, k in ipairs({ "index", "buttonIndex", "action", "event", "clickType" }) do
        local v = contract.param(req, k)
        if v ~= nil then payload[k] = v end
    end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v2/thing/control/panel/" .. util.url_escape(tostring(device_id)),
        body = payload,
    })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- 屏控制设备列表：POST /v1/ai/{houseId}/control/r/info
M.routes["screen.control.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/ai/" .. util.url_escape(house_id) .. "/control/r/info", body = {},
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

return M
