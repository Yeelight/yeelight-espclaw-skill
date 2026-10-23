-- api/common.lua：API 域公共辅助（错误映射、列表截断、house 上下文）。
local util = require("util")
local contract = require("contract")
local i18n = require("i18n")
local auth = require("auth")

local M = {}

M.TOP_N = 10

-- http 错误 -> SkillResponse
function M.err_response(req, err)
    if not err then return contract.error(req, "unknown error") end
    local code = err.code
    if code == "E_NO_AUTH" or code == "not_bound" then
        return contract.auth_required(req, i18n.t("not_bound", req.locale))
    end
    if code == "E_AUTH_EXPIRED" then
        return contract.auth_required(req, i18n.t("auth_expired", req.locale))
    end
    if code == "E_FORBIDDEN" then
        return contract.blocked(req, i18n.t("blocked", req.locale, tostring(err.message)))
    end
    if code == "E_NO_HOUSE" then
        return contract.blocked(req, i18n.t("no_house", req.locale))
    end
    if code == "E_HTTP" and err.http_status then
        return contract.error(req, i18n.t("http_error", req.locale, err.http_status,
            tostring(err.message or "")))
    end
    return contract.error(req, i18n.t("error", req.locale, tostring(err.message or code)))
end

-- house_id：显式参数 > 默认绑定家庭；缺失 -> blocked 响应, nil
function M.require_house_id(req)
    local explicit = contract.param(req, "houseId")
    if explicit and explicit ~= "" then return tostring(explicit), nil end
    local creds, why = auth.require_credentials()
    if not creds then
        return nil, contract.auth_required(req,
            i18n.t(why == "auth_expired" and "auth_expired" or "not_bound", req.locale))
    end
    local house_id = auth.default_house_id(creds)
    if not house_id then
        return nil, contract.blocked(req, i18n.t("no_house_selected", req.locale))
    end
    return tostring(house_id), nil
end

-- 列表截断：{total, items(top N), truncated}
function M.top_n(rows, top)
    top = top or M.TOP_N
    rows = rows or {}
    local total = #rows
    local items = {}
    for i = 1, math.min(top, total) do items[i] = rows[i] end
    return { total = total, items = items, truncated = total > top }
end

-- 名称列表逗号连接
function M.name_list(rows, n)
    n = n or 8
    local names = {}
    for i = 1, math.min(n, #rows) do
        names[#names + 1] = tostring(rows[i].name or rows[i])
    end
    return table.concat(names, "、")
end

-- 通用读封装：request -> ok / 响应
function M.call(req, opts)
    local ok, data, err = require("http").request(opts)
    if not ok then return nil, M.err_response(req, err) end
    return data, nil
end

return M
