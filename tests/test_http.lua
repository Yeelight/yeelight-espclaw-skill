-- tests/test_http.lua
local mock = require("tests.mock")
local http = require("http")

_G.storage_reset()
mock.setup_credentials("house-1")
_G.capability._reset()

-- 业务成功 + data 提取
mock.mock_http.ok("POST", "/v1/house/r/list", { houses = { { id = "h1", name = "我的家" } } })
local ok, data, err = http.request({ method = "POST", path = "/v1/house/r/list", body = {} })
mock.assert(ok, "house list ok")
mock.assert_eq(err, nil, "house list no err")
mock.assert(data.data and data.data.houses and #data.data.houses == 1, "houses extracted")

-- 数组包装
mock.mock_http.on({
    method = "POST", path_contains = "/v1/array/echo",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, code = "0", data = { { id = 1 } } })
    end,
})
-- data 是对象的情况已覆盖；直接数组的情况：
mock.mock_http.on({
    method = "POST", path_contains = "/v1/array/bare",
    respond = function()
        return "HTTP 200\n" .. json.encode({ { id = 1 }, { id = 2 } })
    end,
})
ok, data, err = http.request({ method = "POST", path = "/v1/array/bare", body = {} })
mock.assert(ok, "bare array ok")
mock.assert(data.data and #data.data == 2, "bare array wrapped")

-- 业务失败
mock.mock_http.biz_err("POST", "/v1/fail", "500", "something wrong")
ok, data, err = http.request({ method = "POST", path = "/v1/fail", body = {} })
mock.assert(not ok, "business fail not ok")
mock.assert_eq(err.code, "E_BUSINESS", "E_BUSINESS code")
mock.assert(err.message:find("something wrong", 1, true) ~= nil, "business message")

-- HTTP 401 -> auth
mock.mock_http.http_err("POST", "/v1/unauth", 401)
ok, data, err = http.request({ method = "POST", path = "/v1/unauth", body = {} })
mock.assert(not ok, "401 not ok")
mock.assert_eq(err.code, "E_AUTH_EXPIRED", "401 -> E_AUTH_EXPIRED")

mock.mock_http.http_err("POST", "/v1/forbidden", 403)
ok, data, err = http.request({ method = "POST", path = "/v1/forbidden", body = {} })
mock.assert_eq(err.code, "E_FORBIDDEN", "403 -> E_FORBIDDEN")

mock.mock_http.http_err("POST", "/v1/err500", 500)
ok, data, err = http.request({ method = "POST", path = "/v1/err500", body = {} })
mock.assert_eq(err.code, "E_HTTP", "500 -> E_HTTP")

-- 未绑定
_G.storage_reset()
ok, data, err = http.request({ method = "POST", path = "/v1/house/r/list", body = {} })
mock.assert(not ok, "no creds not ok")
mock.assert_eq(err.code, "E_NO_AUTH", "no creds -> E_NO_AUTH")

-- header 注入与 token 不泄漏
_G.storage_reset()
mock.setup_credentials("house-1")
local cap_err = mock.mock_http.on({
    method = "POST", path_contains = "/v1/house/r/list",
    respond = function(opts)
        -- 检查 header
        mock.assert(opts.headers.Authorization ~= nil, "Authorization header set")
        mock.assert(opts.headers.Authorization:find("^Bearer ") ~= nil, "Bearer prefix")
        mock.assert_eq(opts.headers.houseId, "house-1", "houseId header")
        mock.assert_eq(opts.headers["house-id"], "house-1", "house-id header")
        mock.assert_eq(opts.headers.bizType, "0", "bizType header")
        mock.assert_eq(opts.headers["Client-Id"], "client-1", "client id header")
        mock.assert(opts.url:find("api.yeelight.com", 1, true) ~= nil, "base url cn")
        return "HTTP 200\n" .. json.encode({ success = true, data = {} })
    end,
})
ok, data, err = http.request({ method = "POST", path = "/v1/house/r/list", body = {} })
mock.assert(ok, "header check request ok")

-- token 不出现在错误信息
mock.mock_http.on({
    method = "POST", path_contains = "/v1/leak",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = false, msg = "Bearer sk-secret-token leaked" })
    end,
})
ok, data, err = http.request({ method = "POST", path = "/v1/leak", body = {} })
mock.assert(err.message:find("***", 1, true) ~= nil, "leaked bearer redacted")
