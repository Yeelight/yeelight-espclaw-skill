-- risk.lua：风险分级（R0-R3）、R3 确认、敏感属性拦截、可写属性白名单。
local contract = require("contract")
local i18n = require("i18n")

local M = {}

-- R3：必须聊天确认后带 parameters.confirmed=true 重发
M.R3_INTENTS = {
    ["home.delete"] = true,
    ["gateway.delete"] = true,
    ["device.remove"] = true,
    ["device.unbind"] = true,
    ["home.member.remove"] = true,
    ["home.member.transfer"] = true,
    ["home.member.quit"] = true,
    ["home.lock_all"] = true,
    ["home.unlock_all"] = true,
}

-- R2：改动型管理操作（dryRun 可预览）
M.R2_PREFIXES = {
    "home.create", "home.update", "home.property.set", "home.sort.configure",
    "room.", "area.", "group.", "scene.create", "scene.update", "scene.delete",
    "automation.", "device.rename", "device.move", "entity.rename.batch",
    "panel.", "knob.", "gateway.configure", "favorite.", "home.member.",
    "sensor.event.write", "device.slot.create", "operation.batch.configure",
}

-- 控制类写（R1）
M.CONTROL_PREFIXES = { "light.", "node.property", "node.action", "device.property" }

-- 敏感属性：读写一律拦截
M.SENSITIVE_PROPS = {
    ["password"] = true, ["passwd"] = true, ["token"] = true,
    ["secret"] = true, ["credential"] = true, ["auth"] = true,
    ["wifi_password"] = true, ["ssid_password"] = true, ["camera_stream"] = true,
    ["audio_stream"] = true, ["privacy_mode"] = true, ["location"] = true,
    ["gps"] = true, ["phone"] = true, ["mobile"] = true, ["email"] = true,
}

-- 可写属性白名单（控制命令只允许这些）
M.WRITABLE_PROPS = {
    ["p"] = true, ["l"] = true, ["c"] = true, ["ct"] = true, ["tp"] = true,
    ["power"] = true, ["brightness"] = true, ["color"] = true,
    ["color_temperature"] = true, ["curtain_position"] = true,
    ["fan_speed"] = true, ["mode"] = true, ["volume"] = true,
}

function M.risk_of(intent)
    if M.R3_INTENTS[intent] then return "R3" end
    for _, prefix in ipairs(M.R2_PREFIXES) do
        if intent:sub(1, #prefix) == prefix then return "R2" end
    end
    for _, prefix in ipairs(M.CONTROL_PREFIXES) do
        if intent:sub(1, #prefix) == prefix then return "R1" end
    end
    return "R0"
end

function M.is_write(intent)
    return M.risk_of(intent) ~= "R0"
end

-- R3 确认检查：未确认 -> SkillResponse(blocked)
function M.check_confirmation(req)
    if M.risk_of(req.intent) ~= "R3" then return nil end
    local confirmed = req.parameters and req.parameters.confirmed
    if not confirmed then
        local msg = i18n.t("need_confirm", req.locale, req.intent)
        return contract.make(req, contract.STATUSES.BLOCKED, msg, nil, {
            clarification = { question = msg, requiresConfirmation = true },
        })
    end
    return nil
end

-- 属性名/参数名敏感检查
function M.check_sensitive_prop(req)
    local params = req.parameters or {}
    for _, key in ipairs({ "prop", "propName", "property", "propertyName" }) do
        local name = params[key]
        if type(name) == "string" and M.SENSITIVE_PROPS[name:lower()] then
            return contract.blocked(req, i18n.t("sensitive_prop", req.locale, name))
        end
    end
    return nil
end

-- 控制命令可写属性白名单检查（node.property.set / device.property.set）
function M.check_writable_prop(req)
    local intent = req.intent
    if intent ~= "node.property.set" and intent ~= "device.property.set"
        and intent ~= "node.properties.set" and intent ~= "node.property.batch_set" then
        return nil
    end
    local params = req.parameters or {}
    local names = {}
    if params.prop then names[#names + 1] = params.prop end
    if params.propName then names[#names + 1] = params.propName end
    if type(params.properties) == "table" then
        for _, p in ipairs(params.properties) do
            names[#names + 1] = type(p) == "table" and (p.prop or p.propName) or p
        end
    end
    for _, name in ipairs(names) do
        if type(name) == "string" and not M.WRITABLE_PROPS[name:lower()] then
            return contract.blocked(req, i18n.t("blocked", req.locale,
                "property '" .. name .. "' not writable"))
        end
    end
    return nil
end

-- 综合拦截；返回 SkillResponse 或 nil（放行）
function M.guard(req)
    local r = M.check_confirmation(req)
    if r then return r end
    r = M.check_sensitive_prop(req)
    if r then return r end
    r = M.check_writable_prop(req)
    if r then return r end
    return nil
end

return M
