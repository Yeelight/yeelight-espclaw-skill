-- auth.lua：凭证读写与有效期校验。token 只在本模块与 http.lua 间流转。
local util = require("util")

local M = {}

M.DATA_DIR = "yeelight-smart-home"
M.CRED_FILE = M.DATA_DIR .. "/credentials.json"

M.REGIONS = {
    cn = "https://api.yeelight.com",
    sg = "https://api-sg.yeelight.com",
    us = "https://api-us.yeelight.com",
    eu = "https://api-de.yeelight.com",
    dev = "http://api-dev.yeedev.com",
}

-- storage 读写封装（测试环境注入 mock storage；均返回 ok, content）
local function read_file(rel)
    if not storage then return false, "no storage" end
    return storage.read_file(rel)
end

local function write_file(rel, content)
    if not storage then return false, "no storage" end
    if storage.mkdir then storage.mkdir(M.DATA_DIR) end
    return storage.write_file(rel, content)
end

function M.load()
    local ok, content = read_file(M.CRED_FILE)
    if not ok or type(content) ~= "string" or content == "" then return nil end
    local okd, data = pcall(function() return json.decode(content) end)
    if not okd or type(data) ~= "table" then return nil end
    return data
end

function M.save(creds)
    creds = creds or {}
    creds.updatedAt = util.now_ms()
    local ok, err = write_file(M.CRED_FILE, json.encode(creds))
    if not ok then return nil, err end
    return creds
end

function M.clear()
    write_file(M.CRED_FILE, "")
    return true
end

function M.is_configured()
    local creds = M.load()
    return creds ~= nil and creds.authorization ~= nil and creds.authorization ~= ""
end

-- 返回可用凭证或 nil, 原因 key
function M.require_credentials()
    local creds = M.load()
    if not creds or not creds.authorization then
        return nil, "not_bound"
    end
    local exp = util.jwt_exp(creds.authorization)
    if exp and exp * 1000 <= util.now_ms() then
        return nil, "auth_expired"
    end
    return creds
end

function M.region_base(region)
    return M.REGIONS[region or "cn"] or M.REGIONS.cn
end

function M.account_base(region)
    local base = M.region_base(region)
    return base:gsub("/apis/iot$", "")
end

function M.pedia_base()
    return "https://api.yeelight.com/apis/c"
end

-- 取默认家庭：绑定保存的 house_id；否则 nil
function M.default_house_id(creds)
    creds = creds or M.load() or {}
    return creds.house_id or creds.houseId
end

-- 绑定后保存统一入口
function M.save_binding(opts)
    opts = opts or {}
    local creds = {
        authorization = opts.authorization,   -- 已含 Bearer 前缀或裸 token 均可
        region = opts.region or "cn",
        house_id = opts.house_id,
        client_id = opts.client_id,
        biz_type = opts.biz_type or "0",
        device = opts.device,
        house_name = opts.house_name,
    }
    if creds.authorization and not creds.authorization:find("^Bearer%s") then
        creds.authorization = "Bearer " .. creds.authorization
    end
    return M.save(creds)
end

return M
