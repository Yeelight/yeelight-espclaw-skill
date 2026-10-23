-- tests/json_shim.lua：纯 Lua JSON 实现，测试环境替代固件 json 模块。
local M = {}

local function encode_value(v, out)
    local t = type(v)
    if v == nil then
        out[#out + 1] = "null"
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "number" then
        if math.floor(v) == v and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = string.format("%d", v)
        else
            out[#out + 1] = string.format("%.14g", v)
        end
    elseif t == "string" then
        out[#out + 1] = '"'
        out[#out + 1] = v:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' end
            if c == "\\" then return "\\\\" end
            if c == "\n" then return "\\n" end
            if c == "\r" then return "\\r" end
            if c == "\t" then return "\\t" end
            return string.format("\\u%04x", string.byte(c))
        end)
        out[#out + 1] = '"'
    elseif t == "table" then
        local n = 0
        local is_array = true
        for k, _ in pairs(v) do
            n = n + 1
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then is_array = false end
        end
        if is_array and n > 0 then
            if n ~= #v then is_array = false end
        end
        if is_array then
            out[#out + 1] = "["
            for i = 1, n do
                if i > 1 then out[#out + 1] = "," end
                encode_value(v[i], out)
            end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, val in pairs(v) do
                if not first then out[#out + 1] = "," end
                first = false
                encode_value(tostring(k), out)
                out[#out + 1] = ":"
                encode_value(val, out)
            end
            out[#out + 1] = "}"
        end
    else
        error("json.encode: unsupported type " .. t)
    end
end

function M.encode(v)
    local out = {}
    encode_value(v, out)
    return table.concat(out)
end

local decode_value
local function skip_ws(s, i)
    while i <= #s and s:sub(i, i):match("%s") do i = i + 1 end
    return i
end

local function parse_string(s, i)
    i = i + 1
    local out = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local e = s:sub(i + 1, i + 1)
            if e == "u" then
                local code = tonumber(s:sub(i + 2, i + 5), 16)
                if not code then error("bad \\u escape") end
                -- UTF-8 编码（不含代理对展开的完整实现）
                if code < 0x80 then
                    out[#out + 1] = string.char(code)
                elseif code < 0x800 then
                    out[#out + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
                else
                    out[#out + 1] = string.char(0xE0 + math.floor(code / 0x1000),
                        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
                end
                i = i + 6
            else
                local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                out[#out + 1] = map[e] or e
                i = i + 2
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    error("unterminated string")
end

local function parse_number(s, i)
    local j = i
    while j <= #s and s:sub(j, j):match("[%d%-%+%.eE]") do j = j + 1 end
    local num = tonumber(s:sub(i, j - 1))
    if not num then error("bad number at " .. i) end
    return num, j
end

decode_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then return parse_string(s, i) end
    if c == "{" then
        local obj = {}
        i = skip_ws(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            i = skip_ws(s, i)
            local key
            key, i = parse_string(s, i)
            i = skip_ws(s, i)
            if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
            local val
            val, i = decode_value(s, i + 1)
            obj[key] = val
            i = skip_ws(s, i)
            if s:sub(i, i) == "," then i = i + 1
            elseif s:sub(i, i) == "}" then return obj, i + 1
            else error("expected , or } at " .. i) end
        end
    end
    if c == "[" then
        local arr = {}
        i = skip_ws(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local val
            val, i = decode_value(s, i)
            arr[#arr + 1] = val
            i = skip_ws(s, i)
            if s:sub(i, i) == "," then i = i + 1
            elseif s:sub(i, i) == "]" then return arr, i + 1
            else error("expected , or ] at " .. i) end
        end
    end
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    if s:sub(i, i + 3) == "null" then return nil, i + 4 end
    return parse_number(s, i)
end

function M.decode(s)
    local v, _ = decode_value(s, 1)
    return v
end

return M
