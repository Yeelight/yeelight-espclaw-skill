-- invoke.lua：入口脚本。lua_run_script(path="{CUR_SKILL_DIR}/scripts/invoke.lua", args=SkillRequest)
-- 输出单个 JSON SkillResponse（≤4KB）。任何异常都转为结构化响应，不向 LLM 抛裸错误。
local contract = require("contract")
local router = require("router")
local i18n = require("i18n")

local req, norm_err = contract.normalize_request(args)
if not req then
    print(json.encode({
        contractVersion = contract.CONTRACT_VERSION,
        requestId = "req-invalid",
        status = contract.STATUSES.ERROR,
        userMessage = "invalid request: " .. tostring(norm_err),
        error = { code = "E_INVALID_REQUEST", message = tostring(norm_err) },
    }))
    return
end

local ok, resp = pcall(function()
    return router.dispatch(req)
end)

if not ok then
    resp = contract.error(req, i18n.t("error", req.locale, "internal error"),
        "E_INTERNAL")
end

-- 兜底：响应必须完整
if type(resp) ~= "table" or not resp.status then
    resp = contract.error(req, i18n.t("error", req.locale, "invalid internal response"),
        "E_INVALID_RESPONSE")
end

print(json.encode(resp))
