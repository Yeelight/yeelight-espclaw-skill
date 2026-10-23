-- api/device.lua：设备/实体/状态/灯控/节点属性域（最大的 v1 模块）。
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")
local write_verify = require("write_verify")

local M = {}

M.NODE_TYPE = write_verify.NODE_TYPE

local COLORS = {
    red = 16711680, ["红色"] = 16711680,
    green = 65280, ["绿色"] = 65280,
    blue = 255, ["蓝色"] = 255,
    white = 16777215, ["白色"] = 16777215,
    yellow = 16776960, ["黄色"] = 16776960,
    cyan = 65535, ["青色"] = 65535,
    purple = 16711935, magenta = 16711935, ["紫色"] = 16711935,
    orange = 16753920, ["橙色"] = 16753920,
}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

-- ---- 目标解析（控制写用，支持房间/灯组/全屋节点直写） ----
local function name_match_room(room_name, rooms)
    local m = require("name_match").match_one(room_name, rooms or {})
    if m.status == "exact" then
        return { id = m.item.id or m.item.roomId, name = m.item.name }
    end
    return nil
end

-- 返回 {ok=true, items={{id, nodeType, name}}} 或 {ok=false, resp=SkillResponse}
function M.resolve_control_targets(req)
    local params = req.parameters or {}
    local explicit = req.targets
    local items = {}
    if type(explicit) == "table" and #explicit > 0 then
        local ENTITY_NODE_TYPE = { room = 1, device = 2, area = 3, group = 4, home = 5 }
        for _, t in ipairs(explicit) do
            if type(t) == "table" and t.id then
                local node_type = tonumber(t.nodeType)
                if not node_type and type(t.entityType) == "string" then
                    node_type = ENTITY_NODE_TYPE[t.entityType:lower()]
                end
                items[#items + 1] = {
                    id = tostring(t.id),
                    nodeType = node_type or M.NODE_TYPE.device,
                    name = tostring(t.name or t.id),
                }
            end
        end
        if #items > 0 then return { ok = true, items = items } end
    end
    if params.deviceId then
        return { ok = true, items = { { id = tostring(params.deviceId), nodeType = M.NODE_TYPE.device, name = tostring(params.deviceName or params.deviceId) } } }
    end
    local ok, topo, terr = topology.load({})
    if not ok then
        return { ok = false, resp = common.err_response(req, terr) }
    end
    local device_name = params.deviceName or params.name
    local room_name = params.roomName
    local group_name = params.groupName
    local area_name = params.areaName
    if device_name and device_name ~= "" then
        local pool = topo.devices
        if room_name and room_name ~= "" and room_name ~= "全屋" then
            local m = name_match_room(room_name, topo.rooms)
            if not m then
                return { ok = false, resp = contract.make(req, contract.STATUSES.CLARIFICATION,
                    i18n.t("not_found", req.locale, tostring(room_name))) }
            end
            local rid = tostring(m.id)
            pool = {}
            for _, d in ipairs(topo.devices) do
                if d.roomId == rid then pool[#pool + 1] = d end
            end
        end
        local matches = require("name_match").rank(device_name, pool)
        if #matches == 0 then
            return { ok = false, resp = contract.make(req, contract.STATUSES.CLARIFICATION,
                i18n.t("not_found", req.locale, tostring(device_name))) }
        end
        local best = matches[1].score
        local top = {}
        for _, m in ipairs(matches) do
            if m.score == best then top[#top + 1] = m.item end
        end
        if #top > 1 then
            local labels = require("name_match").candidate_labels(top)
            local msg = i18n.t("ambiguous", req.locale, tostring(device_name), #top, labels)
            return { ok = false, resp = contract.clarification(req, msg, { question = msg, candidates = top }) }
        end
        return { ok = true, items = { { id = top[1].id, nodeType = M.NODE_TYPE.device, name = top[1].name } } }
    end
    if group_name and group_name ~= "" then
        local m = require("name_match").match_one(group_name, topo.groups)
        if m.status == "exact" then
            return { ok = true, items = { { id = m.item.id, nodeType = M.NODE_TYPE.mesh_group, name = m.item.name } } }
        end
        return { ok = false, resp = contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(group_name))) }
    end
    if area_name and area_name ~= "" then
        -- 区域节点需查 area 列表（不在拓扑缓存里），退化为区域下房间逐个控制暂不支持；先按区域节点直写
        return { ok = false, resp = contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_supported", req.locale, "area target control; use roomName or deviceName")) }
    end
    -- 房间 / 全屋
    if room_name and room_name ~= "" and room_name ~= "全屋" then
        local m = name_match_room(room_name, topo.rooms)
        if not m then
            return { ok = false, resp = contract.make(req, contract.STATUSES.CLARIFICATION,
                i18n.t("not_found", req.locale, tostring(room_name))) }
        end
        return { ok = true, items = { { id = tostring(m.id), nodeType = M.NODE_TYPE.room, name = m.name } } }
    end
    -- 全屋：home 节点
    local house_id, resp = common.require_house_id(req)
    if not house_id then return { ok = false, resp = resp } end
    return { ok = true, items = { { id = house_id, nodeType = M.NODE_TYPE.home, name = "全屋" } } }
end

-- ---- 通用控制写 ----
-- prop: "p"/"l"/"ct"/"c"/...；command: "set"|"adjust"|"toggle"
-- 返回 ok(bool), data|nil, err
function M.write_property(req, item, prop, value, command, extra)
    local house_id, resp = common.require_house_id(req)
    if not house_id then return false, nil, { code = "E_NO_HOUSE", resp = resp } end
    local body = { value = value }
    if command and command ~= "set" then body.command = command end
    if type(extra) == "table" then
        for _, k in ipairs({ "duration", "delay", "index", "category" }) do
            if extra[k] ~= nil then body[k] = extra[k] end
        end
    end
    local path
    if command == "toggle" then
        path = string.format("/v1/open/control/house/%s/control/%d/%s/w/properties/%s/toggle",
            util.url_escape(house_id), item.nodeType, util.url_escape(item.id), prop)
    elseif command == "adjust" then
        path = string.format("/v1/open/control/house/%s/control/%d/%s/w/properties/%s/adjust",
            util.url_escape(house_id), item.nodeType, util.url_escape(item.id), prop)
    else
        path = string.format("/v1/open/control/house/%s/control/%d/%s/w/properties/%s",
            util.url_escape(house_id), item.nodeType, util.url_escape(item.id), prop)
    end
    return require("http").request({ method = "POST", path = path, body = body })
end

-- 带写后验证的批量控制
-- 返回 SkillResponse
function M.control_and_verify(req, items, prop, semantic, expected, command, extra)
    local ok_items, failed = {}, {}
    for _, item in ipairs(items) do
        local ok, _, err = M.write_property(req, item, prop, expected, command, extra)
        if not ok then
            failed[#failed + 1] = { name = item.name, reason = err and err.code or "E_HTTP" }
        else
            local verified = true
            if command ~= "toggle" and expected ~= nil then
                local okv = M.verify_target(req, item, semantic, expected)
                if okv == false then verified = false end
            end
            if verified then
                ok_items[#ok_items + 1] = item.name
            else
                failed[#failed + 1] = { name = item.name, reason = "verify_failed" }
            end
        end
    end
    local ok_names = table.concat(ok_items, "、")
    if #failed == 0 then
        return contract.success(req, i18n.t("light_set", req.locale, ok_names), {
            verified = true, property = semantic, targets = ok_items,
        })
    end
    if #ok_items == 0 then
        local reason = failed[1] and failed[1].reason or ""
        if reason == "verify_failed" then
            return contract.make(req, contract.STATUSES.PARTIAL,
                i18n.t("write_unverified", req.locale), { property = semantic, failed = failed })
        end
        return common.err_response(req, { code = reason, message = "control failed" })
    end
    local parts = {}
    for _, f in ipairs(failed) do parts[#parts + 1] = f.name .. "(" .. f.reason .. ")" end
    return contract.partial(req,
        i18n.t("partial", req.locale, table.concat(parts, "、")),
        { verified = true, targets = ok_items, failed = failed })
end

function M.verify_target(req, item, semantic, expected)
    local opts = { house_id = common.require_house_id(req) }
    local ok, actual = write_verify.verify(item.nodeType, item.id, semantic, expected, opts)
    return ok, actual
end

-- ---- light.* ----
local function parse_power(params)
    -- 注意：power 可能为 false，不能用 or 兜底
    local v = params.power
    if v == nil then v = params.value end
    if v == nil then return nil end
    if type(v) == "boolean" then return v end
    local s = util.trim(tostring(v)):lower()
    if s == "true" or s == "on" or s == "open" or s == "1" or v == "开" or v == "打开" or v == "开启" then return true end
    if s == "false" or s == "off" or s == "close" or s == "0" or v == "关" or v == "关闭" then return false end
    return nil
end

local function parse_int(params, keys, min, max)
    for _, key in ipairs(keys) do
        local v = params[key]
        if v ~= nil then
            local n = util.to_int(v)
            if n == nil or n < min or n > max then return nil end
            return n
        end
    end
    return nil
end

local function parse_color(params)
    local v = params.color or params.value
    if v == nil then return nil end
    if type(v) == "number" then return util.to_int(v) end
    local s = util.trim(tostring(v))
    local named = COLORS[s:lower()] or COLORS[s]
    if named then return named end
    local hex = s:match("^#?(%x%x%x%x%x%x)$")
    if hex then return tonumber(hex, 16) end
    return nil
end

local function light_spec(intent)
    if intent == "light.power.set" then
        return { prop = "p", semantic = "power", kind = "power" }
    elseif intent == "light.brightness.set" then
        return { prop = "l", semantic = "brightness", kind = "int", min = 1, max = 100,
                 keys = { "brightness", "value" } }
    elseif intent == "light.brightness.adjust" then
        return { prop = "l", semantic = "brightness", kind = "adjust", min = -100, max = 100,
                 keys = { "delta", "step", "value" } }
    elseif intent == "light.color_temperature.set" then
        return { prop = "ct", semantic = "color_temperature", kind = "int", min = 2700, max = 6500,
                 keys = { "colorTemperature", "color_temperature", "value" } }
    elseif intent == "light.color_temperature.adjust" then
        return { prop = "ct", semantic = "color_temperature", kind = "adjust", min = -3800, max = 3800,
                 keys = { "delta", "step", "value" } }
    elseif intent == "light.color.set" then
        return { prop = "c", semantic = "color", kind = "color" }
    end
    return nil
end

local function run_light_intent(ctx)
    local req = ctx.req
    local spec = light_spec(req.intent)
    if not spec then return contract.not_supported(req, req.intent) end
    local params = req.parameters or {}
    local dry_run = params.dryRun == true
    local value
    if spec.kind == "power" then
        value = parse_power(params)
        if value == nil then return missing(req, "power(on/off)") end
    elseif spec.kind == "int" then
        value = parse_int(params, spec.keys, spec.min, spec.max)
        if value == nil then
            return contract.make(req, contract.STATUSES.CLARIFICATION,
                i18n.t("invalid_param", req.locale,
                    spec.keys[1] .. " (" .. spec.min .. "-" .. spec.max .. ")"))
        end
    elseif spec.kind == "adjust" then
        value = parse_int(params, spec.keys, spec.min, spec.max)
        if value == nil then
            return contract.make(req, contract.STATUSES.CLARIFICATION,
                i18n.t("invalid_param", req.locale, "delta"))
        end
    elseif spec.kind == "color" then
        value = parse_color(params)
        if value == nil then return missing(req, "color(#RRGGBB or name)") end
    end
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    if dry_run then
        local plan = {}
        for _, item in ipairs(resolved.items) do
            plan[#plan + 1] = { id = item.id, nodeType = item.nodeType, name = item.name,
                property = spec.prop, value = value, command = spec.kind == "adjust" and "adjust" or "set" }
        end
        return contract.success(req, "dry run only", { dryRun = true, plan = plan })
    end
    local extra = {}
    if params.duration then extra.duration = params.duration end
    if params.delay then extra.delay = params.delay end
    if params.index then extra.index = params.index end
    -- adjust 先读当前值，得到期望值用于验证
    local expected = value
    local before = {}
    if spec.kind == "adjust" then
        local house_id, resp = common.require_house_id(req)
        if not house_id then return resp end
        for _, item in ipairs(resolved.items) do
            local ok, props = write_verify.read_properties(item.nodeType, item.id, { house_id = house_id })
            local cur = props and util.to_int(props[spec.prop]) or nil
            before[item.id] = cur
            if cur == nil then
                return contract.make(req, contract.STATUSES.PARTIAL,
                    i18n.t("write_unverified", req.locale), { reason = "cannot read current value" })
            end
            local want = cur + value
            if want < 0 then want = 0 end
            -- 上限：亮度 100，色温 6500
            local cap = spec.prop == "l" and 100 or 6500
            if want > cap then want = cap end
            expected = want
        end
        -- 期望值按设备分别可能不同：改为逐设备执行
        local ok_items, failed = {}, {}
        for _, item in ipairs(resolved.items) do
            local want = (before[item.id] or 0) + value
            local cap = spec.prop == "l" and 100 or 6500
            local floor = spec.prop == "l" and 1 or 0
            if want > cap then want = cap end
            if want < floor then want = floor end
            -- adjust 端点传增量，验证用期望绝对值
            local okw = M.write_property(req, item, spec.prop, value, "adjust", extra)
            local verified = false
            if okw then
                verified = M.verify_target(req, item, spec.semantic, want)
            end
            if okw and verified then
                ok_items[#ok_items + 1] = item.name
            else
                failed[#failed + 1] = { name = item.name, reason = okw and "verify_failed" or "E_HTTP" }
            end
        end
        if #failed == 0 then
            return contract.success(req, i18n.t("light_set", req.locale, table.concat(ok_items, "、")),
                { verified = true, property = spec.semantic, targets = ok_items })
        end
        if #ok_items == 0 then
            return common.err_response(req, { code = failed[1].reason, message = "adjust failed" })
        end
        return contract.partial(req, i18n.t("partial", req.locale,
            table.concat(failed, "、")), { verified = true, targets = ok_items, failed = failed })
    end
    return M.control_and_verify(req, resolved.items, spec.prop, spec.semantic, expected,
        spec.kind == "power" and "set" or "set", extra)
end

M.routes = {}

for _, intent in ipairs({ "light.power.set", "light.brightness.set", "light.brightness.adjust",
    "light.color_temperature.set", "light.color_temperature.adjust", "light.color.set" }) do
    M.routes[intent] = run_light_intent
end

-- ---- node.* / device.property.set ----

M.routes["node.property.set"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local prop = params.prop or params.propName or params.property
    local value = params.value
    if not prop or value == nil then return missing(req, "prop/value") end
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    if params.dryRun == true then
        return contract.success(req, "dry run only",
            { dryRun = true, plan = { property = prop, value = value, targets = resolved.items } })
    end
    return M.control_and_verify(req, resolved.items, prop, prop, value, "set",
        { index = params.index, duration = params.duration, delay = params.delay })
end

M.routes["device.property.set"] = M.routes["node.property.set"]

M.routes["node.properties.set"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local props = params.properties
    if type(props) ~= "table" or #props == 0 then return missing(req, "properties") end
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local failed = {}
    for _, item in ipairs(resolved.items) do
        for _, p in ipairs(props) do
            local prop = type(p) == "table" and (p.prop or p.propName) or p
            local value = type(p) == "table" and p.value or params.value
            local ok = M.write_property(req, item, prop, value, "set")
            if not ok then failed[#failed + 1] = item.name .. ":" .. tostring(prop) end
        end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["node.property.batch_set"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local prop = params.prop or params.propName
    local node_ids = params.nodeIds
    if not prop or type(node_ids) ~= "table" or #node_ids == 0 then return missing(req, "prop/nodeIds") end
    local failed = {}
    for _, id in ipairs(node_ids) do
        local ok = M.write_property(req, { id = tostring(id), nodeType = M.NODE_TYPE.device },
            prop, params.value, "set")
        if not ok then failed[#failed + 1] = tostring(id) end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["node.property.toggle"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local prop = params.prop or params.propName or "p"
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local failed = {}
    for _, item in ipairs(resolved.items) do
        local ok = M.write_property(req, item, prop, nil, "toggle")
        if not ok then failed[#failed + 1] = item.name end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("light_set", req.locale, "toggle"))
end

M.routes["node.action.execute"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local action = params.action or params.actionName
    if not action then return missing(req, "action") end
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local failed = {}
    for _, item in ipairs(resolved.items) do
        local ok = M.write_property(req, item, action, params.args or params.params or {}, "set")
        if not ok then failed[#failed + 1] = item.name end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- ---- state / device / entity 读 ----
local function read_device_props(req, item)
    return write_verify.read_properties(M.NODE_TYPE.device, item.id,
        { house_id = common.require_house_id(req) })
end

M.routes["state.query"] = function(ctx)
    local req = ctx.req
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local item = resolved.items[1]
    if not item then return missing(req, "device") end
    local ok, props, err = read_device_props(req, item)
    if not ok then return common.err_response(req, err) end
    local parts = {}
    for prop, value in pairs(props) do parts[#parts + 1] = prop .. "=" .. tostring(value) end
    table.sort(parts)
    return contract.success(req,
        i18n.t("state_query", req.locale, item.name, table.concat(parts, ", ")),
        { deviceId = item.id, properties = props })
end

M.routes["state.batch.query"] = function(ctx)
    local req = ctx.req
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local results = {}
    for _, item in ipairs(resolved.items) do
        local ok, props = read_device_props(req, item)
        results[#results + 1] = { id = item.id, name = item.name,
            properties = ok and props or json.null, ok = ok }
    end
    return contract.success(req, "ok", { results = results })
end

M.routes["entity.list"] = function(ctx)
    local req = ctx.req
    local ok, topo, terr = topology.load({})
    if not ok then return common.err_response(req, terr) end
    local rows = topo.devices
    local summary = common.top_n(rows)
    return contract.success(req,
        i18n.t("entity_list", req.locale, #rows, #summary.items, common.name_list(summary.items)),
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["device.list"] = M.routes["entity.list"]

M.routes["entity.get"] = function(ctx)
    local req = ctx.req
    local ok, topo, terr = topology.load({})
    if not ok then return common.err_response(req, terr) end
    local id = contract.param(req, "id") or contract.param(req, "deviceId")
    local device
    if id then
        for _, d in ipairs(topo.devices) do
            if d.id == tostring(id) then device = d end
        end
    else
        local name = contract.param(req, "name") or contract.param(req, "deviceName")
        local m = require("name_match").match_one(name, topo.devices)
        device = m.status == "exact" and m.item or nil
        if m.status == "ambiguous" then
            local msg = i18n.t("ambiguous", req.locale, tostring(name), #m.candidates,
                require("name_match").candidate_labels(m.candidates))
            return contract.clarification(req, msg, { question = msg, candidates = m.candidates })
        end
    end
    if not device then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(id or contract.param(req, "name") or "")))
    end
    return contract.success(req, "ok", { device = device })
end

M.routes["entity.capabilities"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "id")
    if not device_id then return missing(req, "deviceId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v2/thing/schema/house/" .. util.url_escape(house_id)
            .. "/device/r/info/1/100?crop=false",
    })
    if not data then return resp2 end
    -- 全量实体 schema 中过滤目标设备
    local rows = topology.extract_rows(data)
    local caps = {}
    for _, r in ipairs(rows) do
        if tostring(r.id or r.deviceId) == tostring(device_id) then caps[#caps + 1] = r end
    end
    return contract.success(req, "ok", { deviceId = tostring(device_id), capabilities = caps })
end

M.routes["device.detail.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "id")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/" .. util.url_escape(tostring(device_id)) .. "/r/detail", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { device = data.data or data })
end

M.routes["device.complex.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "id")
    if not device_id then return missing(req, "deviceId") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "GET",
        path = "/v2/thing/manage/house/" .. util.url_escape(house_id)
            .. "/device/" .. util.url_escape(tostring(device_id)) .. "/r/complex",
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { complex = data.data or data })
end

M.routes["device.shadow.get"] = M.routes["device.detail.get"]

M.routes["device.attr.list"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local body = {}
    if device_id then body.ids = tostring(device_id) end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/r/attrs", body = body,
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

-- ---- 设备管理（R2/R3） ----
M.routes["device.rename"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "id")
    local name = contract.param(req, "name") or contract.param(req, "deviceName")
    if not device_id or not name then return missing(req, "deviceId/name") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/" .. util.url_escape(tostring(device_id)) .. "/w/update",
        body = { name = tostring(name) },
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["device.move"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId")
    local room_id = contract.param(req, "roomId") or contract.param(req, "toRoomId")
    if not device_id or not room_id then return missing(req, "deviceId/roomId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/" .. util.url_escape(tostring(device_id)) .. "/w/update",
        body = { roomId = tostring(room_id) },
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["device.move_room.batch"] = function(ctx)
    local req = ctx.req
    local device_ids = contract.param(req, "deviceIds")
    local room_id = contract.param(req, "roomId")
    if type(device_ids) ~= "table" or not room_id then return missing(req, "deviceIds/roomId") end
    local failed = {}
    for _, id in ipairs(device_ids) do
        local ok = common.call(req, {
            method = "POST", path = "/v1/device/" .. util.url_escape(tostring(id)) .. "/w/update",
            body = { roomId = tostring(room_id) },
        })
        if not ok then failed[#failed + 1] = tostring(id) end
    end
    topology.invalidate()
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

local function device_remove(req, suffix)
    local device_id = contract.param(req, "deviceId") or contract.param(req, "id")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = suffix == "unbind" and "POST" or "DELETE",
        path = "/v1/device/" .. util.url_escape(tostring(device_id)) .. "/w/" .. suffix,
        body = {},
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["device.remove"] = function(ctx) return device_remove(ctx.req, "info") end
M.routes["device.unbind"] = function(ctx) return device_remove(ctx.req, "unbind") end

M.routes["entity.rename.batch"] = function(ctx)
    local req = ctx.req
    local renames = contract.param(req, "renames")
    if type(renames) ~= "table" or #renames == 0 then return missing(req, "renames") end
    local failed = {}
    for _, r in ipairs(renames) do
        if type(r) == "table" and r.id and r.name then
            local ok = common.call(req, {
                method = "POST", path = "/v1/device/" .. util.url_escape(tostring(r.id)) .. "/w/update",
                body = { name = tostring(r.name) },
            })
            if not ok then failed[#failed + 1] = tostring(r.id) end
        end
    end
    topology.invalidate()
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["meshgroup.detail.get"] = function(ctx)
    local req = ctx.req
    local group_id = contract.param(req, "groupId") or contract.param(req, "id")
    if not group_id then return missing(req, "groupId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/meshgroup/" .. util.url_escape(tostring(group_id)) .. "/r/detail", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { group = data.data or data })
end

M.routes["node.sorted_device.list"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local target = contract.param(req, "target") or "device"
    local data, resp2 = common.call(req, {
        method = "POST",
        path = "/v1/node/r/1/" .. util.url_escape(tostring(target)) .. "/device", body = {},
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    return contract.success(req, "ok", { total = #rows, items = common.top_n(rows).items })
end

M.routes["node.property_config.get"] = function(ctx)
    local req = ctx.req
    local device_id = contract.param(req, "deviceId") or contract.param(req, "id")
    if not device_id then return missing(req, "deviceId") end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/" .. util.url_escape(tostring(device_id)) .. "/r/property_config",
        body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { config = data.data or data })
end

M.routes["device.virtual_count.get"] = function(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/device/r/" .. util.url_escape(house_id) .. "/virturlNum", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { count = data.data or data })
end

-- device.slot.create：云端无开放端点（/v1/device/w/insert 为内部通道），不支持
M.routes["device.slot.create"] = function(ctx)
    return contract.not_supported(ctx.req,
        i18n.t("not_supported", ctx.req.locale, "device.slot.create"))
end

-- lighting.flow.execute：灯效/流（云端 action）
M.routes["lighting.flow.execute"] = function(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local flow = params.flow or params.flowName
    if not flow then return missing(req, "flow") end
    local resolved = M.resolve_control_targets(req)
    if not resolved.ok then return resolved.resp end
    local failed = {}
    for _, item in ipairs(resolved.items) do
        local ok = M.write_property(req, item, "flow", params.args or { name = flow }, "set")
        if not ok then failed[#failed + 1] = item.name end
    end
    if #failed > 0 then
        return contract.partial(req, i18n.t("partial", req.locale, table.concat(failed, "、")),
            { failed = failed })
    end
    return contract.success(req, i18n.t("ok", req.locale))
end

-- lighting.experience.apply：Runtime 明确 blocked
M.routes["lighting.experience.apply"] = function(ctx)
    return contract.blocked(ctx.req,
        i18n.t("not_supported", ctx.req.locale, "lighting.experience.apply"))
end

return M
