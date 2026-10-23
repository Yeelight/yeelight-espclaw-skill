-- http.lua：cap_http_request 封装。统一注入鉴权 header、解析 "HTTP <status>\n<body>"、
-- 业务 code 归一化、数组包装。token 不出现在任何错误信息里。
local util = require("util")
local auth = require("auth")

local M = {}

M.DEFAULT_TIMEOUT_MS = 15000
M.DEFAULT_MAX_BODY = 65535

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

-- opts: {method, path, base, body(table), headers(extra), timeout_ms,
--        max_body_bytes, save_path, no_auth(bool), raw_path(bool), region}
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
    local host_ok = false
    for host in pairs(ALLOW_HOSTS) do
        if base:find(host, 1, true) then host_ok = true end
    end
    if not host_ok then
        return false, nil, M.err("E_CONFIG", "base url not allowed")
    end
    local url = base .. (opts.raw_path and opts.path or M.escape_path(opts.path or ""))
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
        headers["bizType"] = tostring(creds.biz_type or "0")
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

    local ok, output, cap_err = capability.call("http_request", cap_opts)
    if not ok then
        return false, nil, M.err("E_NETWORK", cap_err or output or "capability call failed")
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
    local biz_ok, biz_msg, biz_code = M.business_ok(data)
    if not biz_ok then
        return false, nil, M.err("E_BUSINESS", biz_msg or "business error", parsed.status), {
            http_status = parsed.status, business_code = biz_code, data = data,
        }
    end
    return true, M.unwrap(data), nil, { http_status = parsed.status, data = data }
end

-- 路径参数 escape（保留 / 与 query string 的 ? & =）
function M.escape_path(path)
    local base, query = path:match("^([^?]*)%??(.*)$")
    base = base:gsub("[^%w%-%_%.~/]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    if query and query ~= "" then
        return base .. "?" .. query
    end
    return base
end

-- 分页路径片段：/r/info/{pageNo}/{pageSize}
function M.page_path(prefix, pageNo, pageSize)
    return string.format("%s/r/info/%d/%d", prefix, pageNo or 1, pageSize or 100)
end

function M.get(opts) opts = util.merge(opts or {}, {}); opts.method = "GET"; return M.request(opts) end
function M.post(opts) opts.method = "POST"; return M.request(opts) end
function M.put(opts) opts.method = "PUT"; return M.request(opts) end
function M.delete(opts) opts.method = "DELETE"; return M.request(opts) end

-- 分页拉取全部（上限 max_pages），rows 汇总
function M.fetch_all_pages(opts, rows_key)
    rows_key = rows_key or "rows"
    local all = {}
    local page = opts.pageNo or 1
    local max_pages = opts.maxPages or 5
    for _ = 1, max_pages do
        local ok, data, err = M.request(opts)
        if not ok then return false, nil, err end
        local rows = data and data[rows_key] or (data and data.data and data.data[rows_key]) or {}
        for _, r in ipairs(rows) do all[#all + 1] = r end
        local total = tonumber(data.total or (data.data and data.data.total)) or #all
        if #all >= total or #rows == 0 then
            return true, { rows = all, total = total }, nil
        end
        page = page + 1
        opts.pageNo = page
    end
    return true, { rows = all, total = #all }, nil
end

return M
