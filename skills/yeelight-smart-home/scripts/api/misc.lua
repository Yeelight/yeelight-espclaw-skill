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
    local path = event.test == true and "/v1/sensor/w/test" or "/v1/sensor/w/insert"
    local data, resp2 = common.call(req, { method = "POST", path = path, body = body })
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
        method = "GET", path = "/v1/messagecenter/r/messages",
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
        method = "POST", path = "/v1/upgrade/r/batchlistfile", body = { deviceIds = device_ids },
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
        method = "POST", path = "/v1/progress/r/" .. util.url_escape(tostring(task_id)), body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { progress = data.data or data })
end

M.routes["app_upgrade.latest.get"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/appupgrade/r/latestfile", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { appUpgrade = data.data or data })
end

M.routes["ota.version_file.batch_list"] = function(ctx)
    local req = ctx.req
    local pids = contract.param(req, "pids")
    if type(pids) ~= "table" then return missing(req, "pids") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/ota/upgrade/r/batchListFilesByVersion", body = { pids = pids },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- ---- AI 语音 ----
-- ai_voice.list：Runtime 明确为 partial（涉及第三方凭据安全边界），只返回指引
M.routes["ai_voice.list"] = function(ctx)
    local req = ctx.req
    return contract.make(req, contract.STATUSES.BLOCKED,
        i18n.t("blocked", req.locale, "AI voice account binding involves third-party credentials"),
        nil, {
            clarification = {
                question = "AI 语音账号能力涉及第三方凭据，请勿在对话中粘贴第三方语音账号、密码或 token；绑定请使用官方 App。",
                guidance = { "不要在对话中粘贴第三方语音账号、密码或 token。",
                    "需要绑定或修改时使用官方 App。" },
            },
        })
end

-- ai_voice.product.list：GET /v1/ai/voice/product/r/list
M.routes["ai_voice.product.list"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/ai/voice/product/r/list",
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- ---- 地理区域（house-independent） ----
M.routes["geo_area.children.list"] = function(ctx)
    local req = ctx.req
    local parent_id = contract.param(req, "parentId")
    if not parent_id then return missing(req, "parentId") end
    local data, resp2 = common.call(req, {
        method = "GET", path = "/v1/area/r/" .. util.url_escape(tostring(parent_id)) .. "/children",
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["geo_area.search"] = function(ctx)
    local req = ctx.req
    local name = contract.param(req, "keyword") or contract.param(req, "name")
    if not name then return missing(req, "keyword") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/area/r/areas", body = { name = tostring(name) },
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

return M
