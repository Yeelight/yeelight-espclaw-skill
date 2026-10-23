-- api/diagnose.lua：诊断域（diagnose.device/gateway/scene/automation、automation.explain/capabilities）
-- 本地组装：entity + capabilities + state + gateway detail -> 结构化结论。
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local device_api = require("api.device")
local write_verify = require("write_verify")
local topology = require("topology")

local M = {}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

M.routes["diagnose.device"] = function(ctx)
    local req = ctx.req
    local resolved = device_api.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local item = resolved.items[1]
    if not item then return missing(req, "device") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local findings = {}
    -- 1) 读当前状态
    local ok, props, err = write_verify.read_properties(write_verify.NODE_TYPE.device, item.id,
        { house_id = house_id })
    if not ok then
        findings[#findings + 1] = { level = "error", check = "state_query",
            message = "cannot read device state: " .. tostring(err and err.code) }
    else
        local power = props["p"]
        if power == false or power == 0 or power == "false" then
            findings[#findings + 1] = { level = "info", check = "power",
                message = "device power is off" }
        end
    end
    -- 2) 在线状态（拓扑）
    local topo_ok, topo = topology.load({})
    if topo_ok then
        for _, d in ipairs(topo.devices) do
            if d.id == item.id then
                if d.online == false then
                    findings[#findings + 1] = { level = "warn", check = "online",
                        message = "device offline in topology" }
                end
            end
        end
    end
    if #findings == 0 then
        findings[#findings + 1] = { level = "ok", check = "basic",
            message = "device reachable and powered" }
    end
    return contract.success(req, "diagnosis complete",
        { deviceId = item.id, deviceName = item.name, findings = findings })
end

M.routes["diagnose.gateway"] = function(ctx)
    local req = ctx.req
    local gateway_id = contract.param(req, "gatewayId")
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id)
            .. (gateway_id and ("/gateway/" .. util.url_escape(tostring(gateway_id)) .. "/r/info")
                or "/gateway/r/info/1/100"),
    })
    if not data then return resp2 end
    return contract.success(req, "gateway diagnosis summary", { gateways = data.data or data })
end

M.routes["diagnose.scene"] = function(ctx)
    local req = ctx.req
    local scene_id = contract.param(req, "sceneId")
    if not scene_id then return missing(req, "sceneId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/scene/" .. util.url_escape(tostring(scene_id)) .. "/r/detail", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "scene diagnosis summary", { scene = data.data or data })
end

M.routes["diagnose.automation"] = function(ctx)
    local req = ctx.req
    local automation_id = contract.param(req, "automationId")
    if not automation_id then return missing(req, "automationId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id)
            .. "/automation/" .. util.url_escape(tostring(automation_id)) .. "/r/info",
    })
    if not data then return resp2 end
    return contract.success(req, "automation diagnosis summary", { automation = data.data or data })
end

M.routes["automation.explain"] = function(ctx)
    return M.routes["diagnose.automation"](ctx)
end

M.routes["automation.capabilities"] = function(ctx)
    local req = ctx.req
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/automations/r/capabilities", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { capabilities = data.data or data })
end

return M
