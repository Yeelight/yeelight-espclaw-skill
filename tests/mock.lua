-- tests/mock.lua：测试环境全局注入（json/capability/storage/delay/system）与断言工具。
local json_shim = require("tests.json_shim")

local M = {}

function M.setup_globals()
    if not json then _G.json = json_shim end
    -- storage mock（固件保真语义）：
    -- read_file 文件不存在时抛 error、成功仅返回 content 单值；
    -- 路径需 get_root_dir + join_path 构造。
    local files = {}
    _G.storage = {
        get_root_dir = function() return "/data" end,
        join_path = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            return table.concat(parts, "/")
        end,
        exists = function(path) return files[path] ~= nil end,
        mkdir = function() return true end,
        read_file = function(path)
            if files[path] == nil then
                error("cannot open file for reading: " .. tostring(path))
            end
            return files[path]
        end,
        write_file = function(path, content) files[path] = content; return true end,
        _files = files,
    }
    _G.storage_reset = function()
        for k in pairs(files) do files[k] = nil end
    end
    _G.delay = { delay_ms = function() end }
    local base = os.time() * 1000
    local offset = 0
    _G.system = {
        millis = function() return base + offset end,
        _advance = function(ms) offset = offset + ms end,
    }
end

-- capability mock：按注册的 matcher 响应 http_request
-- matcher: {method=?, path_contains=..., respond=function(opts)->output_string}
function M.setup_capability()
    local matchers = {}
    local calls = {}
    _G.capability = {
        _matchers = matchers,
        _calls = calls,
        _reset = function()
            for i = #matchers, 1, -1 do matchers[i] = nil end
            for i = #calls, 1, -1 do calls[i] = nil end
        end,
    }
    M.mock_http = {
        -- 添加 matcher（先注册先匹配）
        on = function(matcher) table.insert(matchers, matcher) return matcher end,
        -- 清空全部 matcher
        clear = function()
            for i = #matchers, 1, -1 do matchers[i] = nil end
        end,
        -- 便捷：返回业务成功 JSON
        ok = function(method, path_contains, data)
            return M.mock_http.on({
                method = method,
                path_contains = path_contains,
                respond = function()
                    return "HTTP 200\n" .. json.encode({ success = true, code = "200", msg = "ok", data = data })
                end,
            })
        end,
        -- 便捷：业务失败
        biz_err = function(method, path_contains, code, msg)
            return M.mock_http.on({
                method = method,
                path_contains = path_contains,
                respond = function()
                    return "HTTP 200\n" .. json.encode({ success = false, code = code or "500", msg = msg or "biz error" })
                end,
            })
        end,
        -- 便捷：HTTP 错误
        http_err = function(method, path_contains, status)
            return M.mock_http.on({
                method = method,
                path_contains = path_contains,
                respond = function()
                    return "HTTP " .. tostring(status) .. "\nerror"
                end,
            })
        end,
    }
    _G.capability.call = function(name, opts)
        if name ~= "http_request" then return false, nil, "unsupported cap" end
        table.insert(calls, opts)
        for _, m in ipairs(matchers) do
            local method_ok = not m.method or (opts.method or "GET") == m.method
            local path_ok = not m.path_contains
                or (opts.url or ""):find(m.path_contains, 1, true) ~= nil
            if method_ok and path_ok then
                return true, m.respond(opts), nil
            end
        end
        return false, nil, "no matcher for " .. tostring(opts.url)
    end
end

-- 标准凭证（JWT exp 2099 年）
function M.setup_credentials(house_id)
    _G.storage_reset()
    local header = "eyJhbGciOiJIUzI1NiJ9"
    local payload = json.encode({ exp = 4102444800, sub = "test-user" })
    -- base64url(payload) 手工构造：用标准 base64 后替换字符太麻烦，直接走 jwt_exp 的解析路径
    -- 为简化，用 base64url 编码实现内联（仅测试用）
    local b64 = M.base64url(payload)
    local token = header .. "." .. b64 .. ".sig"
    require("auth").save_binding({
        authorization = token,
        region = "cn",
        house_id = house_id or "house-1",
        client_id = "client-1",
        biz_type = "0",
        house_name = "我的家",
    })
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
function M.base64url(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = {
            B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1),
            B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1),
            B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1),
            B64:sub(n % 64 + 1, n % 64 + 1),
        }
        if not b then chars[3] = "="; chars[4] = "=" end
        if b and not c then chars[4] = "=" end
        out[#out + 1] = table.concat(chars)
    end
    return table.concat(out)
end

-- 读仓库内文件（相对仓库根）
function M.read_file(rel)
    local f = io.open(rel, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- 断言
local failures = 0
local checks = 0
function M.assert(cond, msg)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. tostring(msg or "assertion failed") .. "\n")
    end
end

function M.assert_eq(actual, expected, msg)
    checks = checks + 1
    if actual ~= expected then
        failures = failures + 1
        io.stderr:write(string.format("FAIL: %s\n  expected: %s\n  actual:   %s\n",
            tostring(msg or "value not equal"),
            tostring(expected), tostring(actual)))
    end
end

function M.assert_deep_eq(actual, expected, msg)
    checks = checks + 1
    local a, e = json.encode(actual), json.encode(expected)
    if a ~= e then
        failures = failures + 1
        io.stderr:write(string.format("FAIL: %s\n  expected: %s\n  actual:   %s\n",
            tostring(msg or "deep not equal"), e, a))
    end
end

function M.summary()
    print(string.format("checks: %d, failures: %d", checks, failures))
    return failures == 0
end

return M
