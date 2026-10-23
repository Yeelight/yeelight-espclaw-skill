-- name_match.lua：名称归一化、别名、精确/模糊匹配与歧义判定。
local util = require("util")

local M = {}

M.MAX_CANDIDATES = 5

-- 高频别名（设备品类/常用叫法 -> 规范名），只保留轻量表
M.ALIASES = {
    ["主灯"] = { "吸顶灯", "吊灯" },
    ["台灯"] = { "床头灯", "阅读灯" },
    ["落地灯"] = { "立灯" },
    ["筒灯"] = { "射灯", "spot" },
    ["灯带"] = { "彩光灯带", "lightstrip" },
    ["吸顶灯"] = { "ceiling lamp" },
    ["窗帘"] = { "电动窗帘", "帘" },
    ["空调"] = { "冷暖空调", "ac" },
    ["面板"] = { "开关面板", "智能面板" },
    ["旋钮"] = { "调光旋钮", "smart knob" },
    ["网关"] = { "gateway", "蓝牙网关", "matter网关" },
    ["客厅"] = { "客廳", "living room" },
    ["卧室"] = { "主卧", "次卧", "bedroom" },
    ["书房"] = { "study" },
    ["全屋"] = { "所有", "全部" },
}

local function normalize(s)
    s = util.trim(tostring(s or "")):lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[，。！？、：；,.!?;:]", "")
    return s
end

-- 反向表：别名目标 -> 别名（如 床头灯 -> 台灯）
local REVERSE_ALIASES = {}
for alias, targets in pairs(M.ALIASES) do
    for _, t in ipairs(targets) do
        local tn = normalize(t)
        REVERSE_ALIASES[tn] = REVERSE_ALIASES[tn] or {}
        table.insert(REVERSE_ALIASES[tn], normalize(alias))
    end
end

function M.expand_aliases(name)
    local n = normalize(name)
    local out = { n }
    for _, t in ipairs(M.ALIASES[n] or {}) do out[#out + 1] = normalize(t) end
    for _, a in ipairs(REVERSE_ALIASES[n] or {}) do out[#out + 1] = a end
    return out
end

local function edit_distance_leq(a, b, k)
    -- 轻量判断：长度差 > k 直接 false；否则 DP（名称都较短，可接受）
    if math.abs(#a - #b) > k then return false end
    local prev, curr = {}, {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        curr[0] = i
        local row_min = i
        for j = 1, #b do
            local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
            local v = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            curr[j] = v
            if v < row_min then row_min = v end
        end
        if row_min > k then return false end
        prev, curr = curr, prev
    end
    return prev[#b] <= k
end

-- score：>=100 精确；50-99 包含；20-49 模糊；其余不匹配
function M.score(query, name)
    if query == nil or name == nil then return 0 end
    local q, n = normalize(query), normalize(name)
    if q == "" or n == "" then return 0 end
    if q == n then return 100 end
    if n:find(q, 1, true) then return 90 end
    if q:find(n, 1, true) then return 80 end
    -- 别名：query 的别名表 或 name 的别名表 命中对方
    for _, qv in ipairs(M.expand_aliases(query)) do
        if qv == n then return 95 end
    end
    for _, nv in ipairs(M.expand_aliases(name)) do
        if nv == q then return 95 end
    end
    local k = math.max(1, math.floor(#q / 4))
    if edit_distance_leq(q, n, k) then return 40 end
    return 0
end

-- items: {name=..., ...}；返回 matches = {{item=..., score=...}} 降序
function M.rank(query, items, name_key)
    name_key = name_key or "name"
    local matches = {}
    for _, item in ipairs(items or {}) do
        local s = M.score(query, item[name_key])
        if s > 0 then matches[#matches + 1] = { item = item, score = s } end
    end
    table.sort(matches, function(a, b) return a.score > b.score end)
    return matches
end

-- 匹配结果：{status="exact"|"ambiguous"|"not_found", item=?, candidates=?}
function M.match_one(query, items, name_key)
    if query == nil or query == "" then
        return { status = "not_found" }
    end
    local matches = M.rank(query, items, name_key)
    if #matches == 0 then return { status = "not_found" } end
    local best = matches[1].score
    local top = {}
    for _, m in ipairs(matches) do
        if m.score == best then top[#top + 1] = m.item end
    end
    if #top == 1 then
        return { status = "exact", item = top[1], score = best }
    end
    return { status = "ambiguous", candidates = util.slice(top, 1, M.MAX_CANDIDATES) }
end

function M.candidate_labels(candidates, name_key)
    name_key = name_key or "name"
    local labels = {}
    for i, c in ipairs(candidates or {}) do
        local label = tostring(c[name_key] or c.id or i)
        if c.roomName then label = label .. "(" .. tostring(c.roomName) .. ")" end
        labels[#labels + 1] = label
    end
    return table.concat(labels, "、")
end

return M
