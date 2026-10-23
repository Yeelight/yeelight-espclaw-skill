-- qr.lua：二维码展示。优先设备屏（lvgl），失败回退为文本说明。
-- 仅展示 qrContent，不展示 token。
local M = {}

local function show_lvgl(content)
    local ok = pcall(function()
        local lvgl = require("lvgl")
        local scr = lvgl.screen_active()
        if not scr then return end
        local label = lvgl.label(scr, {})
        label:set_text("Yeelight Bind\nScan with Yeelight App")
        local qr = lvgl.qrcode(scr, {})
        qr:set_size(220, 220)
        qr:update(content)
    end)
    return ok
end

-- 返回展示结果 {mode="screen"|"text", content=?}
function M.display(info)
    if type(info) ~= "table" or not info.qrContent then
        return { mode = "text", content = nil }
    end
    if M.display_lvgl ~= false and show_lvgl(info.qrContent) then
        return { mode = "screen", content = info.qrContent }
    end
    return { mode = "text", content = info.qrContent }
end

return M
