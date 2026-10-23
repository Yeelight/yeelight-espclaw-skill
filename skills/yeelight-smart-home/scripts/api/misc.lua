-- api/misc.lua：传感器/能耗/天气/消息/升级/AI语音/地理区域（v1 只读辅助域）
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

-- ---- 传感器 ----
M.routes["sensor.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = { houseId = house_id }
    local room_id = contract.param(req, "roomId")
    if room_id then body.roomId = tostring(room_id) end
    local data, resp2 = common.call(req, { method = "POST", path = "/v1/device/r/sensors", body = body })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["sensor.event.list"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local body = { deviceId = tostring(device_id) }
    local data, resp2 = common.call(req, { method = "POST", path = "/v1/sensor/r/events", body = body })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["sensor.event.write"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local event = contract.param(req, "event")
    if not device_id or type(event) ~= "table" then return missing(req, "deviceId/event") end
    local body = util.merge(event, { deviceId = tostring(device_id) })
    local data, resp2 = common.call(req, { method = "POST", path = "/v1/sensor/w/events", body = body })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- ---- 能耗 / 天气 ----
M.routes["device.energy.summary"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v1/energy/devices/" .. util.url_escape(tostring(device_id)) .. "/r/summary",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { energy = data.data or data })
end

M.routes["device.weather.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local query_type = contract.param(req, "queryType") or "default"
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/weather/r/" .. util.url_escape(tostring(device_id))
            .. "/" .. util.url_escape(tostring(query_type)) .. "/queryWeather",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { weather = data.data or data })
end

-- ---- 消息中心 ----
M.routes["message.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v1/messagecenter/r/messages/" .. (contract.param(req, "pageNo") or 1)
            .. "/" .. (contract.param(req, "pageSize") or 20),
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    local summary = common.top_n(rows)
    return contract.success(req, "ok",
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

-- ---- 升级（只读） ----
M.routes["upgrade.file.list"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/upgrade/r/listfile", body = { deviceId = tostring(device_id) },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["upgrade.file.batch_list"] = function(ctx)
    local req = ctx.req
    local device_ids = contract.param(req, "deviceIds")
    if type(device_ids) ~= "table" then return missing(req, "deviceIds") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/upgrade/r/listfile/batch", body = { deviceIds = device_ids },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["upgrade.progress.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/upgrade/r/progress", body = { deviceId = tostring(device_id) },
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { progress = data.data or data })
end

M.routes["progress.get"] = function(ctx)
    local req = ctx.req
    local task_id = contract.param(req, "taskId")
    if not task_id then return missing(req, "taskId") end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/progress/r/" .. util.url_escape(tostring(task_id)),
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { progress = data.data or data })
end

M.routes["app_upgrade.latest.get"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/app/upgrade/r/latest",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { appUpgrade = data.data or data })
end

M.routes["ota.version_file.batch_list"] = function(ctx)
    local req = ctx.req
    local pids = contract.param(req, "pids")
    if type(pids) ~= "table" then return missing(req, "pids") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/ota/r/version_file/batch", body = { pids = pids },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- ---- AI 语音 ----
M.routes["ai_voice.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/aivoice/r/list", body = {},
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["ai_voice.product.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/aivoice/r/product/list", body = {},
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- ---- 地理区域（house-independent） ----
M.routes["geo_area.children.list"] = function(ctx)
    local req = ctx.req
    local parent_id = contract.param(req, "parentId") or 0
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/geo/area/" .. util.url_escape(tostring(parent_id)) .. "/r/children",
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["geo_area.search"] = function(ctx)
    local req = ctx.req
    local keyword = contract.param(req, "keyword")
    if not keyword then return missing(req, "keyword") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/geo/area/r/search", body = { keyword = tostring(keyword) },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- ---- 设备槽位 ----
M.routes["device.slot.create"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local slot = contract.param(req, "slot")
    if not device_id or type(slot) ~= "table" then return missing(req, "deviceId/slot") end
    local body = util.merge(slot, { deviceId = tostring(device_id) })
    local data, resp2 = common.call(req, { method = "POST", path = "/v1/device/w/slot", body = body })
    if not data then return resp2 end
    return contract.success(req, i18n.t("ok", req.locale), { slot = data.data or data })
end

return M
