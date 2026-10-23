-- api/scene.lua：情景域（scene.*）
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local common = require("api.common")
local topology = require("topology")
local name_match = require("name_match")

local M = {}

local function missing(req, key)
    return contract.make(req, contract.STATUSES.CLARIFICATION,
        i18n.t("missing_param", req.locale, key))
end

local function scene_base(house_id)
    return "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/scene"
end

local function resolve_scene(req)
    local scene_id = contract.param(req, "sceneId") or contract.param(req, "id")
    if scene_id then
        return { id = tostring(scene_id), name = tostring(contract.param(req, "sceneName") or scene_id) }
    end
    local name = contract.param(req, "sceneName") or contract.param(req, "name")
    if not name or name == "" then return nil end
    local ok, topo, terr = topology.load({})
    if not ok then return nil, terr end
    local m = name_match.match_one(name, topo.scenes or topo.devices)
    if m.status == "exact" then
        return { id = tostring(m.item.id), name = m.item.name }
    end
    if m.status == "ambiguous" then
        return { ambiguous = m.candidates, name = name }
    end
    return { not_found = true, name = name }
end

local function list_scenes(ctx)
    local req = ctx.req
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "POST", path = scene_base(house_id) .. "/r/info/1/100", body = {},
    })
    if not data then return resp2 end
    local rows = topology.extract_rows(data)
    -- 写入拓扑缓存供 resolve_scene 使用
    local ok, topo = topology.load({})
    if ok then topo.scenes = rows end
    return rows, nil
end

M.routes = {}

M.routes["scene.list"] = function(ctx)
    local req = ctx.req
    local rows, resp = list_scenes(ctx)
    if not rows then return resp end
    local summary = common.top_n(rows)
    return contract.success(req,
        i18n.t("scene_list", req.locale, #rows, common.name_list(summary.items)),
        { total = #rows, items = summary.items, truncated = summary.truncated })
end

M.routes["scene.scoped.list"] = M.routes["scene.list"]

M.routes["scene.search"] = function(ctx)
    local req = ctx.req
    local word = contract.param(req, "keyword") or contract.param(req, "sceneName") or ""
    local rows, resp = list_scenes(ctx)
    if not rows then return resp end
    local matched = {}
    for _, s in ipairs(rows) do
        local name = tostring(s.name or "")
        if word == "" or name:find(word, 1, true) then matched[#matched + 1] = s end
    end
    return contract.success(req, i18n.t("scene_list", req.locale, #matched, common.name_list(matched)),
        { total = #matched, items = common.top_n(matched).items })
end

M.routes["scene.detail.get"] = function(ctx)
    local req = ctx.req
    local scene = resolve_scene(req)
    if not scene then return missing(req, "sceneId/sceneName") end
    if scene.not_found or scene.ambiguous then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(scene.name)))
    end
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/scene/" .. util.url_escape(scene.id) .. "/r/detail", body = {},
    })
    if not data then return resp2 end
    return contract.success(req, "ok", { scene = data.data or data })
end

-- 执行：主端点 -> 两个 fallback；无有效网关 -> blocked
M.routes["scene.execute"] = function(ctx)
    local req = ctx.req
    local scene = resolve_scene(req)
    if not scene then return missing(req, "sceneId/sceneName") end
    if scene.ambiguous then
        local labels = name_match.candidate_labels(scene.ambiguous)
        local msg = i18n.t("ambiguous", req.locale, tostring(scene.name), #scene.ambiguous, labels)
        return contract.clarification(req, msg, { question = msg, candidates = scene.ambiguous })
    end
    if scene.not_found then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(scene.name)))
    end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local endpoints = {
        "/v1/open/control/house/" .. util.url_escape(house_id) .. "/control/w/scenes/" .. util.url_escape(scene.id),
        "/v1/controll/device/w/scene/" .. util.url_escape(scene.id),
        "/v1/thing/device/w/scene/" .. util.url_escape(scene.id),
    }
    local last_err, no_gateway = nil, false
    for i, path in ipairs(endpoints) do
        local ok, data, err = require("http").request({ method = "POST", path = path, body = {} })
        if ok then
            return contract.success(req, i18n.t("scene_executed", req.locale, scene.name),
                { sceneId = scene.id, source = "endpoint_" .. i })
        end
        last_err = err
        if err and err.message and tostring(err.message):find("无有效网关", 1, true) then
            no_gateway = true
        end
        -- fallback 仅在网关错误时继续；其余错误直接失败
        if not no_gateway then break end
    end
    if no_gateway then
        return contract.blocked(req, i18n.t("blocked", req.locale, "scene has no valid gateway"))
    end
    return common.err_response(req, last_err)
end

M.routes["scene.test"] = function(ctx)
    local req = ctx.req
    req.parameters = util.merge(req.parameters or {}, { dryRun = true })
    return M.routes["scene.execute"]({ req = req })
end

M.routes["scene.create"] = function(ctx)
    local req = ctx.req
    local scene = contract.param(req, "scene")
    local name = contract.param(req, "name") or contract.param(req, "sceneName")
    if type(scene) ~= "table" or not name then return missing(req, "name/scene(actions)") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = util.merge(scene, { name = tostring(name) })
    local data, resp2 = common.call(req, {
        method = "PUT", path = scene_base(house_id) .. "/w/create", body = body,
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale), { scene = data.data or data })
end

-- 全量替换
M.routes["scene.update"] = function(ctx)
    local req = ctx.req
    local scene = resolve_scene(req)
    if not scene then return missing(req, "sceneId/sceneName") end
    if scene.not_found or scene.ambiguous then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(scene.name)))
    end
    local payload = contract.param(req, "scene")
    if type(payload) ~= "table" then return missing(req, "scene(actions, full replace)") end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local body = util.merge(payload, { id = scene.id })
    local data, resp2 = common.call(req, {
        method = "POST", path = "/v1/scene/" .. util.url_escape(scene.id) .. "/w/modify", body = body,
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

local function scene_delete(req)
    local scene = resolve_scene(req)
    if not scene then return missing(req, "sceneId/sceneName") end
    if scene.not_found or scene.ambiguous then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(scene.name)))
    end
    local house_id, resp = common.require_house_id(req)
    if not house_id then return resp end
    local data, resp2 = common.call(req, {
        method = "DELETE",
        path = scene_base(house_id) .. "/" .. util.url_escape(scene.id) .. "/w/info", body = {},
    })
    if not data then return resp2 end
    topology.invalidate()
    return contract.success(req, i18n.t("ok", req.locale))
end

M.routes["scene.delete"] = scene_delete
M.routes["scene.batch_delete"] = scene_delete

return M
