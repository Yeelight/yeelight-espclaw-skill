-- tools/gen_intent_map.lua：以 router.lua 为唯一事实来源生成 assets/intent-map.json
-- 用法：lua tools/gen_intent_map.lua
package.path = "skills/yeelight-smart-home/scripts/?.lua;skills/yeelight-smart-home/scripts/?/init.lua;tests/?.lua;" .. package.path

local mock = require("tests.mock")
mock.setup_globals()
local json = _G.json

local router = require("router")
local risk = require("risk")
local contract = require("contract")

local catalog = json.decode(mock.read_file("skills/yeelight-smart-home/assets/intent-catalog.json"))

local LEVELS = {
    v1 = {
        "home.summary", "home.list", "home.search", "home.detail.get", "home.stat.get",
        "account.info", "room.list", "room.search", "room.detail.get", "area.list", "area.detail.get",
        "entity.list", "entity.get", "entity.capabilities", "device.list", "device.detail.get",
        "device.complex.get", "device.shadow.get", "device.attr.list",
        "group.list", "group.search", "group.detail.get", "group.complex.get",
        "scene.list", "scene.search", "scene.detail.get", "scene.execute", "scene.test",
        "state.query", "state.batch.query",
        "light.power.set", "light.brightness.set", "light.brightness.adjust",
        "light.color_temperature.set", "light.color_temperature.adjust", "light.color.set",
        "node.property.set", "node.property.toggle", "node.action.execute", "node.properties.set",
        "gateway.list", "gateway.detail.get", "gateway.thread.get",
        "sensor.list", "sensor.event.list", "device.energy.summary", "device.weather.get",
        "message.list", "diagnose.device", "diagnose.gateway",
        "memory.remember", "memory.list", "memory.pause", "memory.resume", "memory.forget",
        "recommendation.list", "recommendation.record", "recommendation.feedback",
        "operation.lesson.record", "operation.lesson.list", "intent.explain",
        "bind.account",
    },
    v2 = {
        "room.create", "room.rename", "room.update", "room.batch_create", "room.batch_update",
        "room.delete", "room.batch_delete", "room.area.configure",
        "area.create", "area.update", "area.delete", "area.batch_delete",
        "group.create", "group.update", "group.members.update", "group.delete", "group.batch_delete",
        "scene.create", "scene.update", "scene.delete", "scene.batch_delete",
        "automation.list", "automation.detail.get", "automation.create", "automation.update",
        "automation.enable", "automation.disable", "automation.delete",
        "device.rename", "device.move", "device.move_room.batch", "device.remove", "device.unbind",
        "entity.rename.batch", "home.create", "home.update", "home.delete",
        "home.member.list", "home.member.invite", "home.member.configure",
        "home.member.remove", "home.member.transfer", "home.member.quit",
        "home.lock_all", "home.unlock_all", "home.sort.list", "home.sort.configure",
        "panel.list", "panel.get", "panel.click", "panel.button.configure",
        "panel.button_event.update", "panel.button_event.batch_update", "panel.button_event.reset",
        "knob.get", "knob.configure", "knob.reset",
        "gateway.configure", "gateway.delete", "favorite.list", "favorite.add",
        "favorite.update", "favorite.delete", "favorite.batch_add",
    },
    v3 = {
        "thing.schema.list", "thing.schema.get", "thing.schema.event.list",
        "thing.product.info.batch_get", "product.pedia.search", "thing.product_faq.list",
        "lighting.design.plan", "lighting.design.apply", "lighting.flow.execute",
        "diagnose.scene", "diagnose.automation", "automation.explain", "automation.capabilities",
        "upgrade.file.list", "upgrade.progress.get", "ai_voice.list",
        "device.property.set", "node.property.batch_set", "lighting.experience.apply",
        "device.storage.get",
    },
}

local level_of = {}
for level, intents in pairs(LEVELS) do
    for _, intent in ipairs(intents) do level_of[intent] = level end
end

local entries = {}
for _, intent in ipairs(catalog.intents) do
    local info = router.intent_info(intent)
    local entry = {
        intent = intent,
        supported = info ~= nil,
        module = info and info.module or nil,
        risk = risk.risk_of(intent),
        level = level_of[intent] or (info and "v2" or nil),
    }
    entries[#entries + 1] = entry
end

local out = {
    contractVersion = contract.CONTRACT_VERSION,
    generatedBy = "tools/gen_intent_map.lua (router.lua 为唯一事实来源)",
    intents = entries,
}

local file = assert(io.open("skills/yeelight-smart-home/assets/intent-map.json", "w"))
file:write(json.encode(out))
file:close()
print("intent-map.json generated: " .. #entries .. " intents")
