-- http.lua：cap_http_request 封装。统一注入鉴权 header、解析 "HTTP <status>\n<body>"、
-- 业务 code 归一化、数组包装。token 不出现在任何错误信息里。
local util = require("util")
local auth = require("auth")

local M = {}

M.DEFAULT_TIMEOUT_MS = 15000
M.DEFAULT_MAX_BODY = 65535
-- 同步 lua_run_script 60s 上限：预留响应时间，HTTP 链路预算 45s
M.BUDGET_MS = 45000
M._budget_deadline = nil

-- invoke 入口设置；每次 lua_run_script 新建 Lua state，天然隔离
function M.start_budget(now_ms)
    M._budget_deadline = (now_ms or 0) + M.BUDGET_MS
end

local function budget_left_ms()
    if not M._budget_deadline then return nil end
    return M._budget_deadline - util.now_ms()
end

local ALLOW_HOSTS = {
    ["api.yeelight.com"] = true,
    ["api-sg.yeelight.com"] = true,
    ["api-us.yeelight.com"] = true,
    ["api-de.yeelight.com"] = true,
    ["api-dev.yeedev.com"] = true,
}

function M.err(code, message, http_status)
    return { code = code, message = util.redact(tostring(message)), http_status = http_status }
end

-- bizType 仅允许 "0"/"1"（进入 HTTP header，防注入）
function M.sanitize_biz_type(value)
    if value == "1" or value == 1 then return "1" end
    return "0"
end

-- 解析 cap_http_request 输出："HTTP <status>[...]\n<body>" 或 "Error: ..."
local function parse_output(output)
    if type(output) ~= "string" then
        return nil, M.err("E_NETWORK", "empty http output")
    end
    if output:sub(1, 5) == "Error" then
        return nil, M.err("E_NETWORK", output:sub(1, 300))
    end
    local status = output:match("^HTTP (%d%d%d)")
    if not status then
        return nil, M.err("E_DECODE", "unexpected http output")
    end
    status = tonumber(status)
    local body_start = output:find("\n", 1, true)
    local body = body_start and output:sub(body_start + 1) or ""
    return { status = status, body = body }
end

local function decode_body(body)
    if body == nil or body == "" then return true, json.null or nil end
    local ok, data = pcall(function() return json.decode(body) end)
    if not ok then return false, M.err("E_DECODE", "invalid JSON body: " .. tostring(body):sub(1, 120)) end
    return true, data
end

-- 业务成功：success==true 或 code ∈ {"200","0",200,0}；顶层数组视为成功
function M.business_ok(data)
    if type(data) ~= "table" then return false, nil, nil end
    if util.is_array(data) then return true, nil, nil end
    local success = data.success
    if success == true then return true, nil, nil end
    if success == false then
        return false, tostring(data.msg or data.message or "business error"), data.code
    end
    local code = data.code
    if code == "200" or code == "0" or code == 200 or code == 0 then
        return true, nil, nil
    end
    return false, tostring(data.msg or data.message or "business error"), code
end

-- 数组响应包装成 {data=...}；对象/空表保持原样
function M.unwrap(data)
    if type(data) ~= "table" then return data end
    if util.is_array(data) and #data > 0 then return { data = data } end
    return data
end

-- opts: {method, path, base, body(table|string), headers(extra), timeout_ms,
--        max_body_bytes, save_path, no_auth(bool), region}
-- 返回: ok(bool), data|nil, err|nil, raw_response
function M.request(opts)
    opts = opts or {}
    local method = (opts.method or "GET"):upper()
    local creds, why
    if not opts.no_auth then
        creds, why = auth.require_credentials()
        if not creds then
            return false, nil, M.err(why == "auth_expired" and "E_AUTH_EXPIRED" or "E_NO_AUTH",
                why == "auth_expired" and "session expired" or "account not bound")
        end
    end
    local base = opts.base or auth.region_base(opts.region or (creds and creds.region))
    local host = base:match("^https?://([^/]+)") or ""
    if not ALLOW_HOSTS[host] then
        return false, nil, M.err("E_CONFIG", "base url not allowed")
    end
    local url = base .. M.escape_path(opts.path or "")
    local headers = {
        ["Accept"] = "application/json",
        ["Accept-Language"] = "zh-CN",
    }
    if creds then
        headers["Authorization"] = creds.authorization
        if creds.client_id then headers["Client-Id"] = tostring(creds.client_id) end
        local house = creds.house_id
        if house then
            headers["houseId"] = tostring(house)
            headers["house-id"] = tostring(house)
        end
        headers["bizType"] = M.sanitize_biz_type(creds.biz_type)
    end
    for k, v in pairs(opts.headers or {}) do headers[k] = tostring(v) end

    local body_str
    if opts.body ~= nil then
        if type(opts.body) == "string" then
            body_str = opts.body
        else
            local ok_e, encoded = pcall(function() return json.encode(opts.body) end)
            if not ok_e then return false, nil, M.err("E_CONFIG", "body not serializable") end
            body_str = encoded
        end
        headers["Content-Type"] = headers["Content-Type"] or "application/json"
    end
    if method == "GET" or method == "HEAD" then body_str = nil end

    local cap_opts = {
        url = url,
        method = method,
        headers = headers,
        timeout_ms = opts.timeout_ms or M.DEFAULT_TIMEOUT_MS,
        max_body_bytes = opts.max_body_bytes or M.DEFAULT_MAX_BODY,
    }
    if body_str then cap_opts.body = body_str end
    if opts.save_path then cap_opts.save_path = opts.save_path end
    -- 预算护栏：剩余时间不足以完成本次请求时快速失败，避免触发 60s 同步硬超时
    local left = budget_left_ms()
    if left ~= nil and left < (cap_opts.timeout_ms or M.DEFAULT_TIMEOUT_MS) then
        cap_opts.timeout_ms = math.max(1000, math.floor(left))
        if left <= 1000 then
            return false, nil, M.err("E_TIMEOUT_BUDGET", "time budget exhausted")
        end
    end

    -- 显式扩大 capability 输出缓冲（默认 64KB：HTTP 状态行 + 64KB body 会溢出截断）
    local cap_ok, output, cap_err = capability.call("http_request", cap_opts, { max_output_bytes = 131072 })
    local ok, output2, cap_err2 = cap_ok, output, cap_err
    if not ok then
        return false, nil, M.err("E_NETWORK", output2 or cap_err2 or "capability call failed")
    end
    local parsed, perr = parse_output(output)
    if not parsed then
        return false, nil, perr
    end
    if parsed.status == 401 or parsed.status == 403 then
        return false, nil, M.err(parsed.status == 401 and "E_AUTH_EXPIRED" or "E_FORBIDDEN",
            "http auth error", parsed.status)
    end
    if parsed.status < 200 or parsed.status >= 300 then
        return false, nil, M.err("E_HTTP", "unexpected status", parsed.status)
    end
    local ok_d, data = decode_body(parsed.body)
    if not ok_d then
        return false, nil, data
    end
    -- 空响应体（如部分 DELETE 的 200 空_body）视为成功
    if data == nil then
        return true, nil, nil, { http_status = parsed.status, data = nil }
    end
    local biz_ok, biz_msg, biz_code = M.business_ok(data)
    if not biz_ok then
        return false, nil, M.err("E_BUSINESS", biz_msg or "business error", parsed.status), {
            http_status = parsed.status, business_code = biz_code, data = data,
        }
    end
    return true, M.unwrap(data), nil, { http_status = parsed.status, data = data }
end

-- 路径参数 escape（幂等：已转义的 %XX 序列不重复转义；保留 / 与 query 的 ? & =）
function M.escape_path(path)
    local base, query = path:match("^([^?]*)%??(.*)$")
    local out = {}
    local i = 1
    while i <= #base do
        local c = base:sub(i, i)
        if c == "%" and base:sub(i + 1, i + 2):match("^%x%x$") then
            out[#out + 1] = base:sub(i, i + 2)
            i = i + 3
        elseif c:match("^[%w%-%_%.~/]$") then
            out[#out + 1] = c
            i = i + 1
        else
            out[#out + 1] = string.format("%%%02X", string.byte(c))
            i = i + 1
        end
    end
    base = table.concat(out)
    if query and query ~= "" then
        return base .. "?" .. query
    end
    return base
end

return M
