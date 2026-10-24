-- api/lighting.lua：灯光设计（lighting.design.plan/apply，本地编排 + 控制端点）
-- design.import 依赖 /v1/meta/import（stretch，v1 暂不实现）。
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local device_api = require("api.device")
local topology = require("topology")
local name_match = require("name_match")

local M = {}

-- 场景模板：语义 -> {power, brightness, color_temperature}
M.PRESETS = {
    ["reading"] = { brightness = 100, color_temperature = 5000 },
    ["阅读"] = { brightness = 100, color_temperature = 5000 },
    ["movie"] = { brightness = 15, color_temperature = 2700 },
    ["观影"] = { brightness = 15, color_temperature = 2700 },
    ["relax"] = { brightness = 40, color_temperature = 3300 },
    ["放松"] = { brightness = 40, color_temperature = 3300 },
    ["work"] = { brightness = 90, color_temperature = 5500 },
    ["工作"] = { brightness = 90, color_temperature = 5500 },
    ["sleep"] = { brightness = 5, color_temperature = 2700 },
    ["睡眠"] = { brightness = 5, color_temperature = 2700 },
}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

M.routes = {}

-- 生成执行计划（不执行）
M.routes["lighting.design.plan"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local scene_name = params.scene or params.designName or params.name
    local plan = params.plan
    if type(plan) ~= "table" and scene_name then
        plan = M.PRESETS[tostring(scene_name):lower()] or M.PRESETS[tostring(scene_name)]
    end
    if type(plan) ~= "table" then
        return missing(req, "scene(reading/movie/relax/work/sleep) or plan")
    end
    local resolved = device_api.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local steps = {}
    for _, item in ipairs(resolved.items) do
        for prop, value in pairs(plan) do
            steps[#steps + 1] = {
                targetId = item.id, targetName = item.name, nodeType = item.nodeType,
                property = prop, value = value,
            }
        end
    end
    return contract.success(req, "plan ready (not executed)", {
        dryRun = true, steps = steps,
        hint = "run lighting.design.apply with parameters.confirmed=true to execute",
    })
end

-- 执行计划：逐设备逐属性写 + 验证
M.routes["lighting.design.apply"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local plan = params.plan
    local scene_name = params.scene or params.designName or params.name
    if type(plan) ~= "table" and scene_name then
        plan = M.PRESETS[tostring(scene_name):lower()] or M.PRESETS[tostring(scene_name)]
    end
    if type(plan) ~= "table" then return missing(req, "scene or plan") end
    if not params.confirmed then
        local msg = i18n.t("need_confirm", req.locale, "lighting.design.apply")
        return contract.make(req, contract.STATUSES.BLOCKED, msg, nil,
            { clarification = { question = msg, requiresConfirmation = true } })
    end
    -- plan 属性过可写白名单（与 node.property.set 同等防线）
    local risk = require("risk")
    for prop, _ in pairs(plan) do
        if type(prop) == "string" and not risk.WRITABLE_PROPS[prop:lower()] then
            return contract.blocked(req, i18n.t("blocked", req.locale,
                "property '" .. prop .. "' not writable"))
        end
    end
    local resolved = device_api.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local ok_items, failed = {}, {}
    for _, item in ipairs(resolved.items) do
        local item_ok = true
        for prop, value in pairs(plan) do
            local semantic = prop
            local ok = device_api.write_property(req, item, prop, value, "set")
            if ok then
                local verified = device_api.verify_target(req, item, semantic, value)
                if verified == false then item_ok = false end
            else
                item_ok = false
            end
        end
        if item_ok then ok_items[#ok_items + 1] = item.name else failed[#failed + 1] = item.name end
    end
    if #failed == 0 then
        return contract.success(req, i18n.t("light_set", req.locale, table.concat(ok_items, "、")),
            { applied = ok_items })
    end
    if #ok_items == 0 then
        return contract.partial(req, i18n.t("write_unverified", req.locale), { failed = failed })
    end
    return contract.partial(req,
        i18n.t("partial", req.locale, "failed: " .. table.concat(failed, "、")),
        { applied = ok_items, failed = failed })
end

M.routes["lighting.design.import"] = function(ctx)
    return contract.not_supported(ctx.req,
        i18n.t("not_supported", ctx.req.locale, "lighting.design.import (planned)"))
end

return M
