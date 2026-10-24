-- bind.lua：QR 扫码绑定。创建二维码 -> 展示 -> 轮询 -> 落盘凭证。
local util = require("util")
local auth = require("auth")
local http = require("http")

local M = {}

M.POLL_INTERVAL_MS = 3000
M.POLL_MAX_MS = 180000

-- 设备号需 MAC 形态（App 扫码协议 cli&MAC&qrCodeId 依赖）；缺省生成随机 MAC
function M.ensure_device_id(opts)
    local device = opts and opts.deviceId
    if not device or device == "" then
        local creds = auth.load()
        device = creds and creds.device
    end
    if not device or device == "" then
        math.randomseed((system and system.millis and system.millis() or os.time() * 1000) % 2147483647)
        device = string.format("F8:24:41:%02X:%02X:%02X",
            math.random(0, 255), math.random(0, 255), math.random(0, 255))
    end
    return M.normalize_device_mac(device)
end

-- MAC 规范化：12 位裸 hex 插冒号，统一大写（对齐 Runtime NormalizeDeviceMAC）
function M.normalize_device_mac(raw)
    local trimmed = util.trim(tostring(raw or ""))
    local upper = trimmed:upper()
    local bare = upper:gsub(":", "")
    if #bare == 12 and bare:match("^%x+$") then
        return bare:gsub("(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)", "%1:%2:%3:%4:%5:%6")
    end
    if upper:match("^%x%x(:%x%x){5}$") then
        return upper
    end
    -- 非 MAC 形态：原样保留（测试/自定义 id）
    return trimmed
end

-- 二维码内容：cli&MAC&qrCodeId（对齐 Runtime BuildQRPayload）
function M.build_qr_payload(qr_code_id, device)
    return "cli&" .. M.normalize_device_mac(device) .. "&" .. tostring(qr_code_id)
end

-- 创建二维码。返回 ok, info|err
-- info = {qrCodeId, status, expireAt, deviceId, qrContent}
function M.create(opts)
    opts = opts or {}
    local device = M.ensure_device_id(opts)
    local ok, data, err = http.request({
        method = "POST",
        base = auth.account_base(opts.region),
        path = "/apis/account/user/scan-login/query/qrcode/" .. util.url_escape(device),
        headers = { ["bizType"] = http.sanitize_biz_type(opts.biz_type) },
        no_auth = true,
        body = {},
    })
    if not ok then return false, nil, err end
    local d = data.data or data
    return true, {
        qrCodeId = d.qrCodeId,
        status = d.status,
        expireAt = d.expireAt,
        deviceId = device,
        -- App 扫码内容 = cli&MAC&qrCodeId（云端无 qrContent 字段，本地构造）
        qrContent = M.build_qr_payload(d.qrCodeId, device),
        raw = d,
    }, nil
end

-- 轮询一次。返回 status: "pending" | "login" | "expired" | "failed"
function M.check(qr_code_id, opts)
    opts = opts or {}
    local ok, data, err = http.request({
        method = "POST",
        base = auth.account_base(opts.region),
        path = "/apis/account/user/scan-login/check/qrcode/" .. util.url_escape(qr_code_id),
        headers = { ["bizType"] = http.sanitize_biz_type(opts.biz_type) },
        no_auth = true,
        body = {},
    })
    if not ok then
        -- 二维码接口对过期码可能直接报业务错误
        if err and err.code == "E_BUSINESS" then
            return false, "expired", { message = err.message }
        end
        return false, "failed", { message = err and err.message or "network error" }
    end
    local d = data.data or data
    local status = util.trim(tostring(d.status or "")):upper()
    if status == "LOGIN" then
        return true, "login", d
    elseif status == "EXPIRED" then
        return false, "expired", { message = "qr expired" }
    end
    return true, "pending", d
end

-- 提取凭证并保存
function M.save_login(info, opts)
    opts = opts or {}
    local token = type(info.token) == "table" and info.token or {}
    local authorization = token.authorization or token.accessToken or token.token
    if not authorization or authorization == "" then
        return false, { message = "no token in login response" }
    end
    local creds, err = auth.save_binding({
        authorization = authorization,
        region = opts.region or "cn",
        house_id = info.houseId or token.houseId or opts.house_id,
        client_id = token.clientId or token.clientID or info.clientId,
        biz_type = http.sanitize_biz_type(opts.biz_type),
        device = opts.deviceId,
        house_name = opts.house_name,
    })
    if not creds then return false, { message = err or "save failed" } end
    return true, creds, nil
end

-- 绑定主流程（供 api 层调用）：
-- opts: {deviceId, region, biz_type, resume={qrCodeId, deviceId}, poll_ms, on_created(info)}
-- 返回 ok, state("created"|"pending"|"login"|"expired"|"failed"), detail, err
function M.run(opts)
    opts = opts or {}
    local resume = opts.resume or {}
    local qr_code_id = resume.qrCodeId
    local device_id = resume.deviceId or M.ensure_device_id(opts)
    if not qr_code_id then
        local ok, info, err = M.create({ deviceId = device_id, region = opts.region, biz_type = opts.biz_type })
        if not ok then return false, "failed", nil, err end
        if opts.on_created then pcall(opts.on_created, info) end
        return true, "created", info, nil
    end
    local deadline = util.now_ms() + (opts.poll_ms or 0)
    while true do
        local ok, state, detail = M.check(qr_code_id, { region = opts.region, biz_type = opts.biz_type })
        if state == "login" and ok and detail then
            local saved, creds, serr = M.save_login(detail, {
                region = opts.region, biz_type = opts.biz_type, deviceId = device_id,
            })
            if not saved then
                return false, "failed", detail, serr
            end
            return true, "login", { houseId = creds.house_id, houseName = creds.house_name }, nil
        elseif state == "expired" then
            return false, "expired", detail, nil
        elseif state == "failed" then
            return false, "failed", detail, nil
        end
        if deadline > 0 and util.now_ms() >= deadline then
            return true, "pending", nil, nil
        end
        util.sleep(M.POLL_INTERVAL_MS)
    end
end

return M
