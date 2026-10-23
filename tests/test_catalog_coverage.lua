-- tests/test_catalog_coverage.lua：intent-catalog.json 中的每个 intent 必须有明确分类
local mock = require("tests.mock")
local router = require("router")
local catalog = json.decode(mock.read_file("skills/yeelight-smart-home/assets/intent-catalog.json"))

mock.assert(catalog ~= nil and type(catalog.intents) == "table", "catalog loaded")
mock.assert(#catalog.intents > 100, "catalog has many intents: " .. tostring(#catalog.intents))

local supported, unsupported = 0, 0
for _, intent in ipairs(catalog.intents) do
    local info = router.intent_info(intent)
    if info then
        supported = supported + 1
    else
        unsupported = unsupported + 1
        -- 未支持的 intent 至少应能进入 dispatch 并返回 not_supported（而不是崩溃）
        local resp = router.dispatch({
            contractVersion = "1.0", requestId = "cov-" .. intent, locale = "zh-CN",
            utterance = "", intent = intent, parameters = {},
        })
        mock.assert(resp ~= nil, intent .. " dispatch returns response")
        mock.assert(resp.status == "not_supported" or resp.status == "auth_required"
            or resp.status == "error" or resp.status == "blocked"
            or resp.status == "clarification_required",
            intent .. " classified as not_supported/auth/error, got " .. tostring(resp.status))
    end
end
print(string.format("catalog: %d supported, %d unsupported of %d",
    supported, unsupported, #catalog.intents))
mock.assert(supported > 100, "most intents have handlers")
