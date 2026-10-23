-- local.lua：本地能力（memory/recommendation/operation.lesson），存设备 storage 专用目录。
local util = require("util")

local M = {}

M.MEMORY_FILE = "yeelight-smart-home/memory.json"
M.RECO_FILE = "yeelight-smart-home/recommendation.json"
M.LESSON_FILE = "yeelight-smart-home/lesson.json"
M.MAX_ENTRIES = 50

local function read_json(path)
    if not storage then return nil end
    local ok, content = storage.read_file(path)
    if not ok or type(content) ~= "string" or content == "" then return {} end
    local okd, data = pcall(function() return json.decode(content) end)
    if not okd or type(data) ~= "table" then return {} end
    return data
end

local function write_json(path, data)
    if not storage then return false end
    if storage.mkdir then storage.mkdir("yeelight-smart-home") end
    return storage.write_file(path, json.encode(data))
end

-- ---- memory ----
-- entry: {content, kind?, tags?}
function M.memory_remember(entry)
    if type(entry) ~= "table" or not entry.content or util.trim(entry.content) == "" then
        return false, "content required"
    end
    local list = read_json(M.MEMORY_FILE)
    local item = {
        content = util.trim(tostring(entry.content)),
        kind = entry.kind or "preference",
        tags = entry.tags,
        at = util.now_ms(),
    }
    -- 完全同文去重
    for i, m in ipairs(list) do
        if m.content == item.content then
            table.remove(list, i)
            break
        end
    end
    list[#list + 1] = item
    while #list > M.MAX_ENTRIES do table.remove(list, 1) end
    return write_json(M.MEMORY_FILE, list), item
end

function M.memory_list()
    return read_json(M.MEMORY_FILE)
end

function M.memory_forget(query)
    local list = read_json(M.MEMORY_FILE)
    local out, removed = {}, 0
    for _, m in ipairs(list) do
        if query and m.content:find(query, 1, true) then
            removed = removed + 1
        else
            out[#out + 1] = m
        end
    end
    if removed > 0 then write_json(M.MEMORY_FILE, out) end
    return removed
end

function M.memory_set_paused(paused)
    local list = read_json(M.MEMORY_FILE)
    local flag = { paused = paused, at = util.now_ms() }
    -- 单独存暂停标记于同文件 meta（首元素特殊）——简化：写独立键由调用方读
    write_json("yeelight-smart-home/memory_pause.json", flag)
    list = nil
    return true
end

function M.memory_is_paused()
    local flag = read_json("yeelight-smart-home/memory_pause.json")
    return flag and flag.paused == true
end

-- ---- recommendation ----
function M.recommendation_list()
    return read_json(M.RECO_FILE)
end

function M.recommendation_record(entry)
    local list = read_json(M.RECO_FILE)
    list[#list + 1] = {
        intent = entry.intent, params = entry.params, at = util.now_ms(),
    }
    while #list > M.MAX_ENTRIES do table.remove(list, 1) end
    return write_json(M.RECO_FILE, list)
end

function M.recommendation_feedback(id, feedback)
    local list = read_json(M.RECO_FILE)
    for _, r in ipairs(list) do
        if r.at == tonumber(id) then r.feedback = feedback end
    end
    return write_json(M.RECO_FILE, list)
end

-- ---- operation lesson ----
function M.lesson_record(entry)
    local list = read_json(M.LESSON_FILE)
    list[#list + 1] = {
        lesson = entry.lesson or entry.content,
        intent = entry.intent,
        at = util.now_ms(),
    }
    while #list > M.MAX_ENTRIES do table.remove(list, 1) end
    return write_json(M.LESSON_FILE, list)
end

function M.lesson_list()
    return read_json(M.LESSON_FILE)
end

return M
