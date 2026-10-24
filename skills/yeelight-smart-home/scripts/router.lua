-- router.lua：intent -> handler。所有 intent 的唯一事实来源（tools/gen_intent_map.lua 据此生成 intent-map.json）。
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local risk = require("risk")
local auth = require("auth")
local bind = require("bind")
local qr = require("qr")
local local_cap = require("local")
local common = require("api.common")

local M = {}

local function merge_routes(into, module)
    for intent, handler in pairs(module.routes or {}) do
        into[intent] = handler
    end
    return into
end

local HANDLERS = {}
for _, name in ipairs({
    "api.home", "api.room", "api.area", "api.device", "api.group", "api.scene",
    "api.automation", "api.gateway", "api.panel", "api.knob", "api.favorite",
    "api.thing", "api.misc", "api.lighting", "api.diagnose",
}) do
    merge_routes(HANDLERS, require(name))
end

-- ---- 本地能力 handlers ----
local LOCAL_HANDLERS = {}

LOCAL_HANDLERS["memory.remember"] = function(ctx)
    local req = ctx.req
    local content = contract.param(req, "content") or req.utterance
    local ok, item = local_cap.memory_remember({ content = content, kind = contract.param(req, "kind") })
    if not ok then
        return contract.error(req, i18n.t("error", req.locale, "memory save failed"))
    end
    return contract.success(req, i18n.t("memory_saved", req.locale, tostring(item.content)))
end

LOCAL_HANDLERS["memory.list"] = function(ctx)
    local req = ctx.req
    if local_cap.memory_is_paused() then
        return contract.success(req, i18n.t("memory_list", req.locale, 0), { paused = true, items = {} })
    end
    local items = local_cap.memory_list()
    return contract.success(req, i18n.t("memory_list", req.locale, #items), { items = items })
end

LOCAL_HANDLERS["memory.pause"] = function(ctx)
    local_cap.memory_set_paused(true)
    return contract.success(ctx.req, i18n.t("ok", ctx.req.locale), { paused = true })
end

LOCAL_HANDLERS["memory.resume"] = function(ctx)
    local_cap.memory_set_paused(false)
    return contract.success(ctx.req, i18n.t("ok", ctx.req.locale), { paused = false })
end

LOCAL_HANDLERS["memory.forget"] = function(ctx)
    local req = ctx.req
    local removed = local_cap.memory_forget(contract.param(req, "content") or contract.param(req, "keyword"))
    if removed == 0 then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("not_found", req.locale, tostring(contract.param(req, "content") or "")))
    end
    return contract.success(req, i18n.t("memory_cleared", req.locale), { removed = removed })
end

LOCAL_HANDLERS["recommendation.list"] = function(ctx)
    local req = ctx.req
    local items = local_cap.recommendation_list()
    return contract.success(req, "ok", { items = items })
end

LOCAL_HANDLERS["recommendation.record"] = function(ctx)
    local req = ctx.req
    local ok = local_cap.recommendation_record({
        intent = contract.param(req, "targetIntent") or req.intent,
        params = req.parameters,
    })
    if not ok then return contract.error(req, i18n.t("error", req.locale, "record failed")) end
    return contract.success(req, i18n.t("ok", req.locale))
end

LOCAL_HANDLERS["recommendation.feedback"] = function(ctx)
    local req = ctx.req
    local ok = local_cap.recommendation_feedback(contract.param(req, "id"), contract.param(req, "feedback"))
    if not ok then return contract.error(req, i18n.t("error", req.locale, "feedback failed")) end
    return contract.success(req, i18n.t("ok", req.locale))
end

LOCAL_HANDLERS["operation.lesson.record"] = function(ctx)
    local req = ctx.req
    local ok = local_cap.lesson_record({
        lesson = contract.param(req, "lesson") or req.utterance,
        intent = contract.param(req, "intent"),
    })
    if not ok then return contract.error(req, i18n.t("error", req.locale, "lesson save failed")) end
    return contract.success(req, i18n.t("ok", req.locale))
end

LOCAL_HANDLERS["operation.lesson.list"] = function(ctx)
    local req = ctx.req
    local items = local_cap.lesson_list()
    return contract.success(req, "ok", { items = items })
end

-- 批量配置：顺序执行 steps = [{intent=..., parameters={...}}]，任一失败即 partial
-- 递归深度保护：嵌套 batch 最多 3 层（M._batch_depth）
M._batch_depth = M._batch_depth or 0
LOCAL_HANDLERS["operation.batch.configure"] = function(ctx)
    local req = ctx.req
    if M._batch_depth >= 3 then
        return contract.blocked(req, i18n.t("blocked", req.locale, "nested batch depth limit (3)"))
    end
    local steps = contract.param(req, "steps")
    if type(steps) ~= "table" or #steps == 0 then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("missing_param", req.locale, "steps"))
    end
    local ok_steps, failed = {}, {}
    M._batch_depth = M._batch_depth + 1
    for i, step in ipairs(steps) do
        if type(step) == "table" and step.intent then
            local sub_req = {
                contractVersion = req.contractVersion,
                requestId = req.requestId .. "-" .. i,
                locale = req.locale,
                utterance = step.utterance or req.utterance,
                intent = step.intent,
                parameters = step.parameters or {},
                targets = step.targets,
            }
            local resp = M.dispatch(sub_req)
            if resp.status == contract.STATUSES.SUCCESS then
                ok_steps[#ok_steps + 1] = step.intent
            else
                failed[#failed + 1] = { intent = step.intent, status = resp.status }
            end
        end
    end
    M._batch_depth = M._batch_depth - 1
    if #failed == 0 then
        return contract.success(req, i18n.t("ok", req.locale), { applied = ok_steps })
    end
    if #ok_steps == 0 then
        return contract.error(req, i18n.t("error", req.locale, "all steps failed"))
    end
    return contract.partial(req, i18n.t("partial", req.locale,
        tostring(#failed) .. " steps failed"), { applied = ok_steps, failed = failed })
end

LOCAL_HANDLERS["intent.explain"] = function(ctx)
    local req = ctx.req
    local intent = contract.param(req, "targetIntent") or contract.param(req, "intent")
    local info = M.intent_info(intent)
    return contract.success(req, "ok", {
        intent = intent,
        supported = info ~= nil,
        risk = risk.risk_of(intent or ""),
        handlerModule = info and info.module or nil,
    })
end

-- ---- bind.account ----
local function handle_bind(ctx)
    local req = ctx.req
    local params = req.parameters or {}
    local state, detail, err
    if params.token and params.token ~= "" then
        -- 开发/调试直填 token（不推荐；不回显）
        local creds = auth.save_binding({
            authorization = tostring(params.token),
            region = params.region,
            house_id = params.houseId,
        })
        if not creds then
            return contract.error(req, i18n.t("bind_failed", req.locale, "save failed"))
        end
        state = "login"
        detail = { houseId = creds.house_id }
    else
        local ok
        ok, state, detail, err = bind.run({
            deviceId = params.deviceId,
            region = params.region,
            resume = type(params.resume) == "table" and params.resume or nil,
            poll_ms = 0,
            on_created = function(info)
                ctx.qr_display = qr.display(info)
            end,
        })
        if state == "failed" then
            local reason = (err and err.message) or (detail and detail.message) or "unknown"
            return contract.error(req, i18n.t("bind_failed", req.locale, tostring(reason)))
        end
    end
    if state == "login" then
        local creds = auth.load() or {}
        return contract.success(req, i18n.t("bind_done", req.locale,
            tostring(creds.house_name or creds.house_id or "")), {
            region = creds.region, houseId = creds.house_id,
        })
    elseif state == "created" then
        local display = ctx.qr_display or qr.display(detail)
        local msg
        if display.mode == "screen" then
            msg = i18n.t("bind_created", req.locale)
        else
            msg = i18n.t("bind_created", req.locale) .. " QR: " .. tostring(display.content)
        end
        return contract.make(req, contract.STATUSES.CLARIFICATION, msg, nil, {
            clarification = {
                question = msg,
                resume = { qrCodeId = detail.qrCodeId, deviceId = detail.deviceId },
                expiresAt = detail.expireAt,
            },
        })
    elseif state == "pending" then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("bind_pending", req.locale), nil, {
                clarification = { question = i18n.t("bind_pending", req.locale),
                    resume = { qrCodeId = params.resume and params.resume.qrCodeId or nil,
                        deviceId = params.resume and params.resume.deviceId or nil } },
            })
    elseif state == "expired" then
        return contract.make(req, contract.STATUSES.CLARIFICATION,
            i18n.t("bind_expired", req.locale))
    end
    return contract.error(req, i18n.t("bind_failed", req.locale, "unknown state"))
end

function M.dispatch(req)
    local intent = req.intent
    -- options.explain：只解释 intent，不执行（须在所有执行分支之前）
    if req.options and req.options.explain == true then
        return LOCAL_HANDLERS["intent.explain"]({ req = req })
    end
    -- 绑定独立入口
    if intent == "bind.account" then
        return handle_bind({ req = req })
    end
    -- 本地能力
    local local_handler = LOCAL_HANDLERS[intent]
    if local_handler then
        local guarded = risk.guard(req)
        if guarded then return guarded end
        return local_handler({ req = req })
    end
    -- 云端能力
    local handler = HANDLERS[intent]
    if not handler then
        return contract.not_supported(req, i18n.t("not_supported", req.locale, intent))
    end
    -- 风险拦截（R3 确认 / 敏感属性 / 可写白名单）
    local guarded = risk.guard(req)
    if guarded then return guarded end
    return handler({ req = req })
end

-- intent -> {module, handler} 信息（gen_intent_map 用）
function M.intent_info(intent)
    if LOCAL_HANDLERS[intent] then return { module = "local", handler = "local" } end
    for _, name in ipairs({
        "api.home", "api.room", "api.area", "api.device", "api.group", "api.scene",
        "api.automation", "api.gateway", "api.panel", "api.knob", "api.favorite",
        "api.thing", "api.misc", "api.lighting", "api.diagnose",
    }) do
        local mod = require(name)
        if mod.routes[intent] then
            return { module = name:gsub("api%.", ""), handler = intent }
        end
    end
    if intent == "bind.account" then return { module = "bind", handler = "bind.account" } end
    return nil
end

M.HANDLERS = HANDLERS
M.LOCAL_HANDLERS = LOCAL_HANDLERS

return M
