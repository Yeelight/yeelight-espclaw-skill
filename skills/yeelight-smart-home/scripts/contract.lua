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
        targets = type(args.targets) == "table" and args.targets or nil,
        parameters = type(args.parameters) == "table" and args.parameters or {},
        conversationContext = args.conversationContext,
        options = type(args.options) == "table" and args.options or {},
    }
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

function M.make(req, status, user_message, result, extra)
    local resp = {
        contractVersion = M.CONTRACT_VERSION,
        requestId = req and req.requestId or util.random_id("req-"),
        status = status,
        userMessage = user_message,
    }
    if result ~= nil then resp.result = truncate_json(result) end
    if type(extra) == "table" then
        for _, key in ipairs({ "clarification", "error", "warnings", "metrics", "traceId" }) do
            if extra[key] ~= nil then resp[key] = extra[key] end
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
    return M.make(req, M.STATUSES.ERROR, message, nil,
        { error = { code = code or "E_INTERNAL", message = message } })
end

-- 参数读取辅助：支持 parameters 与顶层兜底
function M.param(req, name)
    local p = req.parameters and req.parameters[name]
    if p ~= nil then return p end
    return req[name]
end

return M
