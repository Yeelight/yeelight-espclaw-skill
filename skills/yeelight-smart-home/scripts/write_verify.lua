-- write_verify.lua：写后读验证。读节点/设备当前属性，比对期望值。
local util = require("util")
local http = require("http")
local auth = require("auth")

local M = {}

M.VERIFY_RETRIES = 3
M.VERIFY_DELAY_MS = 400

M.PROP_ID = {
    power = "p", brightness = "l", color = "c", color_temperature = "ct",
    curtain_position = "tp",
}

M.NODE_TYPE = { room = 1, device = 2, group = 3, mesh_group = 4, home = 5 }

local function house_id_of(opts)
    local house_id = opts and opts.house_id
    if house_id then return tostring(house_id) end
    local creds, why = auth.require_credentials()
    if not creds then return nil, why end
    return tostring(auth.default_house_id(creds) or ""), nil
end

-- 读属性列表。node_type 数字；device 走 /v1/controll/device 专用端点。
-- 返回 ok, props(propId->value)|nil, err
function M.read_properties(node_type, node_id, opts)
    opts = opts or {}
    local path
    if node_type == M.NODE_TYPE.device then
        path = "/v1/controll/device/" .. util.url_escape(tostring(node_id)) .. "/r/properties"
    else
        local house_id, why = house_id_of(opts)
        if not house_id or house_id == "" then
            return false, nil, { code = why or "E_NO_HOUSE" }
        end
        path = string.format("/v1/open/control/house/%s/control/%d/%s/r/properties",
            util.url_escape(house_id), node_type, util.url_escape(tostring(node_id)))
    end
    local ok, data, err = http.request({ method = "POST", path = path, body = {} })
    if not ok then return false, nil, err end
    local props = {}
    local d = type(data) == "table" and (data.data or data) or {}
    if type(d) == "table" then
        local list = d.properties or d.props or {}
        if type(list) == "table" then
            for _, p in ipairs(list) do
                if type(p) == "table" and (p.propId or p.prop) then
                    props[tostring(p.propId or p.prop)] = p.value
                end
            end
        end
        if d.value ~= nil and d.propId then
            props[tostring(d.propId)] = d.value
        end
    end
    return true, props, nil
end

local function value_matches(expected, actual)
    if expected == nil then return true end
    if type(expected) == "number" and type(actual) == "number" then
        return math.abs(expected - actual) <= 1
    end
    if type(expected) == "boolean" or type(actual) == "boolean" then
        return tostring(expected) == tostring(actual)
    end
    if type(expected) == "string" and type(actual) == "string" then
        return expected:lower() == actual:lower()
    end
    return tostring(expected) == tostring(actual)
end

-- 验证单属性，重试。返回 verified(bool), actual
function M.verify(node_type, node_id, prop_semantic, expected, opts)
    opts = opts or {}
    local prop_id = M.PROP_ID[prop_semantic] or prop_semantic
    local retries = opts.retries or M.VERIFY_RETRIES
    local delay = opts.delay_ms or M.VERIFY_DELAY_MS
    local last_actual = nil
    for i = 1, retries do
        if i > 1 then util.sleep(delay) end
        local ok, props = M.read_properties(node_type, node_id, opts)
        if ok and props ~= nil then
            local actual = props[tostring(prop_id)]
            last_actual = actual
            if value_matches(expected, actual) then return true, actual end
        end
    end
    return false, last_actual
end

return M
