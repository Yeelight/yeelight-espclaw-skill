-- target_resolver.lua：intent + parameters -> 目标实体列表；歧义即 clarification。
local util = require("util")
local name_match = require("name_match")
local topology = require("topology")
local contract = require("contract")
local i18n = require("i18n")

local M = {}

M.NODE_TYPE = { room = 1, device = 2, area = 3, group = 4, home = 5 }

-- intent 前缀 -> 目标类型
local INTENT_KIND = {
    ["light."] = "device",
    ["device."] = "device",
    ["entity."] = "device",
    ["node."] = "device",
    ["room."] = "room",
    ["area."] = "area",
    ["group."] = "group",
    ["scene."] = "scene",
    ["home."] = "home",
    ["gateway."] = "gateway",
    ["state."] = "device",
    ["diagnose."] = "device",
}

function M.kind_of(intent)
    for prefix, kind in pairs(INTENT_KIND) do
        if intent:sub(1, #prefix) == prefix then return kind end
    end
    return nil
end

-- 从 req.targets / parameters 提取显式目标
local function explicit_targets(req)
    local out = {}
    local params = req.parameters or {}
    if type(req.targets) == "table" then
        for _, t in ipairs(req.targets) do
            if type(t) == "table" and (t.id or t.deviceId or t.name) then
                out[#out + 1] = t
            end
        end
    end
    if params.deviceId then out[#out + 1] = { id = tostring(params.deviceId) } end
    if params.groupId then out[#out + 1] = { id = tostring(params.groupId) } end
    if params.roomId then out[#out + 1] = { id = tostring(params.roomId) } end
    return out
end

-- 在设备列表中按 roomName + deviceName 匹配
local function match_devices(req, topo)
    local params = req.parameters or {}
    local devices = topo.devices or {}
    local room_scope = params.roomName
    local pool = devices
    if room_scope and room_scope ~= "" and room_scope ~= "全屋" then
        local m = name_match.match_one(room_scope, topo.rooms or {})
        if m.status == "exact" then
            local rid = tostring(m.item.id or m.item.roomId)
            pool = {}
            for _, d in ipairs(devices) do
                if d.roomId == rid then pool[#pool + 1] = d end
            end
        elseif m.status == "ambiguous" then
            return { status = "ambiguous", candidates = m.candidates, kind = "room" }
        else
            return { status = "not_found", kind = "room", query = room_scope }
        end
    end
    local device_name = params.deviceName or params.name
    if not device_name or device_name == "" then
        return { status = "ok", targets = pool }   -- 整个范围（房间/全屋）
    end
    local m = name_match.match_one(device_name, pool)
    if m.status == "exact" then
        return { status = "ok", targets = { m.item } }
    elseif m.status == "ambiguous" then
        return { status = "ambiguous", candidates = m.candidates, kind = "device" }
    end
    return { status = "not_found", kind = "device", query = device_name }
end

local function match_in(kind, req, topo)
    local params = req.parameters or {}
    local query = params.deviceName or params.name
    if kind == "scene" then query = params.sceneName or params.name end
    if kind == "room" then query = params.roomName or params.name end
    if kind == "area" then query = params.areaName or params.name end
    if kind == "group" then query = params.groupName or params.name end
    if kind == "home" then query = params.homeName or params.name end
    local pool = topo.devices
    if kind == "room" then pool = topo.rooms end
    if kind == "group" then pool = topo.groups end
    if not query then
        return { status = "missing", kind = kind }
    end
    local m = name_match.match_one(query, pool)
    if m.status == "exact" then return { status = "ok", targets = { m.item } } end
    if m.status == "ambiguous" then return { status = "ambiguous", candidates = m.candidates, kind = kind } end
    return { status = "not_found", kind = kind, query = query }
end

-- 主入口：返回
--   {status="ok", targets={...}}
--   {status="missing"|"not_found"|"ambiguous", ...}
-- 失败时可直接用 M.to_clarification(req, resolved) 生成 SkillResponse。
function M.resolve(req, opts)
    opts = opts or {}
    local kind = opts.kind or M.kind_of(req.intent)
    local explicit = explicit_targets(req)
    if #explicit > 0 then
        local targets = {}
        for _, t in ipairs(explicit) do
            targets[#targets + 1] = { id = tostring(t.id or t.deviceId), name = t.name }
        end
        return { status = "ok", targets = targets, explicit = true }
    end
    local ok, topo, terr = topology.load(opts)
    if not ok then
        return { status = "error", error = terr }
    end
    local params = req.parameters or {}
    if kind == "device" then
        return match_devices(req, topo)
    elseif kind == "room" or kind == "scene" or kind == "group" or kind == "area" or kind == "home" then
        return match_in(kind, req, topo)
    end
    return { status = "ok", targets = {}, no_resolve = true }
end

function M.to_clarification(req, resolved)
    local locale = req.locale
    if resolved.status == "ambiguous" then
        local labels = name_match.candidate_labels(resolved.candidates)
        local query = resolved.query or (req.parameters and (req.parameters.deviceName or req.parameters.roomName)) or ""
        local clar = {
            question = i18n.t("ambiguous", locale, query, #resolved.candidates, labels),
            candidates = {},
        }
        for _, c in ipairs(resolved.candidates or {}) do
            clar.candidates[#clar.candidates + 1] = { id = c.id, name = c.name, roomName = c.roomName }
        end
        return contract.clarification(req, clar.question, clar)
    end
    if resolved.status == "not_found" then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", locale, tostring(resolved.query or "")),
            nil, { clarification = { question = i18n.t("not_found", locale, tostring(resolved.query or "")) } })
    end
    if resolved.status == "missing" then
        local key = resolved.kind == "scene" and "sceneName" or (resolved.kind == "room" and "roomName" or "deviceName")
        local msg = i18n.t("missing_param", locale, key)
        return contract.make(req, contract.STATUSES.CLARIFICATION, msg, nil,
            { clarification = { question = msg } })
    end
    if resolved.status == "error" then
        return contract.error(req, "topology load failed: " .. tostring(resolved.error and resolved.error.code))
    end
    return nil
end

return M
