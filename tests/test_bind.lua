-- tests/test_bind.lua
local mock = require("tests.mock")
local bind = require("bind")
local auth = require("auth")

_G.storage_reset()
_G.capability._reset()

-- 创建二维码
mock.mock_http.on({
    method = "POST", path_contains = "/apis/account/user/scan-login/query/qrcode/espclaw-testdev",
    respond = function(opts)
        mock.assert_eq(opts.headers.bizType, "0", "bizType header on qr create")
        return "HTTP 200\n" .. json.encode({
            success = true, data = {
                qrCodeId = "qr-1", status = "WAITING", expireAt = 999999999999,
                qrContent = "https://app.yeelight.com/bind?qr=qr-1",
            },
        })
    end,
})

local ok, state, info = bind.run({ deviceId = "espclaw-testdev", region = "cn" })
mock.assert(ok, "bind create ok")
mock.assert_eq(state, "created", "bind state created")
mock.assert_eq(info.qrCodeId, "qr-1", "qrCodeId")
mock.assert_eq(info.deviceId, "espclaw-testdev", "deviceId kept")

-- 轮询：pending
mock.mock_http.on({
    method = "POST", path_contains = "/apis/account/user/scan-login/check/qrcode/qr-1",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { qrCodeId = "qr-1", status = "WAITING" } })
    end,
})
local ok2, state2 = bind.run({ region = "cn", resume = { qrCodeId = "qr-1", deviceId = "espclaw-testdev" } })
mock.assert(ok2, "check ok")
mock.assert_eq(state2, "pending", "pending while not scanned")

-- 扫码成功 -> 保存凭证（清掉旧 check matcher）
mock.mock_http.clear()
mock.mock_http.on({
    method = "POST", path_contains = "/apis/account/user/scan-login/check/qrcode/qr-1",
    respond = function()
        return "HTTP 200\n" .. json.encode({
            success = true, data = {
                qrCodeId = "qr-1", status = "LOGIN",
                token = { authorization = "Bearer test-token-abc", clientId = "client-9" },
                houseId = "house-77",
            },
        })
    end,
})
local ok3, state3, detail = bind.run({ region = "cn", resume = { qrCodeId = "qr-1", deviceId = "espclaw-testdev" } })
mock.assert(ok3, "login ok")
mock.assert_eq(state3, "login", "login state")
local creds = auth.load()
mock.assert(creds ~= nil, "credentials saved")
mock.assert_eq(creds.house_id, "house-77", "house id saved")
mock.assert_eq(creds.client_id, "client-9", "client id saved")
mock.assert(creds.authorization:find("^Bearer ") ~= nil, "bearer normalized")

-- token 不落日志（输出脱敏）
local redacted = require("util").redact("Bearer test-token-abc")
mock.assert(redacted:find("test-token-abc", 1, true) == nil, "token redacted")

-- 过期
mock.mock_http.on({
    method = "POST", path_contains = "/apis/account/user/scan-login/check/qrcode/qr-exp",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = { qrCodeId = "qr-exp", status = "EXPIRED" } })
    end,
})
local ok4, state4 = bind.run({ region = "cn", resume = { qrCodeId = "qr-exp" } })
mock.assert(not ok4, "expired not ok")
mock.assert_eq(state4, "expired", "expired state")

-- 未登录凭证缺失
_G.storage_reset()
local c2, why = auth.require_credentials()
mock.assert(c2 == nil and why == "not_bound", "no creds -> not_bound")
