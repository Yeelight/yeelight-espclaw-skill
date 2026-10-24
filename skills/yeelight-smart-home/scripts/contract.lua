-- contract.lua：SkillRequest 校验 + SkillResponse 构造（7 种 status）
local util = require("util")

local M = {}

M.CONTRACT_VERSION = "1.0"
M.STATUSES = {
    SUCCESS = "success",
    PARTIAL = "partial",
    CLARIFICATION = "clarification_required",
    BLOCKED = "blocked",
    NOT_SUPPORTED = "not_supported",
    AUTH_REQUIRED = "auth_required",
    ERROR = "error",
}

-- 用户消息 / result 上限，保证 lua_run_script 4KB 输出可容纳
M.MAX_USER_MESSAGE = 1200
M.MAX_RESULT_JSON = 2400

local function valid_request(raw)
    if type(raw) ~= "table" then return "args must be an object" end
    if raw.contractVersion and raw.contractVersion ~= M.CONTRACT_VERSION then
        return "unsupported contractVersion: " .. tostring(raw.contractVersion)
    end
    if type(raw.intent) ~= "string" or raw.intent == "" then
        return "missing intent"
    end
    return nil
end

-- 规范化请求；失败返回 nil, err
function M.normalize_request(args)
    local err = valid_request(args)
    if err then return nil, err end
    local req = {
        contractVersion = M.CONTRACT_VERSION,
        requestId = tostring(args.requestId or util.random_id("req-")),
        locale = args.locale or "zh-CN",
        utterance = args.utterance or "",
        intent = args.intent,
        sessionId = args.sessionId,
        homeRef = args.homeRef,
        parameters = type(args.parameters) == "table" and args.parameters or {},
        conversationContext = args.conversationContext,
        options = type(args.options) == "table" and args.options or {},
    }
    -- targets：顶层优先；parameters.targets 作为批量入口（SKILL.md 契约）
    local targets = nil
    if type(args.targets) == "table" and #args.targets > 0 then
        targets = args.targets
    elseif type(req.parameters.targets) == "table" and #req.parameters.targets > 0 then
        targets = req.parameters.targets
    end
    req.targets = targets
    return req
end

local function truncate_json(result)
    if result == nil then return nil end
    local ok, encoded = pcall(function() return json.encode(result) end)
    if not ok then return nil end
    if #encoded <= M.MAX_RESULT_JSON then return result end
    -- 超限：退化为摘要
    local summary = {}
    for k, v in pairs(result) do
        if type(v) ~= "table" then summary[k] = v end
    end
    summary.truncated = true
    return summary
end

local function truncate_utf8(s, max_bytes)
    if type(s) ~= "string" or #s <= max_bytes then return s end
    -- s:sub(1, cut) 为完整字符 ⇔ 第 cut+1 字节不是续字节（0x80-0xBF）
    local cut = max_bytes
    while cut > 0 do
        local next_byte = string.byte(s, cut + 1)
        if next_byte and next_byte >= 0x80 and next_byte < 0xC0 then
            cut = cut - 1
        else
            break
        end
    end
    if cut <= 0 then return "" end
    return s:sub(1, cut) .. "…"
end

-- clarification 体积防线：candidates 投影精简，整体超限退化为 question
local function slim_clarification(clar)
    if type(clar) ~= "table" then return clar end
    local out = {}
    for k, v in pairs(clar) do out[k] = v end
    if type(out.candidates) == "table" then
        local slim = {}
        for i, c in ipairs(out.candidates) do
            if i > 5 then break end
            if type(c) == "table" then
                slim[i] = { id = c.id, name = c.name, roomName = c.roomName }
            else
                slim[i] = c
            end
        end
        out.candidates = slim
    end
    local ok, encoded = pcall(function() return json.encode(out) end)
    if not ok or #encoded > 800 then
        return { question = tostring(out.question or "") }
    end
    return out
end

function M.make(req, status, user_message, result, extra)
    local resp = {
        contractVersion = M.CONTRACT_VERSION,
        requestId = req and req.requestId or util.random_id("req-"),
        status = status,
        userMessage = truncate_utf8(user_message, M.MAX_USER_MESSAGE),
    }
    if result ~= nil then resp.result = truncate_json(result) end
    if type(extra) == "table" then
        for _, key in ipairs({ "clarification", "error", "warnings", "metrics", "traceId" }) do
            if extra[key] ~= nil then
                resp[key] = (key == "clarification") and slim_clarification(extra[key]) or extra[key]
            end
        end
    end
    return resp
end

function M.success(req, message, result, extra)
    return M.make(req, M.STATUSES.SUCCESS, message or "ok", result, extra)
end

function M.partial(req, message, result, extra)
    return M.make(req, M.STATUSES.PARTIAL, message, result, extra)
end

function M.clarification(req, message, clarification)
    return M.make(req, M.STATUSES.CLARIFICATION, message, nil, { clarification = clarification })
end

function M.blocked(req, message, extra)
    return M.make(req, M.STATUSES.BLOCKED, message, nil, extra)
end

function M.not_supported(req, message)
    return M.make(req, M.STATUSES.NOT_SUPPORTED, message)
end

function M.auth_required(req, message)
    return M.make(req, M.STATUSES.AUTH_REQUIRED, message)
end

function M.error(req, message, code)
    local msg = truncate_utf8(tostring(message or ""), 300)
    return M.make(req, M.STATUSES.ERROR, msg, nil,
        { error = { code = code or "E_INTERNAL", message = msg } })
end

-- 参数读取辅助：支持 parameters 与顶层兜底
function M.param(req, name)
    local p = req.parameters and req.parameters[name]
    if p ~= nil then return p end
    return req[name]
end

return M
