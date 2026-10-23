-- topology.lua：家庭拓扑缓存（设备 + 房间 + 灯组），TTL 内复用，写操作后失效。
local util = require("util")
local auth = require("auth")
local http = require("http")

local M = {}

M.TTL_MS = 60000
M._cache = nil  -- {loaded_at, house_id, rooms, devices, groups}

-- 从响应的 data/data.data 中提取 rows（容器名兼容）
function M.extract_rows(data)
    local candidates = { "rows", "devices", "deviceList", "rooms", "roomList", "groups", "groupList", "list" }
    local roots = {}
    if type(data) == "table" then
        roots[#roots + 1] = data
        if type(data.data) == "table" then roots[#roots + 1] = data.data end
    end
    for _, root in ipairs(roots) do
        for _, key in ipairs(candidates) do
            local v = root[key]
            if type(v) == "table" and (util.is_array(v) or #v > 0) then
                return v
            end
        end
    end
    return {}
end

local function fetch_rows(path_opts)
    local ok, data, err = http.request(path_opts)
    if not ok then return nil, err end
    local rows = {}
    for _, r in ipairs(M.extract_rows(data)) do rows[#rows + 1] = r end
    return rows, nil
end

function M.invalidate()
    M._cache = nil
end

-- 加载（或复用缓存）拓扑。house_id 缺省用绑定凭证的默认家庭。
-- 返回 ok, topology|nil, err|nil
function M.load(opts)
    opts = opts or {}
    local creds, why = auth.require_credentials()
    if not creds then return false, nil, { code = why == "auth_expired" and "E_AUTH_EXPIRED" or "E_NO_AUTH" } end
    local house_id = opts.house_id or auth.default_house_id(creds)
    if not house_id then
        return false, nil, { code = "E_NO_HOUSE", message = "no default house bound" }
    end
    if not opts.force and M._cache and M._cache.house_id == tostring(house_id)
        and util.now_ms() - M._cache.loaded_at < M.TTL_MS then
        return true, M._cache, nil
    end
    local rooms, err_r = fetch_rows({
        path = M.page_path_rooms(tostring(house_id)), method = "GET",
    }, house_id)
    if err_r then return false, nil, err_r end
    local devices, err_d = fetch_rows({
        path = "/v1/device/r/all", method = "POST", body = { houseId = tostring(house_id) },
    }, house_id)
    if err_d then return false, nil, err_d end
    -- 灯组 / 情景为尽力而为：失败不阻塞拓扑
    local ok_g, groups = pcall(fetch_rows, {
        path = "/v2/thing/manage/house/" .. util.url_escape(tostring(house_id)) .. "/group/r/info/1/100",
        method = "GET",
    }, house_id)
    if not ok_g then groups = {} end
    local ok_s, scenes = pcall(fetch_rows, {
        path = "/v1/scene/r/all", method = "POST", body = { houseId = tostring(house_id) },
    }, house_id)
    if not ok_s then scenes = {} end

    local room_by_id = {}
    for _, r in ipairs(rooms) do
        room_by_id[tostring(r.id or r.roomId)] = tostring(r.name or "")
    end
    local norm_devices = {}
    for _, d in ipairs(devices) do
        local room_id = tostring(d.roomId or (d.roomIds and d.roomIds[1]) or "")
        norm_devices[#norm_devices + 1] = {
            id = tostring(d.id or d.deviceId or ""),
            name = tostring(d.name or d.deviceName or ""),
            roomId = room_id,
            roomName = room_by_id[room_id] or tostring(d.roomName or ""),
            category = d.category or d.productCategory,
            nodeType = tonumber(d.nodeType) or 2,
            online = d.online,
            subDeviceList = d.subDeviceList or d.subDevices,
        }
    end
    M._cache = {
        loaded_at = util.now_ms(),
        house_id = tostring(house_id),
        rooms = rooms,
        devices = norm_devices,
        groups = groups or {},
        scenes = scenes or {},
    }
    return true, M._cache, nil
end

function M.page_path_rooms(house_id)
    return "/v2/thing/manage/house/" .. util.url_escape(house_id) .. "/room/r/info/1/100"
end

return M
