-- i18n.lua：面向用户的文案。中文优先，未命中键回退英文键，再回退键名。
local M = {}

M.zh = {
    -- 通用
    ok = "已完成。",
    not_bound = "尚未绑定 Yeelight 账号。请先在设备上运行账号绑定（bind.account），用 Yeelight App 扫码。",
    auth_expired = "登录已过期，请重新运行账号绑定（bind.account）。",
    no_house = "未找到可用家庭。请确认账号下已创建 Pro 家庭。",
    no_house_selected = "尚未选择家庭，请先指定 homeName 或在绑定后选择默认家庭。",
    multi_house = "找到 %d 个家庭，请选择：%s。",
    not_found = "没有找到「%s」。",
    not_supported = "该功能暂不支持：%s。",
    blocked = "该操作被安全策略拦截：%s。",
    error = "操作失败：%s。",
    http_error = "网络请求失败（HTTP %d）：%s。",
    partial = "部分成功：%s",
    ambiguous = "「%s」匹配到 %d 个候选，请选择：%s。",
    invalid_param = "参数无效：%s。",
    missing_param = "缺少参数：%s。",
    need_confirm = "%s 属于高危操作，请确认后重试（parameters.confirmed=true）。",
    sensitive_prop = "属性 %s 为敏感属性，已拦截。",
    write_unverified = "写入已提交，但读回验证未通过或暂不可验证。",
    -- 绑定
    bind_created = "请在设备屏幕上用 Yeelight App 扫码完成绑定；完成后重新运行 bind.account 查询结果。",
    bind_pending = "还未扫码，请在设备屏幕上用 Yeelight App 扫码后重试。",
    bind_expired = "二维码已过期，请重新运行 bind.account 生成新码。",
    bind_done = "账号绑定成功：家庭「%s」。",
    bind_failed = "绑定失败：%s。",
    -- 展示
    home_list = "共 %d 个家庭：%s。",
    room_list = "家庭「%s」共 %d 个房间：%s。",
    device_list = "共 %d 个设备（显示前 %d 个）：%s。",
    entity_list = "共 %d 个实体（显示前 %d 个）：%s。",
    group_list = "共 %d 个灯组：%s。",
    scene_list = "共 %d 个情景：%s。",
    scene_executed = "情景「%s」已执行。",
    light_set = "%s 已设置。",
    state_query = "%s 当前状态：%s。",
    memory_saved = "已记住：%s",
    memory_list = "已保存 %d 条记忆。",
    memory_cleared = "已删除对应记忆。",
    -- 截断提示
    truncated = "（仅显示前 %d 项，可用搜索词或分页缩小范围）",
}

M.en = {
    ok = "Done.",
    not_bound = "No Yeelight account bound. Run bind.account and scan the QR code with the Yeelight app.",
    auth_expired = "Session expired. Re-run bind.account.",
    no_house = "No home found. Create a Pro home in your account first.",
    no_house_selected = "No home selected. Specify homeName first.",
    multi_house = "Found %d homes, choose one: %s.",
    not_found = "'%s' not found.",
    not_supported = "Not supported yet: %s.",
    blocked = "Blocked by safety policy: %s.",
    error = "Operation failed: %s.",
    http_error = "HTTP request failed (%d): %s.",
    partial = "Partially completed: %s",
    ambiguous = "'%s' matches %d candidates, choose one: %s.",
    invalid_param = "Invalid parameter: %s.",
    missing_param = "Missing parameter: %s.",
    need_confirm = "%s is destructive; confirm and retry (parameters.confirmed=true).",
    sensitive_prop = "Property %s is sensitive and blocked.",
    write_unverified = "Write submitted but verification failed or unavailable.",
    bind_created = "Scan the QR code on the device screen with the Yeelight app, then re-run bind.account.",
    bind_pending = "Not scanned yet. Scan the QR code and retry.",
    bind_expired = "QR code expired. Re-run bind.account.",
    bind_done = "Account bound: home '%s'.",
    bind_failed = "Binding failed: %s.",
    home_list = "%d homes: %s.",
    room_list = "Home '%s' has %d rooms: %s.",
    device_list = "%d devices (showing %d): %s.",
    entity_list = "%d entities (showing %d): %s.",
    group_list = "%d groups: %s.",
    scene_list = "%d scenes: %s.",
    scene_executed = "Scene '%s' executed.",
    light_set = "%s updated.",
    state_query = "%s state: %s.",
    memory_saved = "Remembered: %s",
    memory_list = "%d memories saved.",
    memory_cleared = "Memory removed.",
    truncated = "(showing first %d items; use a search term or paging)",
}

local function fmt(template, params)
    params = params or {}
    local i = 0
    return (template:gsub("%%s", function()
        i = i + 1
        return tostring(params[i] or "")
    end))
end

function M.t(key, locale, ...)
    local pack = (locale and locale:sub(1, 2) == "en") and M.en or M.zh
    local template = pack[key] or M.zh[key] or key
    return fmt(template, { ... })
end

return M
