-- tests/test_router.lua：router 分发与本地能力
local mock = require("tests.mock")
local router = require("router")
local auth = require("auth")

_G.storage_reset()
mock.setup_credentials("house-1")

-- 未注册 intent -> not_supported
local resp = router.dispatch({
    contractVersion = "1.0", requestId = "r1", locale = "zh-CN",
    utterance = "", intent = "no.such.intent", parameters = {},
})
mock.assert_eq(resp.status, "not_supported", "unknown intent not_supported")

-- intent.explain 本地
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r2", locale = "zh-CN",
    utterance = "", intent = "intent.explain",
    parameters = { targetIntent = "light.power.set" },
})
mock.assert_eq(resp.status, "success", "intent.explain ok")
mock.assert_eq(resp.result.supported, true, "light.power.set supported")
mock.assert_eq(resp.result.risk, "R1", "light risk")

resp = router.dispatch({
    contractVersion = "1.0", requestId = "r3", locale = "zh-CN",
    utterance = "", intent = "intent.explain",
    parameters = { targetIntent = "no.such" },
})
mock.assert_eq(resp.result.supported, false, "unknown unsupported")

-- memory 本地（storage mock）
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r4", locale = "zh-CN",
    utterance = "", intent = "memory.remember",
    parameters = { content = "我喜欢 4000K 色温" },
})
mock.assert_eq(resp.status, "success", "memory remember ok")

resp = router.dispatch({
    contractVersion = "1.0", requestId = "r5", locale = "zh-CN",
    utterance = "", intent = "memory.list", parameters = {},
})
mock.assert_eq(resp.status, "success", "memory list ok")
mock.assert_eq(#resp.result.items, 1, "one memory")

-- 重复内容去重
router.dispatch({
    contractVersion = "1.0", requestId = "r6", locale = "zh-CN",
    utterance = "", intent = "memory.remember",
    parameters = { content = "我喜欢 4000K 色温" },
})
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r7", locale = "zh-CN",
    utterance = "", intent = "memory.list", parameters = {},
})
mock.assert_eq(#resp.result.items, 1, "dedup memory")

-- 暂停/恢复
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r8", locale = "zh-CN",
    utterance = "", intent = "memory.pause", parameters = {},
})
mock.assert_eq(resp.result.paused, true, "memory paused")
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r9", locale = "zh-CN",
    utterance = "", intent = "memory.list", parameters = {},
})
mock.assert_eq(resp.result.paused, true, "list shows paused")

-- 忘记
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r10", locale = "zh-CN",
    utterance = "", intent = "memory.forget",
    parameters = { content = "4000K" },
})
mock.assert_eq(resp.result.removed, 1, "memory removed")

-- bind.account：新二维码（未绑定状态）
_G.storage_reset()
_G.capability._reset()
mock.mock_http.on({
    method = "POST", path_contains = "/apis/account/user/scan-login/query/qrcode/",
    respond = function()
        return "HTTP 200\n" .. json.encode({ success = true, data = {
            qrCodeId = "qr-x", status = "WAITING", expireAt = 999999999999,
            qrContent = "https://app.yeelight.com/bind?qr=qr-x",
        } })
    end,
})
resp = router.dispatch({
    contractVersion = "1.0", requestId = "r11", locale = "zh-CN",
    utterance = "", intent = "bind.account", parameters = {},
})
mock.assert_eq(resp.status, "clarification_required", "bind.account -> clarification")
mock.assert(resp.clarification.resume ~= nil, "bind resume info")
