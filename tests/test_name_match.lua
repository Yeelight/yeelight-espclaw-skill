-- tests/test_name_match.lua
local mock = require("tests.mock")
local name_match = require("name_match")

local items = {
    { name = "客厅吸顶灯", id = "d1" },
    { name = "卧室台灯", id = "d2" },
    { name = "客厅落地灯", id = "d3" },
}

local m = name_match.match_one("客厅吸顶灯", items)
mock.assert_eq(m.status, "exact", "exact match")
mock.assert_eq(m.item.id, "d1", "exact item")

-- 大小写/空格无关
m = name_match.match_one("客厅吸顶灯 ", items)
mock.assert_eq(m.status, "exact", "normalize spaces")

-- 包含匹配
m = name_match.match_one("吸顶灯", items)
mock.assert_eq(m.status, "exact", "substring unique")
mock.assert_eq(m.item.id, "d1", "substring item")

-- 歧义
m = name_match.match_one("客厅", items)
mock.assert_eq(m.status, "ambiguous", "ambiguous")
mock.assert(#m.candidates == 2, "two candidates")

-- 未找到
m = name_match.match_one("厨房炸锅", items)
mock.assert_eq(m.status, "not_found", "not found")

-- 别名：台灯 -> 床头灯
local alias_items = { { name = "床头灯", id = "b1" } }
m = name_match.match_one("台灯", alias_items)
mock.assert(m.status == "exact" or m.status == "ambiguous", "alias matches (score>0)")
mock.assert(name_match.score("台灯", "床头灯") >= 90, "alias score high")

-- 模糊
mock.assert(name_match.score("客厅吸顶灯", "客厅吸顶灯泡") >= 40, "fuzzy edit distance")

-- 候选标签
local labels = name_match.candidate_labels({ { name = "a", roomName = "r1" }, { name = "b" } })
mock.assert(labels:find("a(r1)", 1, true) ~= nil, "candidate label with room")
