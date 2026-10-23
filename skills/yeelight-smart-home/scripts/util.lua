-- util.lua：通用工具（JSON 假设全局 json 模块存在；设备与测试环境都注入）
local M = {}

function M.is_array(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then return false end
        n = n + 1
    end
    return n == 0 or n == #t
end

function M.type_of(v)
    if v == nil then return "nil" end
    if M.is_array(v) then return "array" end
    if type(v) == "table" then return "object" end
    return type(v)
end

function M.trim(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.split(s, sep)
    local out = {}
    local pat = "([^" .. sep .. "]*)"
    for part in string.gmatch(s, pat) do
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

function M.clamp(v, lo, hi)
    v = tonumber(v)
    if v == nil then return nil end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.to_int(v)
    local n = tonumber(v)
    if n == nil then return nil end
    return math.floor(n)
end

-- 深拷贝（处理嵌套表/数组）
function M.deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = M.deep_copy(val) end
    return out
end

function M.merge(base, extra)
    local out = M.deep_copy(base or {})
    extra = extra or {}
    for k, v in pairs(extra) do
        if type(v) == "table" and type(out[k]) == "table" and not M.is_array(v) then
            out[k] = M.merge(out[k], v)
        else
            out[k] = M.deep_copy(v)
        end
    end
    return out
end

function M.table_size(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function M.url_escape(s)
    s = tostring(s or "")
    return s:gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64REV = {}
for i = 1, #B64URL do B64REV[string.sub(B64URL, i, i)] = i - 1 end

function M.base64url_decode(s)
    if type(s) ~= "string" then return nil end
    local bits, out = 0, {}
    local acc = 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c ~= "=" then
            local v = B64REV[c]
            if not v then return nil end
            acc = acc * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = string.char(math.floor(acc / (2 ^ bits)) % 256)
                acc = acc % (2 ^ bits)
            end
        end
    end
    return table.concat(out)
end

-- 解析 JWT 的 exp（秒）。失败返回 nil。
function M.jwt_exp(token)
    if type(token) ~= "string" then return nil end
    token = token:gsub("^Bearer%s+", "")
    local parts = {}
    for p in token:gmatch("[^.]+") do parts[#parts + 1] = p end
    if #parts < 2 then return nil end
    local payload = M.base64url_decode(parts[2])
    if not payload then return nil end
    local ok, decoded = pcall(function() return json.decode(payload) end)
    if not ok or type(decoded) ~= "table" then return nil end
    return tonumber(decoded.exp)
end

-- 简易脱敏：日志中绝不出现 token
function M.redact(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("Bearer%s+[%w%-%_%.%~]+", "Bearer ***")
             :gsub('"authorization"%s*:%s*"[^"]+"', '"authorization":"***"'))
end

-- 随机 ID（绑定用 deviceId 等）
function M.random_id(prefix, n)
    n = n or 12
    math.randomseed((system and system.millis and system.millis() or os.time() * 1000) % 2147483647)
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local out = {}
    for _ = 1, n do
        local i = math.random(1, #chars)
        out[#out + 1] = chars:sub(i, i)
    end
    return (prefix or "") .. table.concat(out)
end

function M.now_ms()
    if system and system.millis then return system.millis() end
    return os.time() * 1000
end

function M.sleep(ms)
    if delay and delay.delay_ms then
        delay.delay_ms(ms)
    elseif os and os.clock then
        -- 测试环境：忙等不可靠，直接跳过
    end
end

function M.first_nonempty(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and v ~= "" then return v end
    end
    return nil
end

function M.slice(t, from, to)
    local out = {}
    if type(t) ~= "table" then return out end
    for i = from or 1, math.min(to or #t, #t) do out[#out + 1] = t[i] end
    return out
end

return M
